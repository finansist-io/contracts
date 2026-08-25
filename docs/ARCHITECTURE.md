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
update is not in the future and its age is within the asset's registry-bound maximum. There
is no previous-round or single-feed fallback.

Both paper and live execution must use the same integer quote. Feed answers are normalized
to 18 decimals, then the input amount is converted into output-token base units with one
full-precision floor division:

`floor(amountIn * inputPrice18 * 10^outputDecimals / (outputPrice18 * 10^inputDecimals))`

V1 supports feed and token decimals up to 18. Registry identity checks and runtime decimal
checks must agree. V1 stores an inclusive maximum round age in each registry asset: 1,500
seconds for cbBTC/USD and ETH/USD, and 90,000 seconds
for USDC/USD, AERO/USD and EURC/USD. These are the catalog heartbeat plus a fixed delivery
allowance of five minutes or one hour respectively. They are immutable registry policy, not
executor input. A catalog or feed-policy change requires a reviewed registry version.

Entry and exit use the same function with the asset order reversed. `maxSlippageBps` means
the same minimum-output fraction in both directions. The minimum allowed output is the
ceiling of the floor-rounded reference output multiplied by
`(10_000 - maxSlippageBps) / 10_000`; executor calldata may only make it stricter. The
converter rejects `maxSlippageBps >= 10_000`. The final immutable maximum below that value
remains open until route fee and notional-impact vectors are measured.

Slipstream's Q64.96 price is the square root of raw token1 units per raw token0 unit. The
oracle ratio therefore includes both token decimal scales. Executable code must derive
token0, token1 and `zeroForOne` from the registry-bound pool and planned input token, never
executor-supplied ordering or direction. For token0 to token1, the lower price ratio
multiplies by `(10_000 - maxSlippageBps) / 10_000`; its square-root limit rounds up. For
token1 to token0, the upper price ratio multiplies by
`10_000 / (10_000 - maxSlippageBps)`; its square-root limit rounds down. This reciprocal is
required for the same output-side bound in both directions. A pool already at or beyond the
relevant oracle limit fails before the router call. Every intermediate
rational-to-fixed-point division uses full-precision arithmetic and rounds in the same
conservative direction as the final integer square root. The result must lie strictly inside
Slipstream's `(MIN_SQRT_RATIO, MAX_SQRT_RATIO)` interval.

The converter materializes ratios below one at Q192. Ratios at or above one use Q128 before
the square root and a Q32 rescale, keeping the intermediate quotient within 256 bits. Both
paths round every step toward the stricter limit; fuzz properties compare the squared result
against the original rational bound.

Reaching a Slipstream price limit may leave exact input unspent; the limit bounds the
marginal pool-price path but does not guarantee realized output after fees. The router
therefore receives a nonzero limit and the independently checked minimum output. A partial
result below that minimum reverts the entire transaction.

The converter remains non-executable but now has unit, fuzz and pinned Base-fork vectors for
both token address orderings. The Base sequencer recovery grace period, maximum allowed
mandate slippage and bounded exit escalation remain open.

The sequencer-guard prototype uses the one Base uptime proxy pinned by the candidate
manifest. It accepts only a complete non-future round with zero feed decimals and answer
`0`, meaning up. It then requires `block.timestamp - startedAt` to be strictly greater than
an explicit caller-supplied recovery grace period. A down, malformed or future result fails
closed; an up round still within grace also fails closed. There is no fallback. Uptime
`updatedAt` receives consistency checks,
not a price-style maximum age: `startedAt` is the status-transition time used for recovery.
The executable vault must obtain the proxy and grace period from immutable policy, never
executor calldata.

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
independent RPCs. Manifest schema v4 also pins one Chainlink Standard proxy per supported
asset, the shared proxy bytecode, description, decimals, version, underlying aggregator and
complete round at that same block. It separately pins the Base sequencer uptime proxy,
underlying aggregator and complete status round. Catalog heartbeat and round state are
evidence. Maximum ages are separately frozen registry policy. V4 additionally pins each
pool's square-root price and tick for directional price-limit vectors; the recovery grace
remains open.

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
