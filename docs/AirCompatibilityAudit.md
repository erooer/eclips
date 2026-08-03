# Adobe AIR compatibility audit

| Source | Browser behavior | AIR approach | Risk |
|---|---|---|---|
| `Client-src/src/WebMain.as` | Gets `Host`/`env` from FlashVars. | AIR entry reads local JSON first and supplies the same values. | Low |
| `ProductionSetup.as` | Builds HTTP URL from browser host and fixed port 80. | Uses centralized host and port. | Low |
| `CompileTimeBuildData.as` | Uses loader parameters and `LocalConnection` for deployment detection. | AIR defaults to production locally; no server change. | Low |
| `WebAccount.as` | Optional `ExternalInterface`, `SharedObject` preferences. | Guard already exists; AIR supports SharedObject. | Low |
| `HTMLUtil`, payment, credits, news | Browser JS and external URLs. | ExternalInterface is guarded; AIR opens URLs externally. | Low |
| `DomainModel.as` | Domain/security policy setup. | Existing policy remains for SWF; no AIR change. | Low |
| `Parameters.as`, language model | SharedObject settings. | AIR application storage supports it. | Low |
| `Options.as`, `MapUserInput.as` | Fullscreen and stage input. | AIR stage plus deactivate focus cleanup. | Medium |

Direct AIR compilation is viable: all game HTTP and socket APIs are shared ActionScript APIs. No packet, Redis, account, resource, map, or server change is needed.
