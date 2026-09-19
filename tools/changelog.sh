#!/usr/bin/env bash
# Adds the section for a new version to changelog.txt, written from merged pull requests,
# and writes the same entries as Markdown for the GitHub release notes.
#
# Usage: changelog.sh <version> <pull-requests.json> <notes.md> [date]
# The JSON file holds an array of { number, title, labels: [{ name }] },
# as printed by `gh pr list --json number,title,labels`.

set -euo pipefail

version=$1
pull_requests=$2
notes_path=$3
date=${4:-$(date -u +%Y-%m-%d)}

# Pull requests with this label are not interesting for players and get no entry.
internal_label='internal'

# Changelog categories in the order they appear, with the label that selects them.
# Anything without such a label goes to Changes.
categories=('Features' 'Bugfixes' 'Changes')
declare -A category_labels=(['Features']='enhancement' ['Bugfixes']='bug')

cd "$(dirname "$0")/.."
changelog='changelog.txt'

if [ -f "$changelog" ] && grep -q -x -F "Version: $version" "$changelog"; then
  echo "changelog.txt already has a section for version $version." >&2
  exit 1
fi

# One line per listed pull request: "<category><TAB><entry>". Titles read
# "#12 roboport clears debris ..."; the entry drops the issue reference, starts
# with a capital letter and ends with a full stop.
entries=$(jq -r \
  --arg internal "$internal_label" \
  --arg feature "${category_labels['Features']}" \
  --arg bugfix "${category_labels['Bugfixes']}" '
  sort_by(.number)[]
  | [.labels[].name] as $labels
  | select($labels | index($internal) | not)
  | (.title | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "") | sub("^#[0-9]+ +"; "")) as $text
  | select($text | length > 0)
  | (if $labels | index($feature) then "Features"
     elif $labels | index($bugfix) then "Bugfixes"
     else "Changes" end) as $category
  | (($text[0:1] | ascii_upcase) + $text[1:]) as $text
  | (if $text | test("[.!?]$") then $text else $text + "." end) as $text
  | "\($category)\t\($text)"
' "$pull_requests" | tr -d '\r')

if [ -z "$entries" ]; then
  entries=$'Changes\tNo player-facing changes.'
fi

# Factorio only reads a changelog in its exact format: a line of 99 dashes opens each version,
# categories are indented by two spaces and entries by four, without tabs or trailing spaces.
separator=$(printf -- '-%.0s' {1..99})
section="$separator"$'\n'"Version: $version"$'\n'"Date: $date"
notes=''
for category in "${categories[@]}"; do
  texts=$(awk -F '\t' -v category="$category" '$1 == category { print $2 }' <<< "$entries")
  [ -n "$texts" ] || continue
  section+=$'\n'"  $category:"
  notes+="### $category"$'\n\n'
  while IFS= read -r text; do
    section+=$'\n'"    - $text"
    notes+="- $text"$'\n'
  done <<< "$texts"
  notes+=$'\n'
done

# Earlier versions stay untouched below the new section.
{
  printf '%s\n' "$section"
  if [ -f "$changelog" ]; then tr -d '\r' < "$changelog"; fi
} > "$changelog.new"
mv "$changelog.new" "$changelog"
printf '%s' "$notes" | sed -e '$ { /^$/d }' > "$notes_path"

echo "Added version $version to changelog.txt:"
printf '%s\n' "$section" | tail -n +2 | sed 's/^/  /'
