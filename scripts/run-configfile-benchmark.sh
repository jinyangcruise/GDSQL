#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"
PROFILE="${1:-standard}"
ITERATIONS="${GDSQL_BENCHMARK_ITERATIONS:-}"
BENCHMARK_ROOT="$(mktemp -d)"
BENCHMARK_PROJECT="$BENCHMARK_ROOT/project"
BENCHMARK_DATA="$BENCHMARK_ROOT/data"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$PROFILE"
REPORT_DIRECTORY="${GDSQL_BENCHMARK_REPORT_DIR:-$REPOSITORY_ROOT/reports/benchmarks/configfile/$RUN_ID}"
IMPORT_LOG="$BENCHMARK_ROOT/import.log"

case "$PROFILE" in
	smoke)
		ROW_COUNTS="1000"
		DEFAULT_ITERATIONS="3"
		;;
	standard)
		ROW_COUNTS="1000,10000"
		DEFAULT_ITERATIONS="3"
		;;
	full)
		ROW_COUNTS="1000,10000,100000"
		DEFAULT_ITERATIONS="1"
		;;
	*)
		echo "Unknown benchmark profile '$PROFILE'. Use smoke, standard, or full."
		exit 2
		;;
esac
ITERATIONS="${ITERATIONS:-$DEFAULT_ITERATIONS}"

cleanup() {
	rm -rf "$BENCHMARK_ROOT"
}
trap cleanup EXIT

if [ ! -x "$GODOT_EXECUTABLE" ] && ! command -v "$GODOT_EXECUTABLE" >/dev/null 2>&1; then
	echo "Godot executable not found: $GODOT_EXECUTABLE"
	exit 1
fi

mkdir -p "$BENCHMARK_PROJECT/addons"
mkdir -p "$REPORT_DIRECTORY"
cp -R "$REPOSITORY_ROOT/addons/gdsql" "$BENCHMARK_PROJECT/addons/gdsql"
cp -R "$REPOSITORY_ROOT/scripts/benchmark/configfile/." "$BENCHMARK_PROJECT"

export XDG_CONFIG_HOME="$BENCHMARK_ROOT/xdg-config"
export XDG_CACHE_HOME="$BENCHMARK_ROOT/xdg-cache"
export XDG_DATA_HOME="$BENCHMARK_ROOT/xdg-data"

if ! "$GODOT_EXECUTABLE" --headless --editor --path "$BENCHMARK_PROJECT" --quit \
		> "$IMPORT_LOG" 2>&1; then
	cat "$IMPORT_LOG"
	echo "ConfigFile benchmark project import failed."
	exit 1
fi

if grep -Eiq 'SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve (class|script)' \
		"$IMPORT_LOG"; then
	cat "$IMPORT_LOG"
	echo "ConfigFile benchmark project import found a script loading error."
	exit 1
fi

GDSQL_BENCHMARK_ROWS="$ROW_COUNTS" \
GDSQL_BENCHMARK_PROFILE="$PROFILE" \
GDSQL_BENCHMARK_ITERATIONS="$ITERATIONS" \
GDSQL_BENCHMARK_DATA_ROOT="$BENCHMARK_DATA" \
GDSQL_BENCHMARK_REPORT_DIR="$REPORT_DIRECTORY" \
	"$GODOT_EXECUTABLE" --headless --path "$BENCHMARK_PROJECT" \
	--script res://benchmark.gd

echo "ConfigFile benchmark reports:"
echo "  $REPORT_DIRECTORY/report.md"
echo "  $REPORT_DIRECTORY/report.json"
