# Architecture

## Scope

V1 is Base-only, USDC-accounted, spot long/flat and bound to one target asset per vault.
The vault never evaluates indicators, news or AI. Off-chain software decides whether to
request an operation; the vault decides whether that operation is authorized.

## Contracts

- `PersonalVaultV1` holds one owner's funds for one strategy lineage and one target asset.
- `VaultFactoryV1` creates deterministic ERC-1167 clones and initializes them atomically.
- `MarketRegistryV1` is an immutable set of shared asset identities and exact Aerodrome
  routes for one registry version.
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

The price-reference prototype reads the accounting and target USD feeds independently. A
round is usable only when its ID, start time and update time are nonzero, its answer is
positive, `answeredInRound` is not behind its ID, its start is not after its update, its
update is not in the future and its age is within an explicit caller-supplied maximum. There
is no previous-round or single-feed fallback.

Both paper and live execution must use the same integer quote. Feed answers are normalized
to 18 decimals, then the input amount is converted into output-token base units with one
full-precision floor division:

`floor(amountIn * inputPrice18 * 10^outputDecimals / (outputPrice18 * 10^inputDecimals))`

The prototype supports feed decimals up to 18 and token-decimal gaps up to 18. Registry
identity checks and runtime feed-decimal checks must agree.

Entry and exit use the same function with the asset order reversed. The prototype does not
define slippage, router limits or an executable vault path.
Before that path can exist, one release must freeze per-feed maximum ages and the Base
sequencer uptime feed, recovery grace period and failure behavior.

The registry has two record types. An asset record owns one token's address, decimals and
runtime code hash plus its Chainlink USD proxy address, runtime code hash, description hash,
decimals and version. Asset IDs are the `keccak256` hash of the exact manifest token key. The
accounting asset is one of those records. A market record owns a market ID, one non-accounting
target asset ID and the factory, pool, router, tick spacing and runtime code hashes for one
exact Aerodrome route. Multiple markets may reference one asset; they cannot duplicate its
token or price-reference identity.

Within one registry, asset IDs and token addresses form a one-to-one mapping, every feed
proxy belongs to at most one asset and the accounting asset ID resolves to exactly one
record. The V1 accounting asset is USDC. A market in this repository means one exact route,
not every route for an economic token pair. The candidate manifest names the accounting
asset by its exact token key.

The registry constructor enforces those set-level rules while verifying every asset's token
and feed identity. It then verifies every market reference, exact pool token ordering and tick
spacing, pool factory identity, the factory's pool lookup and the router's factory identity.
The registry contract version also pins the one typed `exactInputSingle` ABI selector. The
candidate manifest separately pins the quoter, pool implementation, fee module and
explicit-block fee and observation snapshots through two
independent RPCs. Manifest schema v2 also pins one Chainlink Standard proxy per supported
asset, the shared proxy bytecode, description, decimals, version, underlying aggregator and
complete round at that same block. Catalog heartbeat and round state are evidence, not a
frozen maximum-age policy or contract guarantee.

Only the proxy address and runtime code hash are chain-immutable identity. Feed description,
decimals and version are frozen registry policy: any change fails verification and requires
manual review even when it follows an ordinary underlying-aggregator rotation. The
aggregator address, code hash, type and round remain mutable explicit-block evidence.
They are not stored in the registry and ordinary aggregator rotation does not create a new
asset identity.

Launch policy quotes the exact entry and immediate reverse leg at the immutable route
notional ceiling, then selects one candidate market before vault creation. Vault creation
binds that market permanently; simulation and live execution do not reselect a pool per
operation. No checked-in registry is active yet.

There is never a generic `execute(bytes)` path. Aerodrome calls use a typed interface to one
registry-approved router and pool. A router ABI change requires a new vault version.
