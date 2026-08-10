# Phase 7 — Material Vault

The Material Vault is an account-wide server ledger for non-item resources. It is stored
in the additive Redis account-hash field `materialVaultState`; existing accounts load an
empty vault with no migration.

## Allowed materials

The initial stable IDs are `echo_dust`, `sigil_fragment`, `threat_fragment`,
`citadel_fragment`, `imprint_shard`, and `event_token`. They are configuration entries,
not ordinary inventory objects. Each defaults to a 9,999 cap and is marked auto-depositable
for future reward code.

Marks, stat potions, normal gear, quest chests, and ordinary consumables are not material
IDs and cannot be deposited, withdrawn, or spent through this service. No mark handling,
quest-chest behavior, inventory path, or Potion Storage code changed.

## API and reliability

Future systems call `TryDeposit`, `TryAutoDeposit`, `TryWithdraw`, or `TrySpend` with a
stable material ID, positive amount, and unique operation ID. The account lock, balance,
and a bounded persisted operation ledger are updated together. Replayed requests return the
already-applied balance without changing it. Invalid IDs, negative/zero amounts, cap
overflow, and insufficient balances fail before persistence.

`/materials` lists balances; `/materials <id>` reads one balance. V1 deliberately has no
player-controlled deposit/withdraw command, preventing clients from minting materials.
