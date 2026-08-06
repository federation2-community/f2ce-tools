#!/bin/bash
# Formats commit history as markdown bullets. A single-line commit message
# becomes one bullet. A commit whose first message line already starts with
# "- " has no real subject of its own (it's just a run of hyphenated lines) —
# every such line is a peer, not a child of the first, so those get an empty
# parent bullet with all of them nested underneath as sub-bullets. A commit
# with a genuine subject line followed by "- " prefixed body lines keeps the
# subject as the parent bullet and nests the body lines under it.
#
# Usage: format_changelog.sh <max_commits> [git-log-args...]
set -euo pipefail

max="$1"
shift

{ git log "$@" -n "$max" --pretty=format:'%H'; echo; } | while IFS= read -r sha; do
  [[ -z "$sha" ]] && continue
  mapfile -t lines < <(git log -1 --pretty=format:'%B' "$sha" | grep -v '^$')
  first="${lines[0]:-}"
  if [[ ${#lines[@]} -eq 1 ]]; then
    if [[ "$first" == "- "* ]]; then
      echo "$first"
    else
      echo "- $first"
    fi
  elif [[ "$first" == "- "* ]]; then
    echo "-"
    for line in "${lines[@]}"; do
      if [[ "$line" == "- "* ]]; then
        echo "  $line"
      fi
    done
  else
    echo "- $first"
    for ((i = 1; i < ${#lines[@]}; i++)); do
      line="${lines[$i]}"
      if [[ "$line" == "- "* ]]; then
        echo "  $line"
      fi
    done
  fi
done
