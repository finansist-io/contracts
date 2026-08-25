#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const RPC_REQUEST_INTERVAL_MS = 500;
const DELIVERY_ALLOWANCE_BY_HEARTBEAT = new Map([
  [1_200, 300],
  [86_400, 3_600]
]);

const EXACT_INPUT_SINGLE_SELECTOR = functionSelector(
  "exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))"
);
const QUOTE_EXACT_INPUT_SINGLE_SELECTOR = functionSelector(
  "quoteExactInputSingle((address,address,uint256,int24,uint160))"
);

const selectors = {
  aggregator: functionSelector("aggregator()"),
  decimals: functionSelector("decimals()"),
  description: functionSelector("description()"),
  factory: functionSelector("factory()"),
  fee: functionSelector("fee()"),
  getPool: functionSelector("getPool(address,address,int24)"),
  latestRoundData: functionSelector("latestRoundData()"),
  poolImplementation: functionSelector("poolImplementation()"),
  slot0: functionSelector("slot0()"),
  swapFeeModule: functionSelector("swapFeeModule()"),
  tickSpacing: functionSelector("tickSpacing()"),
  token0: functionSelector("token0()"),
  token1: functionSelector("token1()"),
  typeAndVersion: functionSelector("typeAndVersion()"),
  version: functionSelector("version()")
};

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function normalizeHex(value) {
  invariant(typeof value === "string" && /^0x[0-9a-fA-F]+$/.test(value), `invalid hex: ${value}`);
  return value.toLowerCase();
}

function normalizeAddress(value) {
  const normalized = normalizeHex(value);
  invariant(/^0x[0-9a-f]{40}$/.test(normalized), `invalid address: ${value}`);
  return normalized;
}

function normalizeHash(value) {
  const normalized = normalizeHex(value);
  invariant(/^0x[0-9a-f]{64}$/.test(normalized), `invalid hash: ${value}`);
  return normalized;
}

function wordAddress(value) {
  return normalizeAddress(value).slice(2).padStart(64, "0");
}

function wordUint(value) {
  return BigInt(value).toString(16).padStart(64, "0");
}

function decodeAddress(value) {
  invariant(/^0x[0-9a-fA-F]{64}$/.test(value), `invalid address result: ${value}`);
  return normalizeAddress(`0x${value.slice(-40)}`);
}

function decodeUint(value) {
  invariant(/^0x[0-9a-fA-F]{64}$/.test(value), `invalid integer result: ${value}`);
  return Number(BigInt(value));
}

function decodeString(value) {
  const normalized = normalizeHex(value);
  const words = normalized.slice(2).match(/.{64}/g) ?? [];
  invariant(words.length >= 2, `invalid string result: ${value}`);
  const offset = Number(BigInt(`0x${words[0]}`));
  invariant(Number.isSafeInteger(offset) && offset % 32 === 0, `invalid string offset: ${value}`);
  const lengthWord = 2 + offset * 2;
  invariant(normalized.length >= lengthWord + 64, `invalid string length word: ${value}`);
  const length = Number(BigInt(`0x${normalized.slice(lengthWord, lengthWord + 64)}`));
  const textStart = lengthWord + 64;
  const textEnd = textStart + length * 2;
  invariant(Number.isSafeInteger(length) && normalized.length >= textEnd, `invalid string bytes: ${value}`);
  return Buffer.from(normalized.slice(textStart, textEnd), "hex").toString("utf8");
}

function decodeSignedWord(word) {
  const raw = BigInt(`0x${word}`);
  const signBit = BigInt(1) << BigInt(255);
  return (raw >= signBit ? raw - (BigInt(1) << BigInt(256)) : raw).toString();
}

function decodeRoundData(value) {
  const normalized = normalizeHex(value);
  const words = normalized.slice(2).match(/.{64}/g) ?? [];
  invariant(words.length === 5, `invalid round result: ${value}`);
  return {
    roundId: BigInt(`0x${words[0]}`).toString(),
    answer: decodeSignedWord(words[1]),
    startedAtUnixSeconds: BigInt(`0x${words[2]}`).toString(),
    updatedAtUnixSeconds: BigInt(`0x${words[3]}`).toString(),
    answeredInRound: BigInt(`0x${words[4]}`).toString()
  };
}

function canonicalUint(value, label) {
  invariant(typeof value === "string" && /^(?:0|[1-9][0-9]*)$/.test(value), `invalid ${label}`);
  return BigInt(value);
}

function canonicalInt(value, label) {
  invariant(typeof value === "string" && /^(?:0|-?[1-9][0-9]*)$/.test(value), `invalid ${label}`);
  return BigInt(value);
}

function decodeSlot0(value) {
  const words = value.slice(2).match(/.{64}/g) ?? [];
  invariant(words.length >= 5, `invalid slot0 result: ${value}`);
  return {
    sqrtPriceX96: BigInt(`0x${words[0]}`).toString(),
    tick: Number(decodeSignedWord(words[1])),
    observationCardinality: Number(BigInt(`0x${words[3]}`)),
    observationCardinalityNext: Number(BigInt(`0x${words[4]}`))
  };
}

function runtimeCodeHash(code) {
  invariant(/^0x[0-9a-fA-F]+$/.test(code) && code !== "0x", "empty runtime code");
  return normalizeHash(runCast(["keccak", code]));
}

function textHash(value) {
  return normalizeHash(runCast(["keccak", value]));
}

function functionSelector(signature) {
  const selector = normalizeHex(runCast(["sig", signature]));
  invariant(/^0x[0-9a-f]{8}$/.test(selector), `invalid selector for ${signature}`);
  return selector;
}

function runCast(arguments_) {
  try {
    return execFileSync("cast", arguments_, { encoding: "utf8" }).trim();
  } catch (error) {
    throw new Error("Foundry cast is required on PATH", { cause: error });
  }
}

function firstDifference(expected, actual, path = "snapshot") {
  if (Object.is(expected, actual)) return null;
  if (typeof expected !== "object" || expected === null || typeof actual !== "object" || actual === null) {
    return `${path}: expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`;
  }
  const keys = new Set([...Object.keys(expected), ...Object.keys(actual)]);
  for (const key of keys) {
    const difference = firstDifference(expected[key], actual[key], `${path}.${key}`);
    if (difference) return difference;
  }
  return null;
}

export function validateManifest(manifest) {
  invariant(manifest.schemaVersion === 4, "unsupported manifest schema");
  invariant(manifest.status === "candidate", "only candidate manifests can be verified");
  invariant(textHash(manifest.registryId) === normalizeHash(manifest.registryIdHash), "wrong registry id hash");
  invariant(Number.isSafeInteger(manifest.chainId) && manifest.chainId > 0, "invalid chain id");
  invariant(Number.isSafeInteger(manifest.verificationBlock?.number), "invalid verification block");
  normalizeHash(manifest.verificationBlock.hash);
  invariant(!Number.isNaN(Date.parse(manifest.verificationBlock.timestamp)), "invalid verification timestamp");
  invariant(manifest.selectors?.exactInputSingle === EXACT_INPUT_SINGLE_SELECTOR, "wrong swap selector");
  invariant(
    manifest.selectors?.quoteExactInputSingle === QUOTE_EXACT_INPUT_SINGLE_SELECTOR,
    "wrong quoter selector"
  );
  invariant(Object.keys(manifest.tokens ?? {}).length > 0, "tokens are required");
  invariant(Object.keys(manifest.priceFeeds ?? {}).length > 0, "price feeds are required");
  invariant(Object.keys(manifest.deployments ?? {}).length > 0, "deployments are required");
  invariant(Array.isArray(manifest.markets) && manifest.markets.length > 0, "markets are required");
  invariant(manifest.marketCount === manifest.markets.length, "wrong market count");
  invariant(
    /^[0-9a-f]{64}$/.test(manifest.sources?.chainlink?.directorySha256 ?? ""),
    "invalid Chainlink directory hash"
  );
  invariant(manifest.sources?.chainlink?.variant === "standard", "only Chainlink standard feeds are supported");
  invariant(
    /^[0-9a-f]{40}$/.test(manifest.sources?.chainlink?.sequencerDocumentationCommit ?? ""),
    "invalid sequencer documentation commit"
  );
  invariant(
    manifest.sources?.chainlink?.sequencerDocumentationPath === "src/content/data-feeds/l2-sequencer-feeds.mdx",
    "invalid sequencer documentation path"
  );
  invariant(
    /^[0-9a-f]{40}$/.test(manifest.sources?.chainlink?.freshnessDocumentationCommit ?? ""),
    "invalid freshness documentation commit"
  );
  invariant(
    manifest.sources?.chainlink?.freshnessDocumentationPath === "src/content/data-feeds/index.mdx",
    "invalid freshness documentation path"
  );
  invariant(Array.isArray(manifest.verificationProviders) && manifest.verificationProviders.length === 2, "two providers required");
  for (const provider of manifest.verificationProviders) {
    invariant(/^[a-z0-9-]+$/.test(provider.id), "invalid verification provider id");
    invariant(typeof provider.operator === "string" && provider.operator.length > 0, "invalid verification provider operator");
  }
  invariant(
    new Set(manifest.verificationProviders.map((provider) => provider.id)).size === 2
      && new Set(manifest.verificationProviders.map((provider) => provider.operator)).size === 2,
    "verification providers must be independent"
  );

  for (const [symbol, token] of Object.entries(manifest.tokens)) {
    invariant(symbol.length > 0, "empty token symbol");
    normalizeAddress(token.address);
    normalizeHash(token.codeHash);
    invariant(Number.isInteger(token.decimals) && token.decimals >= 0 && token.decimals <= 18, "invalid decimals");
  }
  invariant(
    typeof manifest.accountingAsset === "string" && manifest.tokens[manifest.accountingAsset],
    "unknown accounting asset"
  );

  const tokenSymbols = Object.keys(manifest.tokens).sort();
  const feedSymbols = Object.keys(manifest.priceFeeds).sort();
  invariant(
    tokenSymbols.length === feedSymbols.length && tokenSymbols.every((symbol, index) => symbol === feedSymbols[index]),
    "every token requires exactly one price feed"
  );
  const blockTimestamp = BigInt(Math.floor(Date.parse(manifest.verificationBlock.timestamp) / 1000));
  for (const [symbol, feed] of Object.entries(manifest.priceFeeds)) {
    invariant(/^[a-z0-9-]+$/.test(feed.catalogPath), `invalid catalog path: ${symbol}`);
    invariant(
      Number.isSafeInteger(feed.catalogHeartbeatSeconds) && feed.catalogHeartbeatSeconds > 0,
      `invalid catalog heartbeat: ${symbol}`
    );
    const deliveryAllowance = DELIVERY_ALLOWANCE_BY_HEARTBEAT.get(feed.catalogHeartbeatSeconds);
    invariant(
      deliveryAllowance !== undefined && feed.maxAgeSeconds === feed.catalogHeartbeatSeconds + deliveryAllowance,
      `invalid maximum age: ${symbol}`
    );
    normalizeAddress(feed.proxy.address);
    normalizeHash(feed.proxy.codeHash);
    invariant(textHash(feed.description) === normalizeHash(feed.descriptionHash), `wrong description hash: ${symbol}`);
    invariant(Number.isInteger(feed.decimals) && feed.decimals > 0 && feed.decimals <= 18, `invalid feed decimals: ${symbol}`);
    invariant(Number.isSafeInteger(feed.version) && feed.version > 0, `invalid feed version: ${symbol}`);
    normalizeAddress(feed.mutableSnapshot.aggregator.address);
    normalizeHash(feed.mutableSnapshot.aggregator.codeHash);
    invariant(feed.mutableSnapshot.aggregator.typeAndVersion.length > 0, `empty aggregator type: ${symbol}`);
    const roundId = canonicalUint(feed.mutableSnapshot.roundId, `round id: ${symbol}`);
    const answer = canonicalInt(feed.mutableSnapshot.answer, `round answer: ${symbol}`);
    const startedAt = canonicalUint(feed.mutableSnapshot.startedAtUnixSeconds, `round start: ${symbol}`);
    const updatedAt = canonicalUint(feed.mutableSnapshot.updatedAtUnixSeconds, `round update: ${symbol}`);
    const answeredInRound = canonicalUint(feed.mutableSnapshot.answeredInRound, `answered round: ${symbol}`);
    invariant(roundId > 0 && answer > 0, `invalid feed round: ${symbol}`);
    invariant(startedAt > 0 && startedAt <= updatedAt && updatedAt <= blockTimestamp, `invalid feed timestamps: ${symbol}`);
    invariant(answeredInRound >= roundId, `incomplete feed round: ${symbol}`);
    invariant(
      blockTimestamp - updatedAt <= BigInt(feed.catalogHeartbeatSeconds),
      `feed exceeded catalog heartbeat at verification block: ${symbol}`
    );
  }

  const sequencer = manifest.sequencerUptimeFeed;
  normalizeAddress(sequencer?.proxy?.address);
  normalizeHash(sequencer?.proxy?.codeHash);
  invariant(
    textHash(sequencer?.description) === normalizeHash(sequencer?.descriptionHash),
    "wrong sequencer description hash"
  );
  invariant(sequencer?.decimals === 0, "invalid sequencer feed decimals");
  invariant(Number.isSafeInteger(sequencer?.version) && sequencer.version > 0, "invalid sequencer feed version");
  normalizeAddress(sequencer?.mutableSnapshot?.aggregator?.address);
  normalizeHash(sequencer?.mutableSnapshot?.aggregator?.codeHash);
  invariant(sequencer?.mutableSnapshot?.aggregator?.typeAndVersion.length > 0, "empty sequencer aggregator type");
  const sequencerRoundId = canonicalUint(sequencer?.mutableSnapshot?.roundId, "sequencer round id");
  const sequencerAnswer = canonicalInt(sequencer?.mutableSnapshot?.answer, "sequencer round answer");
  const sequencerStartedAt = canonicalUint(sequencer?.mutableSnapshot?.startedAtUnixSeconds, "sequencer round start");
  const sequencerUpdatedAt = canonicalUint(sequencer?.mutableSnapshot?.updatedAtUnixSeconds, "sequencer round update");
  const sequencerAnsweredInRound = canonicalUint(
    sequencer?.mutableSnapshot?.answeredInRound,
    "sequencer answered round"
  );
  invariant(
    sequencerRoundId > 0 && (sequencerAnswer === 0n || sequencerAnswer === 1n),
    "invalid sequencer status round"
  );
  invariant(
    sequencerStartedAt > 0 && sequencerStartedAt <= sequencerUpdatedAt && sequencerUpdatedAt <= blockTimestamp,
    "invalid sequencer timestamps"
  );
  invariant(sequencerAnsweredInRound >= sequencerRoundId, "incomplete sequencer round");

  for (const deployment of Object.values(manifest.deployments)) {
    for (const component of ["factory", "poolImplementation", "router", "quoter"]) {
      normalizeAddress(deployment[component]?.address);
      normalizeHash(deployment[component]?.codeHash);
    }
    normalizeAddress(deployment.mutableSnapshot?.swapFeeModule?.address);
    normalizeHash(deployment.mutableSnapshot?.swapFeeModule?.codeHash);
  }

  const marketIds = new Set();
  for (const market of manifest.markets) {
    invariant(!marketIds.has(market.marketId), `duplicate market: ${market.marketId}`);
    marketIds.add(market.marketId);
    invariant(manifest.tokens[market.target], `unknown target: ${market.target}`);
    invariant(market.target !== manifest.accountingAsset, `accounting asset cannot be a target: ${market.marketId}`);
    invariant(manifest.deployments[market.deployment], `unknown deployment: ${market.deployment}`);
    invariant(textHash(market.marketId) === normalizeHash(market.marketIdHash), `wrong market id hash: ${market.marketId}`);
    normalizeAddress(market.pool.address);
    normalizeHash(market.pool.codeHash);
    normalizeAddress(market.pool.token0);
    normalizeAddress(market.pool.token1);
    invariant(Number.isInteger(market.pool.tickSpacing) && market.pool.tickSpacing > 0, "invalid tick spacing");
    invariant(Number.isInteger(market.mutableSnapshot?.feePips), "invalid fee snapshot");
    const sqrtPriceX96 = canonicalUint(market.mutableSnapshot?.sqrtPriceX96, "sqrt price snapshot");
    invariant(
      sqrtPriceX96 > 4_295_128_739n
        && sqrtPriceX96 < 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342n,
      "invalid sqrt price snapshot"
    );
    invariant(
      Number.isInteger(market.mutableSnapshot?.tick)
        && market.mutableSnapshot.tick >= -887_272
        && market.mutableSnapshot.tick <= 887_272,
      "invalid tick snapshot"
    );
    invariant(Number.isInteger(market.mutableSnapshot?.observationCardinality), "invalid observation snapshot");
    invariant(Number.isInteger(market.mutableSnapshot?.observationCardinalityNext), "invalid observation snapshot");
    invariant(market.mutableSnapshot.feePips >= 0 && market.mutableSnapshot.feePips <= 1_000_000, "invalid fee snapshot");
    invariant(market.mutableSnapshot.observationCardinality > 0, "empty observation snapshot");
    invariant(
      market.mutableSnapshot.observationCardinalityNext >= market.mutableSnapshot.observationCardinality,
      "invalid observation growth snapshot"
    );

    const pair = [manifest.tokens[manifest.accountingAsset].address, manifest.tokens[market.target].address]
      .map(normalizeAddress)
      .sort();
    invariant(normalizeAddress(market.pool.token0) === pair[0], `wrong token0: ${market.marketId}`);
    invariant(normalizeAddress(market.pool.token1) === pair[1], `wrong token1: ${market.marketId}`);
  }
}

export function expectedSnapshot(manifest) {
  validateManifest(manifest);
  const tokens = Object.fromEntries(
    Object.entries(manifest.tokens).map(([symbol, token]) => [
      symbol,
      { address: normalizeAddress(token.address), decimals: token.decimals, codeHash: normalizeHash(token.codeHash) }
    ])
  );
  const deployments = Object.fromEntries(
    Object.entries(manifest.deployments).map(([name, deployment]) => [
      name,
      {
        factory: normalizedComponent(deployment.factory),
        poolImplementation: normalizedComponent(deployment.poolImplementation),
        router: { ...normalizedComponent(deployment.router), factory: normalizeAddress(deployment.factory.address) },
        quoter: { ...normalizedComponent(deployment.quoter), factory: normalizeAddress(deployment.factory.address) },
        swapFeeModule: normalizedComponent(deployment.mutableSnapshot.swapFeeModule)
      }
    ])
  );
  const priceFeeds = Object.fromEntries(
    Object.entries(manifest.priceFeeds).map(([symbol, feed]) => [symbol, normalizedFeedSnapshot(feed)])
  );
  const sequencerUptimeFeed = normalizedFeedSnapshot(manifest.sequencerUptimeFeed);
  const accountingToken = tokens[manifest.accountingAsset];
  const markets = Object.fromEntries(
    manifest.markets.map((market) => {
      const deployment = deployments[market.deployment];
      return [
        market.marketId,
        {
          marketIdHash: normalizeHash(market.marketIdHash),
          target: market.target,
          deployment: market.deployment,
          pool: {
            ...normalizedComponent(market.pool),
            token0: normalizeAddress(market.pool.token0),
            token1: normalizeAddress(market.pool.token1),
            tickSpacing: market.pool.tickSpacing,
            factory: deployment.factory.address,
            factoryRoundTrip: normalizeAddress(market.pool.address)
          },
          mutableSnapshot: { ...market.mutableSnapshot }
        }
      ];
    })
  );
  return {
    chainId: manifest.chainId,
    block: {
      number: manifest.verificationBlock.number,
      hash: normalizeHash(manifest.verificationBlock.hash),
      timestamp: manifest.verificationBlock.timestamp
    },
    accountingToken: accountingToken.address,
    tokens,
    priceFeeds,
    sequencerUptimeFeed,
    deployments,
    markets
  };
}

function normalizedComponent(component) {
  return { address: normalizeAddress(component.address), codeHash: normalizeHash(component.codeHash) };
}

function normalizedFeedSnapshot(feed) {
  return {
    proxy: normalizedComponent(feed.proxy),
    description: feed.description,
    descriptionHash: normalizeHash(feed.descriptionHash),
    decimals: feed.decimals,
    version: feed.version,
    mutableSnapshot: {
      aggregator: {
        ...normalizedComponent(feed.mutableSnapshot.aggregator),
        typeAndVersion: feed.mutableSnapshot.aggregator.typeAndVersion
      },
      roundId: feed.mutableSnapshot.roundId,
      answer: feed.mutableSnapshot.answer,
      startedAtUnixSeconds: feed.mutableSnapshot.startedAtUnixSeconds,
      updatedAtUnixSeconds: feed.mutableSnapshot.updatedAtUnixSeconds,
      answeredInRound: feed.mutableSnapshot.answeredInRound
    }
  };
}

export function verifyManifestAgainstSnapshots(manifest, first, second) {
  const expected = expectedSnapshot(manifest);
  const providerDifference = firstDifference(first, second, "providers");
  invariant(!providerDifference, `provider disagreement: ${providerDifference}`);
  const manifestDifference = firstDifference(expected, first);
  invariant(!manifestDifference, `manifest mismatch: ${manifestDifference}`);
  return expected;
}

class RpcClient {
  constructor(url, label) {
    this.url = url;
    this.label = label;
    this.id = 1;
    this.nextRequestAt = 0;
  }

  async request(method, params) {
    const payload = { jsonrpc: "2.0", id: this.id++, method, params };
    let lastError;
    for (let attempt = 1; attempt <= 4; attempt += 1) {
      await this.waitForRequestSlot();
      try {
        const response = await fetch(this.url, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(15_000)
        });
        const body = await response.json();
        if (response.ok && body.result !== undefined) return body.result;
        lastError = new Error(body.error?.message ?? `HTTP ${response.status}`);
      } catch (error) {
        lastError = error;
      }
      await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
    }
    const callTarget = method === "eth_call" ? ` ${params[0].to} ${params[0].data}` : "";
    throw new Error(`${this.label} ${method}${callTarget} failed after 4 attempts`, { cause: lastError });
  }

  async waitForRequestSlot() {
    const waitMs = Math.max(0, this.nextRequestAt - Date.now());
    if (waitMs > 0) await new Promise((resolve) => setTimeout(resolve, waitMs));
    this.nextRequestAt = Date.now() + RPC_REQUEST_INTERVAL_MS;
  }
}

async function readSnapshot(manifest, rpcUrl, label) {
  const client = new RpcClient(rpcUrl, label);
  const blockTag = `0x${manifest.verificationBlock.number.toString(16)}`;
  const chainId = Number(BigInt(await client.request("eth_chainId", [])));
  const block = await client.request("eth_getBlockByNumber", [blockTag, false]);
  invariant(block, "verification block is unavailable");

  const codeComponent = async (address) => {
    const normalized = normalizeAddress(address);
    const code = await client.request("eth_getCode", [normalized, blockTag]);
    return { address: normalized, codeHash: runtimeCodeHash(code) };
  };
  const call = (address, data) => client.request("eth_call", [{ to: normalizeAddress(address), data }, blockTag]);

  const tokens = {};
  for (const [symbol, token] of Object.entries(manifest.tokens)) {
    tokens[symbol] = {
      ...(await codeComponent(token.address)),
      decimals: decodeUint(await call(token.address, selectors.decimals))
    };
  }

  const deployments = {};
  for (const [name, deployment] of Object.entries(manifest.deployments)) {
    const factory = await codeComponent(deployment.factory.address);
    const implementationAddress = decodeAddress(await call(factory.address, selectors.poolImplementation));
    const feeModuleAddress = decodeAddress(await call(factory.address, selectors.swapFeeModule));
    deployments[name] = {
      factory,
      poolImplementation: await codeComponent(implementationAddress),
      router: {
        ...(await codeComponent(deployment.router.address)),
        factory: decodeAddress(await call(deployment.router.address, selectors.factory))
      },
      quoter: {
        ...(await codeComponent(deployment.quoter.address)),
        factory: decodeAddress(await call(deployment.quoter.address, selectors.factory))
      },
      swapFeeModule: await codeComponent(feeModuleAddress)
    };
  }

  const readFeedSnapshot = async (feed) => {
    const proxy = await codeComponent(feed.proxy.address);
    const aggregatorAddress = decodeAddress(await call(proxy.address, selectors.aggregator));
    const description = decodeString(await call(proxy.address, selectors.description));
    return {
      proxy,
      description,
      descriptionHash: textHash(description),
      decimals: decodeUint(await call(proxy.address, selectors.decimals)),
      version: decodeUint(await call(proxy.address, selectors.version)),
      mutableSnapshot: {
        aggregator: {
          ...(await codeComponent(aggregatorAddress)),
          typeAndVersion: decodeString(await call(aggregatorAddress, selectors.typeAndVersion))
        },
        ...decodeRoundData(await call(proxy.address, selectors.latestRoundData))
      }
    };
  };

  const priceFeeds = {};
  for (const [symbol, feed] of Object.entries(manifest.priceFeeds)) {
    priceFeeds[symbol] = await readFeedSnapshot(feed);
  }
  const sequencerUptimeFeed = await readFeedSnapshot(manifest.sequencerUptimeFeed);

  const accountingToken = normalizeAddress(manifest.tokens[manifest.accountingAsset].address);
  const markets = {};
  for (const market of manifest.markets) {
    const deployment = deployments[market.deployment];
    const targetToken = normalizeAddress(manifest.tokens[market.target].address);
    const getPoolData = `${selectors.getPool}${wordAddress(accountingToken)}${wordAddress(targetToken)}${wordUint(
      market.pool.tickSpacing
    )}`;
    const slot0 = decodeSlot0(await call(market.pool.address, selectors.slot0));
    markets[market.marketId] = {
      marketIdHash: normalizeHash(market.marketIdHash),
      target: market.target,
      deployment: market.deployment,
      pool: {
        ...(await codeComponent(market.pool.address)),
        token0: decodeAddress(await call(market.pool.address, selectors.token0)),
        token1: decodeAddress(await call(market.pool.address, selectors.token1)),
        tickSpacing: decodeUint(await call(market.pool.address, selectors.tickSpacing)),
        factory: decodeAddress(await call(market.pool.address, selectors.factory)),
        factoryRoundTrip: decodeAddress(await call(deployment.factory.address, getPoolData))
      },
      mutableSnapshot: {
        feePips: decodeUint(await call(market.pool.address, selectors.fee)),
        ...slot0
      }
    };
  }

  return {
    chainId,
    block: {
      number: Number(BigInt(block.number)),
      hash: normalizeHash(block.hash),
      timestamp: new Date(Number(BigInt(block.timestamp)) * 1000).toISOString()
    },
    accountingToken,
    tokens,
    priceFeeds,
    sequencerUptimeFeed,
    deployments,
    markets
  };
}

async function main() {
  const manifestPath = process.argv[2] ?? "registry/base-mainnet-v1.candidate.json";
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  validateManifest(manifest);
  const providerEnvName = (id) => `MANIFEST_RPC_URL_${id.toUpperCase().replace(/[^A-Z0-9]/g, "_")}`;
  invariant(Array.isArray(manifest.verificationProviders) && manifest.verificationProviders.length === 2, "two providers required");
  const [firstProvider, secondProvider] = manifest.verificationProviders;
  const firstRpc = process.env[providerEnvName(firstProvider.id)];
  const secondRpc = process.env[providerEnvName(secondProvider.id)];
  invariant(firstRpc && secondRpc && firstRpc !== secondRpc, "two distinct registry RPC URLs are required");

  const [first, second] = await Promise.all([
    readSnapshot(manifest, firstRpc, firstProvider.id),
    readSnapshot(manifest, secondRpc, secondProvider.id)
  ]);
  verifyManifestAgainstSnapshots(manifest, first, second);
  console.log(
    `verified ${manifest.registryId} candidate with ${firstProvider.id} + ${secondProvider.id} at block `
      + `${manifest.verificationBlock.number} ${manifest.verificationBlock.hash}`
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
