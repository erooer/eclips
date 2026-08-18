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

`Build-Everything.ps1` finishes by writing the tracked
`build/deployment-manifest.json`. It inventories every file the deployer can
copy: the client SWF, `server.exe`, `wServer.exe`, every top-level server
DLL/PDB, and every compiled resource. Each entry has a SHA-256 hash and the
manifest records the exact source commit used for the build.

Because a Git commit cannot contain its own hash, production artifacts use a
two-commit bundle. First commit the source change, run `Build-Everything.ps1`
from that clean source commit, then commit only the generated manifest and its
allowlisted artifacts. The VPS verifies that the artifact commit's parent is
the manifest's source commit and that the artifact commit contains no source
changes. A later source-only commit therefore invalidates the bundle.

PC release workflow:

```powershell
git add <source files>
git commit -m "Describe source change"
.\scripts\Build-Everything.ps1
.\scripts\Test-PortableBuildPipeline.ps1
.\scripts\Publish-DeploymentArtifacts.ps1
git push
```

The publisher stages every manifest entry with `git add -f`, including ignored
DLL/PDB/resource outputs, hashes the exact Git blobs in the index (not only the
PC working-tree files), verifies that those bytes match the manifest,
rejects unlisted deployable output and unrelated staged files, creates the
artifact commit, then validates the completed two-commit bundle. Do not edit or
regenerate an artifact afterward; the manifest validator rejects any byte
change or missing file. Deployment artifact paths are marked `-text` in
`.gitattributes`, so Git never performs line-ending or other text conversion on
manifest-managed TXT/XML/JSON/CONFIG/DAT resources or binary files.

The VPS does not use those working-tree copies as deployment sources. It reads
the manifest and every listed artifact directly from the current artifact
commit with Git plumbing, streams each blob as bytes into an isolated temporary
staging tree, and verifies the staged SHA-256 hashes before backup or service
stop. Deployment copies come only from that verified staging tree.

The server build resolves MSBuild in this order: `ECLIPSE_MSBUILD_PATH`,
Visual Studio/Build Tools via `vswhere`, `msbuild` on `PATH`, then the newest
installed stable dotnet SDK's `MSBuild.exe` or `MSBuild.dll`. Every candidate is
version-probed and requires the .NET Framework 4.6 and 4.7.2 targeting packs.
The selected SDK's
`Microsoft\Microsoft.NET.Build.Extensions\net461\lib` directory is supplied as
the `netstandard` compatibility reference path. Resolution fails with an
inventory of every searched source when no usable toolchain exists.
