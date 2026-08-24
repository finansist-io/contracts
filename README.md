# Finansist contracts

Owner-controlled strategy vaults for Base.

Status: pre-deployment. No contract in this repository is approved for deposits or live
execution. The current code establishes custody, mandate, registry and accounting
boundaries. The checked-in Base market manifest is a verified candidate, not an active
deployment. Aerodrome execution remains absent until route and price-protection policies are
frozen and tested.

```bash
forge build
forge lint
forge test
FOUNDRY_PROFILE=ci forge test
node --test test/script/*.test.mjs
MANIFEST_RPC_URL_A=... MANIFEST_RPC_URL_B=... node script/verify-market-manifest.mjs
```

The manifest verifier requires Node.js 20 and Foundry's `cast` on `PATH`.

See `docs/ARCHITECTURE.md` and `docs/INVARIANTS.md` before changing money state or
authority.
