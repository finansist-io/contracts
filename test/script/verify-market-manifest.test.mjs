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
  assert.equal(manifest.accountingAsset, "USDC");
  assert.equal(snapshot.accountingToken, manifest.tokens[manifest.accountingAsset].address.toLowerCase());
  assert.equal(Object.keys(snapshot.markets).length, manifest.marketCount);
  assert.deepEqual(Object.keys(snapshot.priceFeeds).sort(), Object.keys(manifest.tokens).sort());
  assert.equal(snapshot.priceFeeds.AERO.description, "AERO / USD");
  assert.equal(snapshot.priceFeeds.USDC.mutableSnapshot.answer, "99987455");
  assert.equal(snapshot.sequencerUptimeFeed.description, "L2 Sequencer Uptime Status Feed");
  assert.equal(snapshot.sequencerUptimeFeed.mutableSnapshot.answer, "0");
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

test("sequencer-feed disagreement fails before manifest comparison", () => {
  const first = expectedSnapshot(manifest);
  const second = structuredClone(first);
  second.sequencerUptimeFeed.mutableSnapshot.updatedAtUnixSeconds = "1786726256";

  assert.throws(() => verifyManifestAgainstSnapshots(manifest, first, second), /provider disagreement/);
});

test("manifest drift is rejected", () => {
  const snapshot = expectedSnapshot(manifest);
  const changed = structuredClone(manifest);
  changed.tokens[changed.accountingAsset].decimals = 18;

  assert.throws(() => verifyManifestAgainstSnapshots(changed, snapshot, snapshot), /manifest mismatch/);
});

test("an active label cannot be inferred from candidate evidence", () => {
  const changed = structuredClone(manifest);
  changed.status = "active";

  assert.throws(() => validateManifest(changed), /only candidate manifests/);
});

test("schema v2 is rejected after the sequencer cutover", () => {
  const changed = structuredClone(manifest);
  changed.schemaVersion = 2;

  assert.throws(() => validateManifest(changed), /unsupported manifest schema/);
});

test("accounting asset must name a token", () => {
  const changed = structuredClone(manifest);
  changed.accountingAsset = "UNKNOWN";

  assert.throws(() => validateManifest(changed), /unknown accounting asset/);
});

test("accounting asset cannot be a market target", () => {
  const changed = structuredClone(manifest);
  changed.markets[0].target = changed.accountingAsset;

  assert.throws(() => validateManifest(changed), /accounting asset cannot be a target/);
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

test("invalid sequencer evidence is rejected", () => {
  const unknownStatus = structuredClone(manifest);
  unknownStatus.sequencerUptimeFeed.mutableSnapshot.answer = "2";
  assert.throws(() => validateManifest(unknownStatus), /invalid sequencer status round/);

  const future = structuredClone(manifest);
  future.sequencerUptimeFeed.mutableSnapshot.updatedAtUnixSeconds = "1786737348";
  assert.throws(() => validateManifest(future), /invalid sequencer timestamps/);

  const incomplete = structuredClone(manifest);
  incomplete.sequencerUptimeFeed.mutableSnapshot.answeredInRound = "1";
  assert.throws(() => validateManifest(incomplete), /incomplete sequencer round/);
});

test("down sequencer status remains valid evidence", () => {
  const down = structuredClone(manifest);
  down.sequencerUptimeFeed.mutableSnapshot.answer = "1";

  assert.doesNotThrow(() => validateManifest(down));
});
