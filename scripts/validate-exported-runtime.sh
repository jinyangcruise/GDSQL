#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"
REQUIRE_STANDALONE="${GDSQL_REQUIRE_STANDALONE_EXPORT:-0}"
SMOKE_ROOT="$(mktemp -d)"
SMOKE_PROJECT="$SMOKE_ROOT/project"
SMOKE_PACK="$SMOKE_ROOT/gdsql-runtime-smoke.pck"
STANDALONE_ROOT="$SMOKE_ROOT/standalone"
SMOKE_BINARY="$STANDALONE_ROOT/gdsql-runtime-smoke.x86_64"
IMPORT_LOG="$SMOKE_ROOT/import.log"
EXPORT_LOG="$SMOKE_ROOT/export.log"
RUNTIME_LOG="$SMOKE_ROOT/runtime.log"
STANDALONE_EXPORT_LOG="$SMOKE_ROOT/standalone-export.log"
STANDALONE_RUNTIME_LOG="$SMOKE_ROOT/standalone-runtime.log"
RUNTIME_WORKING_DIRECTORY="$SMOKE_ROOT/runtime"
SYSTEM_DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}"
EXPORT_DATA_ROOT="$SMOKE_ROOT/xdg-export-data"

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
mkdir -p "$STANDALONE_ROOT"
mkdir -p "$EXPORT_DATA_ROOT/godot"
ln -s "$SYSTEM_DATA_ROOT/godot/export_templates" \
	"$EXPORT_DATA_ROOT/godot/export_templates"
cp -R "$REPOSITORY_ROOT/addons/gdsql" "$SMOKE_PROJECT/addons/gdsql"
cp -R "$REPOSITORY_ROOT/scripts/export-smoke/." "$SMOKE_PROJECT"

export XDG_CONFIG_HOME="$SMOKE_ROOT/xdg-config"
export XDG_CACHE_HOME="$SMOKE_ROOT/xdg-cache"

"$GODOT_EXECUTABLE" --headless --editor --path "$SMOKE_PROJECT" --quit \
	> "$IMPORT_LOG" 2>&1

"$GODOT_EXECUTABLE" --headless --path "$SMOKE_PROJECT" \
	--export-pack "Runtime Smoke" "$SMOKE_PACK" \
	> "$EXPORT_LOG" 2>&1

set +e
pushd "$RUNTIME_WORKING_DIRECTORY" >/dev/null
XDG_DATA_HOME="$SMOKE_ROOT/xdg-pack-data" \
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

if [ "$REQUIRE_STANDALONE" = "1" ]; then
	set +e
	XDG_DATA_HOME="$EXPORT_DATA_ROOT" \
		"$GODOT_EXECUTABLE" --headless --path "$SMOKE_PROJECT" \
		--export-release "Runtime Smoke" "$SMOKE_BINARY" \
		> "$STANDALONE_EXPORT_LOG" 2>&1
	STANDALONE_EXPORT_EXIT=$?
	set -e
	if [ "$STANDALONE_EXPORT_EXIT" -ne 0 ]; then
		cat "$STANDALONE_EXPORT_LOG"
		echo "Standalone Linux export failed. Install export templates matching $($GODOT_EXECUTABLE --version)."
		exit "$STANDALONE_EXPORT_EXIT"
	fi

	set +e
	pushd "$RUNTIME_WORKING_DIRECTORY" >/dev/null
	XDG_DATA_HOME="$SMOKE_ROOT/xdg-standalone-data" \
		"$SMOKE_BINARY" --headless > "$STANDALONE_RUNTIME_LOG" 2>&1
	STANDALONE_RUNTIME_EXIT=$?
	popd >/dev/null
	set -e
	if [ "$STANDALONE_RUNTIME_EXIT" -ne 0 ] \
			|| ! grep -q 'GDSQL_EXPORT_SMOKE_OK' "$STANDALONE_RUNTIME_LOG"; then
		cat "$STANDALONE_RUNTIME_LOG"
		echo "Standalone GDSQL runtime smoke test failed."
		exit 1
	fi
	if grep -Eiq 'SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve (class|script)' \
		"$STANDALONE_EXPORT_LOG" "$STANDALONE_RUNTIME_LOG"; then
		cat "$STANDALONE_EXPORT_LOG" "$STANDALONE_RUNTIME_LOG"
		echo "Standalone GDSQL runtime smoke test found a script loading error."
		exit 1
	fi
	echo "Standalone Linux runtime executed successfully."
fi

echo "Exported GDSQL runtime validation passed with $($GODOT_EXECUTABLE --version)."
