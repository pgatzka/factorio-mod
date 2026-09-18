# factorio-mod

Factorio 2.0 mod that loads without Space Age; name and theme are not decided.

## Features

- Hovering over a roboport shows the amount of debris (items on the ground, trees, rocks, cliffs) inside its construction range in the info panel. A piece is in range when its center is; pieces that only overlap the edge from outside are ignored.
- Roboports clear that debris on their own: each marks debris inside its own construction range for deconstruction, keeping at most a configurable number of pieces marked at once. The map setting "Maximum marked debris per roboport" defaults to 1; 0 turns automatic marking off.
- Debris the robots cannot remove is skipped and does not count toward that limit: cliffs while the roboport's network has no cliff explosives, and items on the ground while the network has no storage space for them.

## Local development

The repository root is the mod folder (`info.json` lives here). Factorio loads a mod folder named `<name>` or `<name>_<version>`, so link the clone into the mods directory:

```powershell
New-Item -ItemType Junction -Path "$env:APPDATA\Factorio\mods\factorio-mod" -Target (Get-Location)
```

Then start Factorio and enable the mod in the mod list.

## Pull request checks

Every push to a pull request runs the "Mod checks" workflow:

- `info.json` is valid and has the fields Factorio requires.
- All Lua files are syntactically correct.
- The mod loads in the current stable headless Factorio with the base game alone, and its scripts run without errors. A small harness mod (`.github/ci/harness`) builds a roboport with debris around it and fails the check when nothing gets marked.

A failing check names the problem in the pull request's check report; the full Factorio log is in the workflow run.

## Release

Build the mod portal package from the committed state (`HEAD`):

```powershell
powershell -ExecutionPolicy Bypass -File tools\package.ps1
```

- Output: `dist/<name>_<version>.zip`, with name and version read from `info.json`, so the package version always matches the version shown in-game.
- The package contains only runtime files (`info.json`, `changelog.txt`, `thumbnail.png`, top-level `*.lua`, `locale/`, `migrations/`, `prototypes/`, `graphics/`). Extend `$runtimePatterns` in `tools/package.ps1` when the mod gains other runtime folders.
- Bump `version` in `info.json` and commit before building; the mod portal rejects a version that was already uploaded.
- Upload the zip on the mod portal, or drop it into `%APPDATA%\Factorio\mods` to test it (remove the development junction first so the mod is not present twice).
