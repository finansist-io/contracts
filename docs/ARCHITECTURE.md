# Architecture

## Scope

V1 is Base-only, USDC-accounted, spot long/flat and bound to one target asset per vault.
The vault never evaluates indicators, news or AI. Off-chain software decides whether to
request an operation; the vault decides whether that operation is authorized.

## Contracts

- `PersonalVaultV1` holds one owner's funds for one strategy lineage and one target asset.
- `VaultFactoryV1` creates deterministic ERC-1167 clones and initializes them atomically.
- `MarketRegistryV1` is an immutable set of exact token, factory, pool, router and quoter
  identities for one registry version.
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

The current registry pins address-level runtime code hashes. It does not yet prove the
Slipstream pool's token pair, factory parentage, observation capacity or proxy implementation
slot. Those checks are part of the Aerodrome integration change, not assumptions hidden in
deployment scripts.

There is never a generic `execute(bytes)` path. Aerodrome calls use a typed interface to one
registry-approved router and pool. A router ABI change requires a new vault version.
