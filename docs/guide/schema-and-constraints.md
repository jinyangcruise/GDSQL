# Schemas and constraints

The table schema is authoritative. Generated models mirror it; model scripts do
not create, rename, or migrate columns.

## Edit a table

Open the database document and expand a table. Each table provides:

- **Open Data** for the table workbench;
- **Model** for the model binding assistant;
- **Reset Data…** to delete every row and reset its generated-key sequence;
- indexes, foreign keys, and column definitions.

Schema edits remain drafts until the database document's **Save Changes**
action succeeds.

## Column rules

Each column defines a Godot Variant type and may define nullability, uniqueness,
automatic generation, and a default. Auto-increment is supported only for an
`int` primary key.

Right-click a column to open its actions. Removing a column is staged rather
than applied immediately. Right-click it again to restore it before saving.
GDSQL also stages dependent local indexes and foreign keys for removal and
discards dependent unsaved constraints. A foreign key from another table blocks
the removal until that constraint is removed and saved first.

## Same-database foreign keys

Open **Foreign Keys** and select **Add Foreign Key**. The editor limits choices
to valid combinations:

- the local and target columns use the same type;
- the type is `int`, `String`, or `StringName`;
- the target column is primary or unique;
- the target belongs to a different table in the same database.

The generated constraint name follows
`fk_<source>_<local>_<target>_<target_column>` and updates with the selected
inputs.

Foreign keys are integrity constraints, not model declarations. Inserts and
updates cannot create orphaned keys. Updating or deleting a referenced target
uses `RESTRICT`. Validation considers the final transaction state, so related
changes can be staged in either order inside one transaction.

## Resetting and destroying data

**Reset Data…** truncates one table and resets its generated-key metadata. It
remains subject to foreign-key restrictions.

At database level, **Remove from GDSQL** unregisters the database but preserves
its files. **Destroy Files…** permanently removes the selected database's
catalog, schemas, tables, and rows after confirmation.
