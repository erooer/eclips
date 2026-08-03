# Build pipeline

`scripts/Build-Everything.ps1` runs targeted preflight checks, rebuilds the server, then rebuilds the client. The target checks reject Ominous Below map/reference/type mistakes. Broad reports retain legacy source findings as report-only so they do not make a clean rebuild non-reproducible.

Commands:

```powershell
./scripts/Clean-Build.ps1
./scripts/Build-Everything.ps1
```

The client output is `build/client-unchanged.swf`. Server projects build from `Cosmic-Realms-main/Server-src`. No shipped SWF or compatibility stack is used.
