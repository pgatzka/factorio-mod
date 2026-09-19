# factorio-mod

Factorio 2.0 mod that loads without Space Age; name and theme are not decided.

## Features

- Hovering over a roboport shows the amount of debris (items on the ground, trees, rocks, cliffs) inside its construction range in the info panel. A piece is in range when its center is; pieces that only overlap the edge from outside are ignored.
- Roboports clear that debris on their own: each marks debris inside its own construction range for deconstruction, keeping at most a configurable number of pieces marked at once. The map setting "Maximum marked debris per roboport" defaults to 1; 0 turns automatic marking off. A roboport only marks debris while it is fully powered; with low or no power it pauses, and debris that is already marked stays marked.
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
- The release package builds, loads in the current stable headless Factorio with the base game alone, and its scripts run without errors. A small harness mod (`.github/ci/harness`) builds a powered and an unpowered roboport with debris around them and fails the check when the powered one marks nothing or the unpowered one marks something.

A failing check names the problem in the pull request's check report; the full Factorio log is in the workflow run.

## Release

Releases are made on GitHub only: **Actions → Release → Run workflow** on `main`, choosing which part of the version to raise (`patch` by default, `minor`, or `major`).

The workflow then

1. raises `version` in `info.json` (e.g. 0.1.0 → 0.1.1),
2. runs the same checks as for pull requests against that version, which builds the package and loads it in Factorio,
3. records the version commit on `main`,
4. publishes a GitHub release tagged with the version, with the package `<name>_<version>.zip` attached.

When a check fails, nothing is pushed: no version change, no tag, no release.

- The package contains only runtime files (`info.json`, `changelog.txt`, `thumbnail.png`, top-level `*.lua`, `locale/`, `migrations/`, `prototypes/`, `graphics/`). Extend `$runtimePatterns` in `tools/package.ps1`, the build step used by the workflows, when the mod gains other runtime folders.
- Uploading the package to the mod portal is a manual step: download it from the GitHub release.
- `main` only takes changes through pull requests. The workflow pushes the version commit as a GitHub App that is a bypass actor of that rule; it expects the app's ID in the repository variable `RELEASE_APP_ID` and its private key in the secret `RELEASE_APP_PRIVATE_KEY`.
