# Redis persistence and schema

The rebuilt account and world servers use StackExchange.Redis against logical database **15** (`server.json` and `wServer.json`). Redis itself also carries transient pub/sub channels such as `Network`, `Chat`, and `Control`; those are not account records.

The persistent runtime binds only to `127.0.0.1:6379`, stores files in `runtime/redis-data`, enables `appendonly yes` with `appendfsync everysec`, and keeps RDB snapshots (`matching-rebuild.rdb`) as a secondary recovery point.

## Key layout

All values below are fictional examples.

| Redis key | Type | Purpose / example |
| --- | --- | --- |
| `logins` | hash | Uppercase email/UUID maps to JSON login metadata. Field `PLAYER@EXAMPLE.TEST` can contain `{"AccountId":42,"Salt":"...","HashedPassword":"..."}`. |
| `account.42` | hash | Main account record. Fields include `uuid`, `name`, `nameChosen`, `guest`, `rank`, `credits`, `totalCredits`, `fame`, `totalFame`, `guildId`, `guildRank`, `guildFame`, `vaultCount`, `maxCharSlot`, and `banned`. |
| `names` | hash | Uppercase character name to account id, e.g. `EXAMPLERANGER` -> `42`. |
| `char.42.7` | hash | Character 7 belonging to account 42. Includes class, level, stats, inventory/equipment, `fame`, and binary fields such as `fameStats`. |
| `vault.42` | hash | Vault fields `vault.0`, `vault.1`, etc.; values are serialized `ushort[]` item slots. |
| `classStats.42` | hash | Class statistics keyed by object/class type. |
| `guilds` | hash | Uppercase guild name to guild id. |
| `guild.9` | hash | Guild record including `name`, `fame`, `level`, and serialized membership fields. |
| `ips` | hash | IP-to-account association data. |
| `lock:42` | string with TTL | Temporary account lock, not durable account state. |

## Encoding

Scalar hash fields use StackExchange.Redis primitive string conversions. Composite fields use the server's `DbObject` serialization helpers; arrays and binary statistics can therefore be binary/encoded values rather than human-readable JSON. Login metadata is JSON in the `logins` hash.

## Account ranks and administrator status

The authoritative model is `common/DbModels.cs` in the rebuilt server source. `DbAccount` loads the complete Redis hash `account.<accountId>` and saves changed fields with `HashSetAsync`.

- Account lookup by email/UUID: the `logins` hash uses the uppercase UUID/email as its field. Its JSON metadata contains the numeric `AccountId`; password material is not needed to administer rank and must not be displayed.
- Account lookup by chosen in-game name: the `names` hash maps the uppercase name to the numeric account id.
- Account record key: `account.<AccountId>` — for example, `account.42`.
- Legacy rank field: `rank`. It is an integer encoded as UTF-8 decimal text, for example `60`.
- Administrator field: `admin`. It is a binary Boolean: byte `0x01` means true and `0x00` means false. It is not a JSON field and should not be written as the text `True`.
- Effective `DbAccount.Rank`: `max(discordRank[discordId], rank)`. The optional `discordRank` hash is a separate Discord-role integration; it does not replace the stored `rank` field.

The server's own `/rank` command (`wServer/realm/commands/RankedCommands.cs`) makes the intended update explicit: it sets `admin = (rank >= 60)` and then saves `rank`. Therefore, an Administrator promotion uses exactly `rank = 60` and `admin = true`; no account blobs, credentials, characters, vault data, currency, guild data, or other fields are changed.

There is no C# account-role enum for Player, Supporter, Moderator, Administrator, or Developer. The source-defined values are:

| Numeric rank | Source label / behavior |
| ---: | --- |
| 0 | `none` in `resources/data/roles.json`; `/rank` calls this Normal Player. |
| 10 | `donor` / Patron T2. |
| 20 | Patron T3. |
| 60 | Administrator threshold; also enables the separate `admin` Boolean. |
| 70 | Former Staff (command help text). |
| 80 | GM (command help text). |
| 90 | Dev (command help text; this is the source's Developer-equivalent label). |
| 100 | Owner (command help text). |

The source defines no `Supporter` or `Moderator` labels, and it permits other numeric ranks through `/rank`; those names/values must not be invented by an administration script.

Permission references are source-driven: `Command.cs` compares `DbAccount.Rank` to command `permLevel`; `HelloHandler.cs` checks `Admin` for admin-only worlds and `Rank` for a world minimum rank; `Player.cs` publishes both values and has rank-based entitlement checks; `ConnectManager.cs`, trade/inventory handlers, market handlers, and `RankedCommands.cs` contain the remaining world-side checks. The rank command itself is the canonical promotion implementation.

### Rank/admin reference audit

The following are all first-party rebuilt-server source files with account rank/admin references (third-party `bin` and `packages` files excluded):

- `common/DbModels.cs` — `DbAccount.Admin`, `LegacyRank`, `DiscordRank`, and calculated `Rank`.
- `common/Database.cs` — default `Admin = false`, Discord-rank storage, and the admin legend exclusion.
- `server/account/rank.cs` — HTTP Discord-role rank management.
- `server/char/list.cs`, `server/privateMessage/list.cs`, `server/RequestHandler.cs`, and `server/XmlModels.cs` — account response/model handling.
- `wServer/realm/ConnectManager.cs`, `ConnectionQueue.cs`, `ChatManager.cs`, and `worlds/World.cs` — connection, priority, and world admission behavior.
- `wServer/networking/handlers/HelloHandler.cs` — admin-only/minimum-rank admission.
- `wServer/networking/handlers/AcceptTradeHandler.cs`, `InvDropHandler.cs`, and `InvSwapHandler.cs` — admin-aware trade/inventory behavior.
- `wServer/networking/handlers/market/MarketAddHandler.cs` and `MarketBuyHandler.cs` — rank-restricted market behavior.
- `wServer/realm/entities/player/Player.cs` and `Player.UseItem.cs` — transmitted rank/admin stats and entitlement/gameplay checks.
- `wServer/realm/commands/Command.cs`, `RankedCommands.cs`, and `UnrankedCommands.cs` — command permission levels and the canonical rank update.
- `wServer/logic/behaviors/AnnounceOnDeath.cs`, `wServer/realm/worlds/logic/Arena.cs`, `ArenaSolo.cs`, and `DeathArena.cs` — rank/admin-specific world behavior.

## Safe local Redis Insight connection

Connect Redis Insight only to:

- Host: `127.0.0.1`
- Port: `6379`
- Database: `15`

Use read-only inspection unless you intentionally administer game data. Never expose this Redis instance to a LAN or the internet.

## Backup and restore

Run `scripts/Backup-Redis.ps1` while the stack is running. It issues `SAVE` then stores the AOF, RDB, and configuration under `runtime/redis-backups/<timestamp>`.

Run `scripts/Restore-Redis.ps1 -BackupPath <folder>` only after `Stop-All.ps1`. It first copies the current persistent files into a timestamped `pre-restore-*` safety backup, then restores the selected AOF/RDB files.
