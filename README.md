# Finansist contracts

Owner-controlled strategy vaults for Base.

Status: pre-deployment. No contract in this repository is approved for deposits or live
execution. The current code establishes custody, mandate, registry and accounting
boundaries. The checked-in Base market manifest is a verified candidate, not an active
deployment. It pins the five Chainlink Standard proxies and their explicit-block round
evidence plus the Base sequencer uptime identity and status evidence, without freezing the
still-open maximum-age or recovery-grace policy. Aerodrome execution remains absent until
route and price-protection policies are frozen and tested.

The current protection work is a non-executable prototype. It proves feed validation,
cross-USD ratio math, sequencer status/grace validation and Base-fork vectors. It is not live
protection until maximum ages and the Base sequencer uptime policy are frozen and wired into
the complete entry/exit change.

```bash
forge build
forge lint
forge test
FOUNDRY_PROFILE=ci forge test
BASE_FORK_RPC_URL=... forge test --match-path 'test/fork/*.fork.t.sol'
node --test test/script/*.test.mjs
MANIFEST_RPC_URL_BLASTAPI_BASE_PUBLIC=... \
  MANIFEST_RPC_URL_TENDERLY_BASE_PUBLIC=... node script/verify-market-manifest.mjs
```

The manifest verifier requires Node.js 20 and Foundry's `cast` on `PATH`.

See `docs/ARCHITECTURE.md` and `docs/INVARIANTS.md` before changing money state or
authority.
