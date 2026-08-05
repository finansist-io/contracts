# Finansist contracts

Owner-controlled strategy vaults for Base.

Status: pre-deployment. No contract in this repository is approved for deposits or live
execution. The current code establishes custody, mandate, registry and accounting
boundaries. Aerodrome execution remains absent until the exact Slipstream deployment and
independent price-protection rule are frozen and tested.

```bash
forge build
forge test
FOUNDRY_PROFILE=ci forge test
```

See `docs/ARCHITECTURE.md` and `docs/INVARIANTS.md` before changing money state or
authority.
