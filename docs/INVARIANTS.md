# Invariants

These rules are release blockers, not operational preferences.

1. Only the owner can authorize mandates or move owner-accounted funds.
2. An executor can never select an arbitrary token, pool, router, recipient or calldata.
3. A vault is permanently bound to one accounting token, target token, strategy lineage,
   market and registry version.
4. Raw ERC-20 balances are not accounting state. Donations are surplus and cannot create
   profit, fees or execution authority.
5. Accounted owner USDC never exceeds the vault's USDC balance.
6. Deposits increase the high-water mark by the amount received. Owner withdrawals reduce
   it by the amount withdrawn, saturating at zero.
7. Entry pause is consulted only for entry readiness. It cannot block mandate revocation,
   idle withdrawal or surplus recovery.
8. Existing vault bytecode cannot be upgraded by Finansist or a registry administrator.

Position backing, realized-profit fee math and exit/recovery invariants land together with
the executable entry/exit transition. They are not predeclared as implemented behavior.
