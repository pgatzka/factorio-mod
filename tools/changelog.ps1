# Adds the section for a new version to changelog.txt, written from merged pull requests,
# and writes the same entries as Markdown for the GitHub release notes.
#
# -PullRequests is a JSON file with an array of { number, title, labels: [{ name }] },
# as printed by `gh pr list --json number,title,labels`.

param(
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $PullRequests,
    [Parameter(Mandatory)] [string] $NotesPath,
    [string] $Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

# Pull requests with this label are not interesting for players and get no entry.
$internalLabel = 'internal'

# Changelog category per label, in the order the categories appear. Anything else goes to Changes.
$categories = [ordered]@{
    'Features' = 'enhancement'
    'Bugfixes' = 'bug'
    'Changes'  = $null
}

# Factorio only reads a changelog in its exact format: a line of 99 dashes opens each version,
# categories are indented by two spaces and entries by four, without tabs or trailing spaces.
$separator = '-' * 99

function Get-EntryText([string] $title) {
    # Titles read "#12 roboport clears debris ..."; the entry drops the issue reference,
    # starts with a capital letter and ends with a full stop.
    $text = ($title -replace '\s+', ' ').Trim() -replace '^#\d+\s+', ''
    if ($text.Length -eq 0) { return $null }
    $text = $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
    if ($text -notmatch '[.!?]$') { $text += '.' }
    return $text
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$changelogPath = Join-Path $repoRoot 'changelog.txt'

$entries = [ordered]@{}
foreach ($category in $categories.Keys) { $entries[$category] = @() }

# ConvertFrom-Json hands over an array as one object; unroll it so one pull request stays a list too.
$pulls = @(Get-Content -Raw $PullRequests | ConvertFrom-Json | ForEach-Object { $_ }) | Sort-Object number
foreach ($pull in $pulls) {
    if ($null -eq $pull) { continue }
    $labels = @($pull.labels | ForEach-Object { $_.name })
    if ($labels -contains $internalLabel) { continue }
    $text = Get-EntryText $pull.title
    if (-not $text) { continue }

    $target = 'Changes'
    foreach ($category in $categories.Keys) {
        $label = $categories[$category]
        if ($label -and ($labels -contains $label)) { $target = $category; break }
    }
    $entries[$target] += $text
}

$listed = 0
foreach ($category in $categories.Keys) { $listed += $entries[$category].Count }
if ($listed -eq 0) {
    $entries['Changes'] += 'No player-facing changes.'
}

$section = @($separator, "Version: $Version", "Date: $Date")
$notes = @()
foreach ($category in $entries.Keys) {
    if ($entries[$category].Count -eq 0) { continue }
    $section += "  ${category}:"
    $notes += "### $category", ''
    foreach ($text in $entries[$category]) {
        $section += "    - $text"
        $notes += "- $text"
    }
    $notes += ''
}

# Earlier versions stay untouched below the new section.
$existing = ''
if (Test-Path $changelogPath) {
    $existing = ((Get-Content -Raw $changelogPath) -replace "`r`n", "`n").TrimEnd("`n")
    if ($existing -match "(?m)^Version: $([regex]::Escape($Version))$") {
        throw "changelog.txt already has a section for version $Version."
    }
}
$content = ($section -join "`n") + "`n"
if ($existing) { $content += $existing + "`n" }

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($changelogPath, $content, $utf8)
[System.IO.File]::WriteAllText($NotesPath, (($notes -join "`n").TrimEnd("`n") + "`n"), $utf8)

Write-Host "Added version $Version to changelog.txt:"
$section | Select-Object -Skip 1 | ForEach-Object { Write-Host "  $_" }
