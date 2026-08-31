#!/bin/bash
# Formats commit history as markdown bullets. A single-line commit message
# becomes one bullet. A commit whose first message line already starts with
# "- " has no real subject of its own (it's just a run of hyphenated lines) —
# every such line is a peer, not a child of the first, so each becomes its
# own top-level bullet (no empty placeholder parent, which would otherwise
# render as a content-less bullet stacked directly on top of its first
# child's bullet). A commit with a genuine subject line followed by "- "
# prefixed body lines keeps the subject as the parent bullet and nests the
# body lines under it.
#
# Body lines can themselves be nested to any depth (indentation is taken as
# 2 spaces per level). A line that isn't itself a "- " bullet is treated as
# a wrapped continuation of the previous bullet and folded back onto it.
#
# Usage: format_changelog.sh <max_commits> [git-log-args...]
set -euo pipefail

max="$1"
shift

# Parses lines (from argument 2 onward) into bullets, nesting arbitrarily
# deep and folding non-bullet lines into the preceding bullet's text. Prints
# each bullet indented by 2 spaces per (level + shift).
print_bullets() {
  local shift_levels="$1"
  shift
  local -a levels=()
  local -a texts=()
  local line indent content level
  for line in "$@"; do
    if [[ "$line" =~ ^([[:space:]]*)-[[:space:]]+(.*)$ ]]; then
      indent="${BASH_REMATCH[1]}"
      content="${BASH_REMATCH[2]}"
      level=$(( ${#indent} / 2 ))
      levels+=("$level")
      texts+=("$content")
    elif [[ ${#texts[@]} -gt 0 ]]; then
      # Continuation of the previous bullet's wrapped text.
      content="${line#"${line%%[![:space:]]*}"}"
      local last=$(( ${#texts[@]} - 1 ))
      texts[$last]="${texts[$last]} $content"
    fi
  done
  local i
  for ((i = 0; i < ${#texts[@]}; i++)); do
    printf '%*s- %s\n' "$(( (levels[i] + shift_levels) * 2 ))" '' "${texts[$i]}"
  done
}

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
    print_bullets 0 "${lines[@]}"
  else
    echo "- $first"
    print_bullets 1 "${lines[@]:1}"
  fi
done
