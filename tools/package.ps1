# Builds the mod portal release package dist/<name>_<version>.zip from the committed state (HEAD).
# Name and version come from info.json; only runtime files are packaged.

$ErrorActionPreference = 'Stop'

# Top-level files and folders Factorio needs at runtime. Everything else stays out of the package.
$runtimePatterns = @(
    'info.json',
    'changelog.txt',
    'thumbnail.png',
    '*.lua',
    'locale',
    'migrations',
    'prototypes',
    'graphics'
)

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (git status --porcelain) {
        Write-Warning 'Working tree has uncommitted changes; the package is built from HEAD and will not include them.'
    }

    $info = (git show HEAD:info.json) -join "`n" | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'info.json is not committed.' }
    if ($info.name -notmatch '^[A-Za-z0-9_-]+$') { throw "Invalid mod name in info.json: '$($info.name)'" }
    if ($info.version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid mod version in info.json: '$($info.version)'" }

    $paths = @(git ls-tree --name-only HEAD | Where-Object {
        $entry = $_
        $runtimePatterns | Where-Object { $entry -like $_ }
    })

    $packageName = "$($info.name)_$($info.version)"
    $distDir = Join-Path $repoRoot 'dist'
    $zipPath = Join-Path $distDir "$packageName.zip"
    New-Item -ItemType Directory -Force $distDir | Out-Null
    if (Test-Path $zipPath) { Remove-Item $zipPath }

    git archive --format=zip "--prefix=$packageName/" -o $zipPath HEAD -- $paths
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }

    Write-Host "Created $zipPath"
    Write-Host 'Contents:'
    $paths | ForEach-Object { Write-Host "  $packageName/$_" }
}
finally {
    Pop-Location
}
