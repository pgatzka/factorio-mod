# factorio-mod

Placeholder Factorio 2.0 mod. It loads without Space Age and changes no gameplay yet; name and theme are not decided.

## Local development

The repository root is the mod folder (`info.json` lives here). Factorio loads a mod folder named `<name>` or `<name>_<version>`, so link the clone into the mods directory:

```powershell
New-Item -ItemType Junction -Path "$env:APPDATA\Factorio\mods\factorio-mod" -Target (Get-Location)
```

Then start Factorio and enable the mod in the mod list.

## Release

Build the mod portal package from the committed state (`HEAD`):

```powershell
powershell -ExecutionPolicy Bypass -File tools\package.ps1
```

- Output: `dist/<name>_<version>.zip`, with name and version read from `info.json`, so the package version always matches the version shown in-game.
- The package contains only runtime files (`info.json`, `changelog.txt`, `thumbnail.png`, top-level `*.lua`, `locale/`, `migrations/`, `prototypes/`, `graphics/`). Extend `$runtimePatterns` in `tools/package.ps1` when the mod gains other runtime folders.
- Bump `version` in `info.json` and commit before building; the mod portal rejects a version that was already uploaded.
- Upload the zip on the mod portal, or drop it into `%APPDATA%\Factorio\mods` to test it (remove the development junction first so the mod is not present twice).
