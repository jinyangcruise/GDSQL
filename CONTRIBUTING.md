# Contributing

## Getting Started

1. Clone the repository.
2. Open the project in Godot 4.7+.
3. Enable GDSQL in **Project Settings → Plugins**.
4. The GDSQL main screen button appears at the top of the editor.

## Development Setup

### Git Hooks

This repository includes two Git hooks in `.githooks/`:

- `pre-commit` formats staged GDScript files and stages the formatted result.
- `pre-push` runs the complete GdUnit4 test suite and rejects the push if a test fails.

Enable it once:

```bash
git config core.hooksPath .githooks
```

Hooks provide quick local feedback. GitHub Actions runs the same test suite for pull requests and release tags, so CI remains the authoritative release gate.

### Formatter

This repository uses the GDQuest GDScript formatter for code formatting. The formatter may be checked by a separate GitHub Actions workflow so it can be enabled, disabled, or adjusted independently from the test workflow. But it is better to use it, otherwise the `format.yml` may fail.

It is recommended to use the formatter inside Godot Editor, for better linting messages and syntax error detection.

If you have the formatter installed locally, you can run it before committing:

```bash
gdscript-formatter --safe addons/gdsql tests
```

Preferebly it is better to keep code consistent and coherent by reordering it:
```bash
gdscript-formatter --reorder-code addons/gdsql tests
```

## Code Style

* Type hints are encouraged (`var x: int`, `func f() -> void`).
* Prefer `%UniqueNodeName` over `get_node()`.
* Keep GDScript files formatted with the project formatter.
* Follow Linter orientations on new code, older code need dedicated care.

## Testing

Tests use the **GdUnit4** framework and live under `tests/`.

```bash
# Run from Godot editor: open GdUnit panel → Run All
# Or via CLI:
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests
```

Set `GODOT_BIN` if the executable is not named `godot` on your system.

## Releases and Versioning

`addons/gdsql/plugin.cfg` is the single source of truth for the addon version. The release tag must be that version prefixed with `v`; the packaging workflow rejects a mismatch.

Until the first stable release, published development releases stay on the `0.9.x` line. Increment the patch component once per release, not once per commit:

```bash
./scripts/bump-version.sh patch
git add addons/gdsql/plugin.cfg
git commit -m "Bump version to 0.9.1"
git tag -a v0.9.1 -m "GDSQL 0.9.1"
git push origin HEAD v0.9.1
```

The script also accepts an explicit version such as `./scripts/bump-version.sh 1.0.0`. Release tags are immutable inputs to packaging; hooks and CI do not rewrite commits or recreate tags.

## Pull Request Process

1. Ensure all tests pass before submitting.
2. Format changed GDScript files.
3. For a release, bump `addons/gdsql/plugin.cfg` in a dedicated commit.
4. Tag the release commit with `vX.X.X` to trigger the packaging workflow.
