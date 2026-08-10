# Phase 5 — Contracts and Fame

Contracts are an account-wide, server-authoritative progression system exposed through
`/contracts` (or `/contract`).  The implementation intentionally has no client or packet
dependency, so existing clients and saved accounts remain compatible.

## Schedule and objectives

The schedule uses UTC calendar days and UTC Monday weeks.  Each period tracks two
deterministic objectives:

| Period | Objective | Target | Reward |
| --- | --- | ---: | ---: |
| Daily | Consume quest marks | 3 | 125 Fame |
| Daily | Earn quest chests from consumed marks | 1 | 150 Fame |
| Daily | Claim both daily objectives | — | 250 Fame |
| Weekly | Consume quest marks | 12 | 400 Fame |
| Weekly | Earn quest chests from consumed marks | 3 | 450 Fame |
| Weekly | Claim both weekly objectives | — | 600 Fame |

These objectives deliberately avoid RNG drops, trading, guilds, and parties.  Marks remain
normal consumables: their existing quest-chest counter and reward path run unchanged, and
the contract hook records progress only after that established path increments the account.

## Claims and rerolls

`/contracts claim <scope>` accepts `daily-marks`, `daily-chests`, `daily-bonus`,
`weekly-marks`, `weekly-chests`, or `weekly-bonus`.  Claim flags and the Fame award are
written together before the command reports success, making repeat claim packets harmless.

`/contracts reroll` is a useful voluntary Fame sink: once per daily period it costs 250
Fame and changes the daily mark objective to five consumed marks.  It resets only that
daily mark objective and its bonus eligibility; it does not touch marks, quest chests,
Potion Storage, Forge state, or other account data.

## Persistence and compatibility

`DbAccount.ContractState` stores a JSON payload in the additive Redis account-hash field
`contractState`.  Accounts without that field deserialize to an empty state and begin
tracking normally.  No existing field, character save, mark counter, or Redis key format
is changed.

## Manual verification

1. Consume marks and verify `/contracts` shows daily and weekly mark progress.
2. Cross a pre-existing quest-chest threshold and verify chest progress increments once.
3. Claim each completed scope twice; only the first claim should add Fame.
4. Reroll once with at least 250 Fame; verify a second reroll is refused until UTC daily
   reset and marks/chests remain normal consumable progression.
