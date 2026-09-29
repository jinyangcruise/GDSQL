# Choose a content profile

The profile determines how the runtime obtains authored definitions. Choose it
before creating production databases because switching profiles does not move
or transform existing data.

| | Direct Content | Managed Content |
|---|---|---|
| Best for | One shipped definition database | Base game plus DLC, mods, or layered content |
| Authored source | Registered `res://` database | Immutable package databases |
| Runtime content | Reads the authored database | Reads a generated effective cache |
| Package provenance | Not needed | Tracked per effective row |
| Save compatibility | Application-defined | Compared with the active package set |
| Setup cost | Low | Higher; package and cache configuration required |

## Direct Content

Use Direct Content when the project ships one authoritative set of definitions.
The standard content database lives under `res://data`, while save slots live
under `user://gdsql/saves`. Runtime content models resolve the database bound to
the `content` role directly.

## Managed Content

Use Managed Content when definitions can be overlaid by packages. The standard
layout is:

```text
res://content/base/          base package and manifest.cfg
res://content/packages/      optional shipped package directories
user://gdsql/mods/           optional user-installed package directories
user://gdsql/cache/effective_content/  disposable effective-content cache
```

Open **Managed content setup**, create the base database, validate the package
set, then select **Save & Build Cache**. Runtime startup resolves the enabled
packages deterministically and binds the resulting `effective_content`
database to the `content` role.

Games decide what to do when a save expects missing or changed packages. GDSQL
reports compatibility but does not silently delete or rewrite player data.

See [Managed content packages](./managed-content) for package layout, manifests,
overlays, cache rebuilding, and save compatibility.

## Switching profiles

**Reset / Change Profile** returns to profile selection and changes onboarding
configuration only. Before switching a real project, plan migration for:

- database roots and registrations;
- Resource paths stored by authored content;
- generated model bindings;
- package manifests and effective cache;
- save package expectations.

Treat a profile migration as a project migration, not a reversible display
preference.
