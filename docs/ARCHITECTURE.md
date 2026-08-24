# Architecture

## Scope

V1 is Base-only, USDC-accounted, spot long/flat and bound to one target asset per vault.
The vault never evaluates indicators, news or AI. Off-chain software decides whether to
request an operation; the vault decides whether that operation is authorized.

## Contracts

- `PersonalVaultV1` holds one owner's funds for one strategy lineage and one target asset.
- `VaultFactoryV1` creates deterministic ERC-1167 clones and initializes them atomically.
- `MarketRegistryV1` is an immutable set of exact token, factory, pool and router identities
  for one registry version.
- `EntryGuard` can stop new entries. It cannot move funds or block revoke, withdrawal or
  exit paths.

Vault clones point permanently to one implementation. There is no beacon, proxy admin or
upgrade function. A future implementation is a new factory and an owner-chosen migration.

## Current boundary

Custody, idle-USDC accounting, high-water-mark flow adjustments, immutable market binding,
mandate activation/revocation and deterministic factory deployment are implemented. Position
and crystallized-claim storage will be added with the entry/exit transition that can change it;
the foundation does not carry dead money fields.

Entry, exit, price protection, signed owner requests, fee crystallization and terminal raw
recovery are not yet callable. They must not be added until their complete state transition
and adversarial tests land in the same change.

The registry constructor verifies token decimals and runtime code hashes, exact pool token
ordering and tick spacing, pool factory identity, the factory's pool lookup and the router's
factory identity. The registry contract version also pins the one typed
`exactInputSingle` ABI selector. The candidate manifest separately pins the quoter, pool
implementation, fee module and explicit-block fee and observation snapshots through two
independent RPCs. Mutable snapshots are evidence, not contract guarantees.

Launch policy selects one candidate market using the expected operation size before vault
creation. Vault creation binds that market permanently; simulation and live execution do not
reselect a pool per operation. No checked-in registry is active yet.

There is never a generic `execute(bytes)` path. Aerodrome calls use a typed interface to one
registry-approved router and pool. A router ABI change requires a new vault version.
