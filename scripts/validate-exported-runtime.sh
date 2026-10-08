#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"
SMOKE_ROOT="$(mktemp -d)"
SMOKE_PROJECT="$SMOKE_ROOT/project"
SMOKE_PACK="$SMOKE_ROOT/gdsql-runtime-smoke.pck"
IMPORT_LOG="$SMOKE_ROOT/import.log"
EXPORT_LOG="$SMOKE_ROOT/export.log"
RUNTIME_LOG="$SMOKE_ROOT/runtime.log"
RUNTIME_WORKING_DIRECTORY="$SMOKE_ROOT/runtime"

cleanup() {
	rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

if [ ! -x "$GODOT_EXECUTABLE" ] && ! command -v "$GODOT_EXECUTABLE" >/dev/null 2>&1; then
	echo "Godot executable not found: $GODOT_EXECUTABLE"
	exit 1
fi

mkdir -p "$SMOKE_PROJECT/addons"
mkdir -p "$RUNTIME_WORKING_DIRECTORY"
cp -R "$REPOSITORY_ROOT/addons/gdsql" "$SMOKE_PROJECT/addons/gdsql"
cp -R "$REPOSITORY_ROOT/scripts/export-smoke/." "$SMOKE_PROJECT"

export XDG_DATA_HOME="$SMOKE_ROOT/xdg-data"
export XDG_CONFIG_HOME="$SMOKE_ROOT/xdg-config"
export XDG_CACHE_HOME="$SMOKE_ROOT/xdg-cache"

"$GODOT_EXECUTABLE" --headless --editor --path "$SMOKE_PROJECT" --quit \
	> "$IMPORT_LOG" 2>&1

"$GODOT_EXECUTABLE" --headless --path "$SMOKE_PROJECT" \
	--export-pack "Runtime Smoke" "$SMOKE_PACK" \
	> "$EXPORT_LOG" 2>&1

set +e
pushd "$RUNTIME_WORKING_DIRECTORY" >/dev/null
"$GODOT_EXECUTABLE" --headless --main-pack "$SMOKE_PACK" \
	> "$RUNTIME_LOG" 2>&1
RUNTIME_EXIT=$?
popd >/dev/null
set -e

if [ "$RUNTIME_EXIT" -ne 0 ]; then
	cat "$RUNTIME_LOG"
	echo "Exported runtime smoke test exited with code $RUNTIME_EXIT."
	exit "$RUNTIME_EXIT"
fi

if ! grep -q 'GDSQL_EXPORT_SMOKE_OK' "$RUNTIME_LOG"; then
	cat "$RUNTIME_LOG"
	echo "Exported runtime smoke test did not reach its success sentinel."
	exit 1
fi

if grep -Eiq 'SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve (class|script)' \
	"$IMPORT_LOG" "$EXPORT_LOG" "$RUNTIME_LOG"; then
	cat "$IMPORT_LOG" "$EXPORT_LOG" "$RUNTIME_LOG"
	echo "Exported runtime smoke test found a script loading error."
	exit 1
fi

echo "Exported GDSQL runtime pack executed successfully with $($GODOT_EXECUTABLE --version)."
