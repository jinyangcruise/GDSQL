#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_CFG="$REPOSITORY_ROOT/addons/gdsql/plugin.cfg"
REQUESTED_VERSION="${1:-}"

usage() {
	echo "Usage: $0 patch|MAJOR.MINOR.PATCH"
}

CURRENT_VERSION="$(sed -n 's/^version="\([^"]*\)"$/\1/p' "$PLUGIN_CFG")"

if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
	echo "Error: plugin.cfg contains an invalid version: $CURRENT_VERSION"
	exit 1
fi

case "$REQUESTED_VERSION" in
	patch)
		NEXT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
		;;
	[0-9]*.[0-9]*.[0-9]*)
		if [[ ! "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			usage
			exit 1
		fi
		NEXT_VERSION="$REQUESTED_VERSION"
		;;
	*)
		usage
		exit 1
		;;
esac

if [ "$NEXT_VERSION" = "$CURRENT_VERSION" ]; then
	echo "Error: addon version is already $CURRENT_VERSION"
	exit 1
fi

TEMP_FILE="$(mktemp "$PLUGIN_CFG.tmp.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT

awk -v version="$NEXT_VERSION" '
	BEGIN { replacements = 0 }
	/^version="[^"]*"$/ {
		print "version=\"" version "\""
		replacements++
		next
	}
	{ print }
	END {
		if (replacements != 1) {
			exit 1
		}
	}
' "$PLUGIN_CFG" > "$TEMP_FILE"

chmod 0644 "$TEMP_FILE"
mv "$TEMP_FILE" "$PLUGIN_CFG"
trap - EXIT

echo "Updated GDSQL from $CURRENT_VERSION to $NEXT_VERSION."
echo "Commit this change before creating tag v$NEXT_VERSION."
