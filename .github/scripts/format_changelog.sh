#!/bin/bash
# Formats commit history as markdown bullets. A commit's first non-blank
# message line becomes the top-level bullet (used verbatim if it already
# starts with "- ", since a commit's whole message can be a single run of
# hyphenated lines with no separate subject/body split). Any further "- "
# prefixed lines become indented sub-bullets under it, so multi-line
# hyphenated commit messages render as nested lists instead of being
# dropped or double-bulleted.
#
# Usage: format_changelog.sh <max_commits> [git-log-args...]
set -euo pipefail

max="$1"
shift

{ git log "$@" -n "$max" --pretty=format:'%H'; echo; } | while IFS= read -r sha; do
  [[ -z "$sha" ]] && continue
  mapfile -t lines < <(git log -1 --pretty=format:'%B' "$sha" | grep -v '^$')
  first="${lines[0]:-}"
  if [[ "$first" == "- "* ]]; then
    echo "$first"
  else
    echo "- $first"
  fi
  for ((i = 1; i < ${#lines[@]}; i++)); do
    line="${lines[$i]}"
    if [[ "$line" == "- "* ]]; then
      echo "  $line"
    fi
  done
done
