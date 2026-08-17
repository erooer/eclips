# Build pipeline

`scripts/Build-Everything.ps1` runs targeted preflight checks, rebuilds the server, then rebuilds the client. The target checks reject Ominous Below map/reference/type mistakes. Broad reports retain legacy source findings as report-only so they do not make a clean rebuild non-reproducible.

Commands:

```powershell
./scripts/Provision-FlexSdk.ps1
./scripts/Clean-Build.ps1
./scripts/Build-Everything.ps1
```

`Build-Client.ps1` resolves Apache Flex 4.9.1 in this order: an explicit
`ECLIPSE_FLEX_SDK_HOME`, then the ignored repo cache at
`tools/flex-sdk-4.9.1`. If it is missing, the build provisions the exact Apache
4.9.1 archive and Flash Player 15 API library from pinned URLs and verifies
their SHA-256 checksums before extraction/use. Java must be available through
`JAVA_HOME` or `PATH`. `Provision-FlexSdk.ps1` may be run separately to warm the
cache or diagnose the toolchain before a production build.

The client output is `build/client-unchanged.swf`. The same bytes are copied to
both `runtime/resources/web/rotmg.swf` and the deployable
`Cosmic-Realms-main/Server-src/bin/resources/web/rotmg.swf`; the build fails if
their hashes differ. Server projects build from `Cosmic-Realms-main/Server-src`.
No shipped SWF or compatibility stack is used.

`Build-Everything.ps1` finishes by writing the ignored
`build/deployment-manifest.json`. It binds the required server/client artifact
hashes to the Git commit used for the build.

The server build resolves MSBuild in this order: `ECLIPSE_MSBUILD_PATH`,
Visual Studio/Build Tools via `vswhere`, `msbuild` on `PATH`, then the newest
installed stable dotnet SDK's `MSBuild.exe` or `MSBuild.dll`. Every candidate is
version-probed and requires the .NET Framework 4.6 and 4.7.2 targeting packs.
The selected SDK's
`Microsoft\Microsoft.NET.Build.Extensions\net461\lib` directory is supplied as
the `netstandard` compatibility reference path. Resolution fails with an
inventory of every searched source when no usable toolchain exists.
