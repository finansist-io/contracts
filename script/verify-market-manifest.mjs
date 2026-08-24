#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const RPC_REQUEST_INTERVAL_MS = 500;

const EXACT_INPUT_SINGLE_SELECTOR = functionSelector(
  "exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))"
);
const QUOTE_EXACT_INPUT_SINGLE_SELECTOR = functionSelector(
  "quoteExactInputSingle((address,address,uint256,int24,uint160))"
);

const selectors = {
  decimals: functionSelector("decimals()"),
  factory: functionSelector("factory()"),
  fee: functionSelector("fee()"),
  getPool: functionSelector("getPool(address,address,int24)"),
  poolImplementation: functionSelector("poolImplementation()"),
  slot0: functionSelector("slot0()"),
  swapFeeModule: functionSelector("swapFeeModule()"),
  tickSpacing: functionSelector("tickSpacing()"),
  token0: functionSelector("token0()"),
  token1: functionSelector("token1()")
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

function decodeSlot0(value) {
  const words = value.slice(2).match(/.{64}/g) ?? [];
  invariant(words.length >= 5, `invalid slot0 result: ${value}`);
  return {
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
  invariant(manifest.schemaVersion === 1, "unsupported manifest schema");
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
  invariant(Object.keys(manifest.deployments ?? {}).length > 0, "deployments are required");
  invariant(Array.isArray(manifest.markets) && manifest.markets.length > 0, "markets are required");
  invariant(manifest.marketCount === manifest.markets.length, "wrong market count");

  for (const [symbol, token] of Object.entries(manifest.tokens)) {
    invariant(symbol.length > 0, "empty token symbol");
    normalizeAddress(token.address);
    normalizeHash(token.codeHash);
    invariant(Number.isInteger(token.decimals) && token.decimals >= 0 && token.decimals <= 255, "invalid decimals");
  }

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
    invariant(manifest.deployments[market.deployment], `unknown deployment: ${market.deployment}`);
    invariant(textHash(market.marketId) === normalizeHash(market.marketIdHash), `wrong market id hash: ${market.marketId}`);
    normalizeAddress(market.pool.address);
    normalizeHash(market.pool.codeHash);
    normalizeAddress(market.pool.token0);
    normalizeAddress(market.pool.token1);
    invariant(Number.isInteger(market.pool.tickSpacing) && market.pool.tickSpacing > 0, "invalid tick spacing");
    invariant(Number.isInteger(market.mutableSnapshot?.feePips), "invalid fee snapshot");
    invariant(Number.isInteger(market.mutableSnapshot?.observationCardinality), "invalid observation snapshot");
    invariant(Number.isInteger(market.mutableSnapshot?.observationCardinalityNext), "invalid observation snapshot");
    invariant(market.mutableSnapshot.feePips >= 0 && market.mutableSnapshot.feePips <= 1_000_000, "invalid fee snapshot");
    invariant(market.mutableSnapshot.observationCardinality > 0, "empty observation snapshot");
    invariant(
      market.mutableSnapshot.observationCardinalityNext >= market.mutableSnapshot.observationCardinality,
      "invalid observation growth snapshot"
    );

    const pair = [manifest.tokens.USDC.address, manifest.tokens[market.target].address]
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
  const accountingToken = tokens.USDC;
  invariant(accountingToken, "USDC accounting token is required");
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
    deployments,
    markets
  };
}

function normalizedComponent(component) {
  return { address: normalizeAddress(component.address), codeHash: normalizeHash(component.codeHash) };
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

  const accountingToken = normalizeAddress(manifest.tokens.USDC.address);
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
    deployments,
    markets
  };
}

async function main() {
  const manifestPath = process.argv[2] ?? "registry/base-mainnet-v1.candidate.json";
  const firstRpc = process.env.MANIFEST_RPC_URL_A;
  const secondRpc = process.env.MANIFEST_RPC_URL_B;
  invariant(firstRpc && secondRpc && firstRpc !== secondRpc, "two distinct registry RPC URLs are required");

  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const [first, second] = await Promise.all([
    readSnapshot(manifest, firstRpc, "provider A"),
    readSnapshot(manifest, secondRpc, "provider B")
  ]);
  verifyManifestAgainstSnapshots(manifest, first, second);
  console.log(
    `verified ${manifest.registryId} candidate at block ${manifest.verificationBlock.number} ${manifest.verificationBlock.hash}`
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
