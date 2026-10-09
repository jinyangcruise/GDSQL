# Migrations and recovery

Migrations preserve a durable database while its schema evolves. They matter
once saves or shared development databases can exist at an older schema than
the current project.

During early prototyping, direct schema changes are usually enough. Start
migration history before distributing builds that create persistent saves or
before a team needs an auditable sequence of schema changes.

## The four records

GDSQL keeps the intended history separate from the state of each database:

| Record | Default location | Responsibility |
|---|---|---|
| Authored history | `res://.gdsql/migrations/<stream>/<migration_id>.cfg` | Append-only, project-owned migration definitions |
| Trusted schema state | `res://.gdsql/migration_states/<stream>.cfg` | Evidence that a history prefix produces the project schema |
| Applied ledger | `<data_root>/<database>/migrations.cfg` | The history already applied to one durable database |
| Recovery data | `<data_root>/.gdsql_migration_recovery/<database>/` | Temporary snapshot used while one migration is applied |

The registration's migration stream selects the authored history. It defaults
to the logical database name. Multiple save slots can therefore share one
history while retaining independent applied ledgers.

Commit authored history and trusted schema state to version control. A
project-owned database under `res://` is normally committed as well. A player's
ledger and rows under `user://` belong to that save and must not be copied into
project history.

## Author a schema migration

Open the database document and stage exactly one table change. Then:

1. Select **Create Migration**.
2. Keep **Current schema draft** selected.
3. Review the generated stable ID and description.
4. Select **Preview Migration**.
5. Inspect the operation, affected rows, and destructive warning.
6. Select **Save and Apply**.

The editor currently records one typed schema step per migration. The step can
create, alter, rename, or drop a table. Column, index, and foreign-key changes
inside one table alteration remain one step.

Migration IDs must be unique and sort after the current history head. The
editor suggests timestamp-prefixed IDs such as
`20261009_153000_alter_heroes`. Treat an applied ID and its definition as
immutable.

After the first migration is authored, direct schema saves are disabled for
that migration stream. Further schema changes must extend its history. This
prevents the current schema from drifting away from the sequence used to
upgrade older databases.

## Author a data migration

Data migrations update existing rows with the same typed expressions used by
the query system. Start with no pending schema draft, select **Create
Migration**, and choose **Update table rows**. Select the table, assignments,
and optional `WHERE` conditions before previewing.

The preview records the expected affected-row count. Application stops and
restores the recovery snapshot if the actual count differs. Use separate,
ordered migrations when a data rewrite depends on a schema change—for example:

1. add a nullable `faction` column;
2. populate existing heroes with a typed data migration;
3. make `faction` required in a later schema migration.

The current editor does not author arbitrary scripts as migration steps. This
keeps history serializable, reviewable, and deterministic.

## What happens when a game is updated

Runtime bootstrap prepares every durable registration before models or gameplay
use it:

1. load the registration's authored history and trusted schema state;
2. recover any interrupted migration;
3. read that database's applied ledger;
4. preview and apply the next missing migration;
5. repeat until the trusted project history head is reached;
6. open the runtime database and register it for use.

Suppose a save ledger ends at `002_add_faction` and the updated game ships
history through `005_add_reputation`. That save applies `003`, `004`, and `005`
in order. A different save already at `004` applies only `005`.

Writable databases outside `res://`, including normal `user://` save slots,
persist their ledgers and can be upgraded during startup. Project content under
`res://` is read-only in exported builds, so runtime verifies that its schema
already matches trusted project state. Apply its pending migrations in the
editor before exporting.

Fresh save slots do not replay every historical migration. GDSQL provisions
the current template schema without copying rows, verifies its fingerprint,
and adopts the current history head as a baseline.

## Failure and interruption recovery

Before applying a migration, GDSQL creates a durable snapshot of the target
database and its ledger. The migration is recorded as applied only after every
step succeeds and the resulting schema fingerprint is available.

- If application fails before the ledger entry is committed, GDSQL restores
  the snapshot.
- If the process stops after the ledger entry is committed but before cleanup,
  startup keeps the committed database and removes the stale snapshot.
- If a snapshot exists without a matching ledger entry, startup restores it
  before applying more history.
- If history, the ledger, and recovery evidence disagree, startup stops with a
  diagnostic instead of guessing.

Ordinary row transactions and checkpoints use a separate recoverable file
replacement protocol. An interrupted preparation restores the complete
previous table set; an interrupted cleanup retains the committed replacements.

Recovery snapshots protect an operation in progress. They are not downgrade
migrations, release backups, or a replacement for backing up important player
saves. GDSQL currently supports forward migration only.

## Team and release workflow

Use this sequence for a migration-managed database:

1. update the branch and confirm the database reports **up to date**;
2. stage and preview one change;
3. save and apply the migration locally;
4. inspect the generated history file, trusted state, and schema changes;
5. commit those project-owned files together;
6. test a fresh database and copies of saves from supported older releases;
7. apply all project-content migrations before export.

Do not edit, delete, rename, or reorder a migration that another database may
have applied. If a shipped migration needs correction, append a new migration.
Resolve parallel-branch conflicts by preserving already-shared history and
giving new entries later unique IDs.

## Status and common failures

The database document reports the state of its migration stream:

| Status | Meaning | Action |
|---|---|---|
| **no authored history** | Direct schema saving is still available | Continue prototyping or author the first migration |
| **pending** | The next definition exists but is not applied here | Discard unrelated drafts, review, and apply it |
| **up to date** | Ledger, history, and schema evidence agree | Safe to author the next migration |
| **unavailable** | History, schema, or recovery evidence is invalid | Read **GDSQL Logs** and resolve the diagnostic before editing |

Common protections include:

- **history changed/stale**: another change extended history after the preview;
- **schema drift**: the current schema differs from the last ledger fingerprint;
- **plan stale**: the ledger changed after preview;
- **project schema outdated**: a `res://` database has pending migrations;
- **recovery history missing/diverged**: recovery data cannot be reconciled
  safely with authored and applied history.

Never repair these states by manually editing checksums or the applied ledger.
Preserve the affected files, inspect the first diagnostic, and restore from a
known backup when the evidence cannot be reconciled.

