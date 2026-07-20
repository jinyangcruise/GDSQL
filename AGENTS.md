# GDSQL Agent Guide

This repository is undergoing an architectural rewrite. All agents must read
`docs/architecture/core.md`, `docs/architecture/glossary.md`, and
`docs/architecture/mermaid-diagram.md` before changing `addons/gdsql`.

## Source of truth

- `docs/architecture/core.md` defines boundaries, dependency direction, and
  lifecycle rules.
- `docs/architecture/glossary.md` defines names and responsibilities.
- `docs/architecture/mermaid-diagram.md` is the dependency map.
- If code and these documents disagree, stop and report the discrepancy unless
  the task explicitly updates the architecture.

## Non-negotiable rules

1. `QuerySpec` is descriptive data. It must not access storage, catalog files,
   editor controls, transactions, caches, or execution state.
2. Frontends translate into `QuerySpec`; SQL syntax and graph concerns stop at
   their translators.
3. Runtime code depends on contracts. Concrete ConfigFile code is confined to
   `storage/configfile` and the composition root.
4. The dependency direction is frontend/editor → API → query model →
   validation/binding → planning → execution → catalog/storage contracts →
   ConfigFile backend. Never introduce reverse imports.
5. Use typed domain classes for stable concepts. Use `Dictionary` only at
   dynamic serialization, import, compatibility, or external-data boundaries.
6. Use constructor injection for stable dependencies. Do not add mutable public
   service properties as hidden dependencies.
7. Query models are constructed once and treated as immutable after build or
   compilation. Builders must reject mutation after `build()`.
8. Each pipeline stage returns structured results and diagnostics owned by that
   stage. Do not print, push editor UI, or throw for ordinary query failures.
9. Globally registered Godot classes use the `GDSQL` prefix. Internal helper
   scripts that are not globally registered may use shorter names.
10. The initial scaffold may contain typed properties, enums, constructors,
	abstract methods, and result shells, but must not invent execution logic.

## Runtime workspace boundary

`addons/gdsql` contains plugin implementation only. Project-owned runtime data
belongs under `res://.gdsql/` and `res://data/` (default data if not created, is selectable):

```text
res://.gdsql/settings.cfg
res://.gdsql/graphs/
res://data/databases.cfg
res://data/<database>/schema/*.cfg || *.gsql
res://data/<database>/tables/*.cfg || *.gsql
```

`.gdsql` is project/tool configuration, not plugin source. Database paths must
be resolved by storage infrastructure; higher layers must not construct these
paths or depend on ConfigFile section names.

## Change protocol for agents

- Inspect current status before editing; preserve unrelated user changes.
- Keep one architectural boundary per change.
- Add or update tests at the boundary being changed.
- Update the glossary or architecture docs when introducing a new public
  concept, folder, dependency, or result type.
- Update the glossary `State` column whenever a concept moves from
  `Planned` to `Scaffolded`, `Implemented`, `Tested`, or `Verified`.
- Before handoff, run Godot parsing/tests available in the repository and
  report any environment limitation precisely.

## Formatting 

Do not worry if code was reordered, it's the formatter.
