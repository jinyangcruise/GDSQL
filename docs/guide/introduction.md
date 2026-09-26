# Introduction

GDSQL is a Godot editor plugin and runtime library for structured game data. It
is designed around two responsibilities:

- **Content** is authored with the game: items, characters, dialogue, balance,
  asset references, and other definitions shared by every player.
- **Saved state** changes per playthrough: progression, inventory, character
  customization, quest choices, and similar durable runtime data.

The editor provides conventional database and table views. The runtime exposes
typed queries, transactions, logical database roles, model bindings, save-slot
switching, and checkpoints without making scenes or generated models the schema
authority.

## The table is the source of truth

A table owns its columns, constraints, and rows. A generated model mirrors that
schema for typed GDScript access; it does not create or migrate the table.
Regeneration replaces only the generated base. The user-owned child script is
where custom methods and explicit relationships belong.

## Two content profiles

Choose a profile when the GDSQL welcome page first opens:

- **Direct Content** reads one authored content database from `res://` and is
  the shortest path for projects that do not need overlays or mods.
- **Managed Content** builds a disposable effective database from a base
  package plus optional DLC or mod packages.

Changing the profile later changes onboarding and runtime composition; it does
not migrate databases, models, resource paths, or save expectations. See
[Choose a content profile](./content-profiles) before creating production data.

## What GDSQL is not

GDSQL is not a remote server database or a multiplayer synchronization layer.
It does not require SQL text for normal use: the editor and GDScript API build
typed canonical queries. The graph and SQL frontends are secondary to the
table, model, and runtime workflows documented here.
