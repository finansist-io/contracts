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
