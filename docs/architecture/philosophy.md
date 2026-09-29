# Project philosophy

GDSQL aims to provide an easy-to-use data layer built specifically for Godot,
on top of a foundation stable enough to support a full game rather than only an
editor prototype.

Ease of use and architectural rigor are not opposing goals. The editor should
make common work obvious; the runtime should make the same work predictable.
Complexity belongs behind explicit concepts instead of being pushed onto every
game developer.

## Godot-native, not database-shaped at any cost

GDSQL uses Godot's language, Variant types, Resources, paths, scenes, editor
surfaces, and project lifecycle. It does not require a separate server or force
developers to translate every game concept into a server-database workflow.

Database ideas remain valuable where they protect data: schemas, constraints,
transactions, indexes, typed queries, deterministic ordering, and migrations.
They should serve Godot projects rather than make Godot imitate a conventional
database administration tool.

## Simple first, capable underneath

A new user should be able to create a database, define a table, edit rows,
generate a model, and load it at runtime through one guided path.

Advanced projects should not outgrow that path. Relationships, multiple save
slots, Resources, transactions, managed packages, mods, and future storage
backends extend the same concepts. GDSQL avoids a separate "beginner system"
that must later be discarded.

The table view is therefore the primary editor experience. Graphs, SQL text,
and agent integrations are additional frontends when they provide a concrete
advantage; they are not alternate execution engines.

## One meaning, multiple interfaces

An operation should have one canonical meaning regardless of whether it came
from a table action, typed GDScript, a model, a graph, or a future tool.

All frontends converge on `QuerySpec` and the same validation, planning,
execution, transaction, catalog, and storage contracts. This prevents subtle
differences where an editor action accepts data that runtime code rejects, or
where a new interface bypasses integrity rules.

## Explicit ownership

GDSQL keeps authority visible:

- Tables own schemas.
- Models own typed game-facing behavior, not table migration.
- The content role owns shared definitions.
- Save slots own mutable playthrough state.
- Settings own mutable state shared across saves.
- Packages own authored content layers; the effective cache is disposable.
- Game code owns policy decisions such as missing mod content, save migration,
  networking authority, and conflict resolution.

This separation reduces magic. A relationship declaration provides navigation;
it does not silently create a table constraint. A profile change alters runtime
composition guidance; it does not move data. A model regeneration updates the
generated base; it does not overwrite custom functions.

## Safe operations over convenient corruption

Mutations should validate before commit and fail with structured diagnostics.
Related batch changes should be atomic. Destructive actions should identify
their target, distinguish unregistering from deletion, and require explicit
confirmation.

GDSQL does not silently repair ambiguous state, discard unresolved mod-owned
identifiers, or rewrite saves because active packages changed. It reports the
condition and leaves game-specific policy to the game.

## Debuggable by construction

Systems are easier to trust when their boundaries can be inspected. Stable
domain concepts use typed classes. Results carry diagnostics owned by the stage
that produced them. Dependencies are supplied explicitly instead of hidden in
mutable global services.

Editor structures should use reusable scenes when layout matters. A scene may
show skeleton data so it remains understandable in isolation, while service
objects retain the real state and behavior. Logs identify the action that
failed instead of leaving the developer with a silent button.

## Stable foundation, deliberate evolution

GDSQL should not repeatedly reinvent its public concepts. Query meaning,
catalog authority, logical roles, storage contracts, generated/user model
separation, and structured results form the long-term foundation.

New storage formats and frontends should fit those contracts. Persisted formats
and public APIs require versions, compatibility rules, dry-run migrations, and
recovery guidance before release. Backward compatibility is a product feature,
not cleanup postponed until after adoption.

Stability does not mean freezing mistakes. A major Godot change may unlock a
substantially better foundation. A mature generic type system, for example,
could justify a major revision to typed query results, model collections, and
optional-value handling. That kind of change should be designed as an explicit
versioned migration, not introduced gradually through incompatible minor
updates.

## Scope is part of quality

GDSQL is a local game-data layer and authoring workbench. It is not currently a
network protocol, remote database server, multiplayer authority system, or
automatic solution to every serialization problem.

Potential features belong in active development only when their workflow,
ownership, failure behavior, and architectural boundary are understood. Keeping
SQL compilation, advanced graph authoring, dynamic scene preview, interchange,
and networking work scoped prevents secondary ideas from destabilizing the
foundation players and developers depend on.

## The practical standard

A feature belongs in GDSQL when it makes game data easier to author or safer to
use without creating a second source of truth. It should be understandable in
the editor, usable from code, diagnosable when it fails, and compatible with the
same core pipeline.

That is the balance the project protects: approachable enough to be plug and
play, explicit enough for serious projects, and stable enough that developers
can build their own tools and game systems on top of it.
