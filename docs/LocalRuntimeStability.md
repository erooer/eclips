# Local runtime stability

`Start-All-Stable.ps1` is an optional local launcher. It reports the active power plan, oversized logs, port conflicts, and requests AboveNormal priority only for the server processes it starts.

For an isolated test, a user may manually exclude only these narrow directories from real-time scanning:

- `C:\Users\erooe\Downloads\Cosmic-Realms-main\rebuild-original\runtime\logs`
- `C:\Users\erooe\Downloads\Cosmic-Realms-main\rebuild-original\runtime\redis-data`
- `C:\Users\erooe\Downloads\Cosmic-Realms-main\rebuild-original\runtime`

Do not exclude Downloads, the user profile, a drive, or disable antivirus globally. Remove any temporary exclusion after profiling.
