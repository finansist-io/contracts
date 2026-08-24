import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  expectedSnapshot,
  validateManifest,
  verifyManifestAgainstSnapshots
} from "../../script/verify-market-manifest.mjs";

const manifest = JSON.parse(await readFile("registry/base-mainnet-v1.candidate.json", "utf8"));

test("candidate manifest has a complete normalized snapshot", () => {
  validateManifest(manifest);
  const snapshot = expectedSnapshot(manifest);

  assert.equal(snapshot.chainId, 8453);
  assert.equal(snapshot.accountingToken, manifest.tokens.USDC.address.toLowerCase());
  assert.equal(Object.keys(snapshot.markets).length, manifest.marketCount);
  assert.deepEqual(Object.keys(snapshot.priceFeeds).sort(), Object.keys(manifest.tokens).sort());
  assert.equal(snapshot.priceFeeds.AERO.description, "AERO / USD");
  assert.equal(snapshot.priceFeeds.USDC.mutableSnapshot.answer, "99987455");
});

test("matching providers and manifest pass", () => {
  const snapshot = expectedSnapshot(manifest);
  assert.deepEqual(verifyManifestAgainstSnapshots(manifest, snapshot, structuredClone(snapshot)), snapshot);
});

test("provider disagreement fails before manifest comparison", () => {
  const first = expectedSnapshot(manifest);
  const second = structuredClone(first);
  second.markets[manifest.markets[0].marketId].mutableSnapshot.feePips += 1;

  assert.throws(() => verifyManifestAgainstSnapshots(manifest, first, second), /provider disagreement/);
});

test("price-feed disagreement fails before manifest comparison", () => {
  const first = expectedSnapshot(manifest);
  const second = structuredClone(first);
  second.priceFeeds.WETH.mutableSnapshot.updatedAtUnixSeconds = "1786736596";

  assert.throws(() => verifyManifestAgainstSnapshots(manifest, first, second), /provider disagreement/);
});

test("manifest drift is rejected", () => {
  const snapshot = expectedSnapshot(manifest);
  const changed = structuredClone(manifest);
  changed.tokens.USDC.decimals = 18;

  assert.throws(() => verifyManifestAgainstSnapshots(changed, snapshot, snapshot), /manifest mismatch/);
});

test("an active label cannot be inferred from candidate evidence", () => {
  const changed = structuredClone(manifest);
  changed.status = "active";

  assert.throws(() => validateManifest(changed), /only candidate manifests/);
});

test("every token has one standard feed and provider provenance has no RPC URL", () => {
  assert.equal(manifest.sources.chainlink.variant, "standard");
  assert.deepEqual(Object.keys(manifest.priceFeeds).sort(), Object.keys(manifest.tokens).sort());
  for (const provider of manifest.verificationProviders) {
    assert.deepEqual(Object.keys(provider).sort(), ["id", "operator"]);
  }
});

test("stale or incomplete feed evidence is rejected", () => {
  const stale = structuredClone(manifest);
  stale.priceFeeds.WETH.mutableSnapshot.startedAtUnixSeconds = "1786735900";
  stale.priceFeeds.WETH.mutableSnapshot.updatedAtUnixSeconds = "1786736000";
  assert.throws(() => validateManifest(stale), /exceeded catalog heartbeat/);

  const incomplete = structuredClone(manifest);
  incomplete.priceFeeds.WETH.mutableSnapshot.answeredInRound = "1";
  assert.throws(() => validateManifest(incomplete), /incomplete feed round/);
});
