# Finansist contracts

Owner-controlled strategy vaults for Base.

Status: pre-deployment. No contract in this repository is approved for deposits or live
execution. The current code establishes custody, mandate, registry and accounting
boundaries. The checked-in Base market manifest is a verified candidate, not an active
deployment. It pins the five Chainlink Standard proxies and their explicit-block round
evidence plus the Base sequencer uptime identity and status evidence. Per-feed maximum ages
are registry-bound, and the non-executable Slipstream price guard has directional unit, fuzz
and pinned Base-fork proofs. Aerodrome execution remains absent until the remaining route and
protection policies are complete.

The current protection work is a non-executable prototype. It proves feed validation,
cross-USD ratio math, sequencer status/grace validation and Base-fork vectors. It is not live
protection until the price guard and final Base sequencer uptime policy are wired into the
complete entry/exit change.

```bash
forge fmt --check
forge lint
forge build --force
FOUNDRY_PROFILE=ci forge test --force
BASE_FORK_RPC_URL=... forge test --force --match-path 'test/fork/*.fork.t.sol'
node --test test/script/*.test.mjs
MANIFEST_RPC_URL_BLASTAPI_BASE_PUBLIC=... \
  MANIFEST_RPC_URL_TENDERLY_BASE_PUBLIC=... node script/verify-market-manifest.mjs
```

The manifest verifier requires Node.js 20 and Foundry's `cast` on `PATH`.

See `docs/ARCHITECTURE.md` and `docs/INVARIANTS.md` before changing money state or
authority.
