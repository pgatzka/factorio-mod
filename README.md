# factorio-mod

Factorio 2.0 mod that loads without Space Age; name and theme are not decided.

## Features

- Hovering over a roboport shows the amount of debris (items on the ground, trees, rocks, cliffs) inside its construction range in the info panel.
- Roboports clear that debris on their own: each marks debris inside its own construction range for deconstruction, keeping at most a configurable number of pieces marked at once. The map setting "Maximum marked debris per roboport" defaults to 1; 0 turns automatic marking off.
- Debris the robots cannot remove is skipped and does not count toward that limit: cliffs while the roboport's network has no cliff explosives, and items on the ground while the network has no storage space for them.

## Local development

The repository root is the mod folder (`info.json` lives here). Factorio loads a mod folder named `<name>` or `<name>_<version>`, so link the clone into the mods directory:

```powershell
New-Item -ItemType Junction -Path "$env:APPDATA\Factorio\mods\factorio-mod" -Target (Get-Location)
```

Then start Factorio and enable the mod in the mod list.
