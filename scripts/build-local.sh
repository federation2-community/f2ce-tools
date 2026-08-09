#!/usr/bin/env bash
#
# build-local.sh — build f2ce-tools.mpackage from the working tree, the same way
# CI does, for local full-stack testing.
#
# WHY THIS EXISTS. Running muddler directly:
#
#     docker run --rm -v "$PWD:/work" -w /work demonnic/muddler
#
# produces a package that INSTALLS BUT CANNOT BOOT. src/scripts/init.lua ships
# with `F2T_REQUIRED_MUXLET = nil` and `MUXLET_URL = nil` as placeholders, and
# .github/workflows/build.yml rewrites them just before calling muddler. Skip
# that and the client dies on load with:
#
#     [f2ce-tools] Cannot install Muxlet: build is missing MUXLET_URL injection.
#
# This script performs the same injection against a RESTORED copy of init.lua,
# so the placeholders stay `nil` in git — they are build inputs, not source.
#
# Usage:
#   scripts/build-local.sh                  # Muxlet version from mfile
#   MUXLET_VERSION=v2.2.9 scripts/build-local.sh
#
# Output: build/f2ce-tools.mpackage — point the web client at it with
#   LOCAL_PKG=../fed2-tools/build/f2ce-tools.mpackage ../f2ce-web-client/scripts/dev-stack.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

INIT_LUA="src/scripts/init.lua"
[ -f "$INIT_LUA" ] || { echo "build-local: $INIT_LUA not found" >&2; exit 1; }
[ -f mfile ] || { echo "build-local: mfile not found" >&2; exit 1; }

# mfile is JSON; read it with node rather than assuming jq is installed.
read -r MUXLET_REPO MFILE_MUXLET_VERSION <<<"$(node -e '
  const m = JSON.parse(require("fs").readFileSync("mfile", "utf8"));
  const d = m.dependency || {};
  process.stdout.write(`${d.repo || "tmtocloud/Muxlet"} ${d.version || ""}`);
')"

MUXLET_VERSION="${MUXLET_VERSION:-$MFILE_MUXLET_VERSION}"
if [ -z "$MUXLET_VERSION" ]; then
  echo "build-local: no Muxlet version in mfile's dependency.version, and none passed" >&2
  exit 1
fi

# Mirrors the workflow: normalise to a single "v"-prefixed tag that drives both
# the download URL and the version F2T_REQUIRED_MUXLET checks against.
MUXLET_TAG="v${MUXLET_VERSION#v}"
MUXLET_URL="https://github.com/${MUXLET_REPO}/releases/download/${MUXLET_TAG}/Muxlet.mpackage"

echo "build-local: Muxlet $MUXLET_TAG"
echo "build-local: $MUXLET_URL"

# Always put the placeholders back, however we exit — leaving a real URL in
# init.lua would quietly commit a build artifact into source.
BACKUP="$(mktemp)"
cp "$INIT_LUA" "$BACKUP"
restore() { cp "$BACKUP" "$INIT_LUA"; rm -f "$BACKUP"; }
trap restore EXIT INT TERM

# -i '' is the BSD/macOS spelling; this script is for local (macOS) builds. CI
# uses GNU sed in the workflow.
sed -i '' \
  -e "s|local F2T_REQUIRED_MUXLET = nil|local F2T_REQUIRED_MUXLET = \"${MUXLET_TAG}\"|" \
  -e "s|local MUXLET_URL = nil|local MUXLET_URL = \"${MUXLET_URL}\"|" \
  "$INIT_LUA"

# Fail loudly rather than shipping another package that cannot boot.
grep -q "local MUXLET_URL = \"${MUXLET_URL}\"" "$INIT_LUA" || {
  echo "build-local: MUXLET_URL injection did not apply — has init.lua's placeholder changed?" >&2
  exit 1
}
grep -q "local F2T_REQUIRED_MUXLET = \"${MUXLET_TAG}\"" "$INIT_LUA" || {
  echo "build-local: F2T_REQUIRED_MUXLET injection did not apply — has init.lua's placeholder changed?" >&2
  exit 1
}

echo "build-local: running muddler..."
docker run --rm -v "$PWD:/work" -w /work demonnic/muddler

echo "build-local: built $(ls -lh build/f2ce-tools.mpackage | awk '{print $5}') -> build/f2ce-tools.mpackage"
