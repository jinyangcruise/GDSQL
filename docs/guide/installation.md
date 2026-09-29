# Installation

## Requirements

- Godot 4.x
- The `addons/gdsql` directory from this repository

Godot-AI is optional and is needed only for the agent tools described in
[Godot-AI tools](./godot-ai).

## Install and enable

1. Copy `addons/gdsql` into the project's `addons` directory.
2. Open **Project → Project Settings → Plugins**.
3. Enable **GDSQL**.
4. Select **GDSQL** from Godot's main-screen buttons.

The welcome page should ask you to choose **Direct Content** or
**Managed Content**. That profile choice is project tool configuration; it does
not create or move a database until you confirm the next setup action.

## Project-owned files

GDSQL keeps plugin code and project data separate:

```text
res://addons/gdsql/       plugin implementation
res://.gdsql/             project tool configuration
res://data/               default Direct Content data root
res://content/            conventional Managed Content package roots
user://gdsql/             registry, saves, cache, and user-installed mods
```

Use the editor workflow to create these files. Do not copy sample databases
into a production project as a substitute for choosing a profile and creating
its registrations.

Continue with [Create your first project](./getting-started).
