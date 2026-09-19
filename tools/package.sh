#!/usr/bin/env bash
# Builds the mod portal release package dist/<name>_<version>.zip from the committed state (HEAD).
# Name and version come from info.json; only runtime files are packaged.

set -euo pipefail

# Top-level files and folders Factorio needs at runtime. Everything else stays out of the package.
runtime_patterns=(
  'info.json'
  'changelog.txt'
  'thumbnail.png'
  'LICENSE'
  '*.lua'
  'locale'
  'migrations'
  'prototypes'
  'graphics'
)

cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
  echo 'warning: working tree has uncommitted changes; the package is built from HEAD and will not include them.' >&2
fi

info=$(git show HEAD:info.json) || { echo 'info.json is not committed.' >&2; exit 1; }
name=$(jq -r '.name' <<< "$info")
version=$(jq -r '.version' <<< "$info")
if ! [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "Invalid mod name in info.json: '$name'" >&2; exit 1; fi
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Invalid mod version in info.json: '$version'" >&2; exit 1; fi

paths=()
while IFS= read -r entry; do
  for pattern in "${runtime_patterns[@]}"; do
    # Unquoted on purpose: the pattern is a glob.
    if [[ "$entry" == $pattern ]]; then
      paths+=("$entry")
      break
    fi
  done
done < <(git ls-tree --name-only HEAD)

package="${name}_${version}"
mkdir -p dist
rm -f "dist/$package.zip"
git archive --format=zip "--prefix=$package/" -o "dist/$package.zip" HEAD -- "${paths[@]}"

echo "Created dist/$package.zip"
echo 'Contents:'
printf "  $package/%s\n" "${paths[@]}"
