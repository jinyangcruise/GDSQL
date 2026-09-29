# Table workbench

Open a database, find the table, and select **Open Data**. The table document
runs the initial query automatically and keeps query controls separate from row
drafts.

## Browse and navigate

- Click a column header to cycle its row order.
- Click the `#` header to choose visible columns.
- Use the controls at the bottom for page size and page navigation.
- Use **Refresh** to reload the current page.
- Use `Ctrl+Shift+P` and search for a GDSQL database or table to navigate
  without returning to the database document.

Columns share the available width. Horizontal scrolling begins when every
visible column reaches its minimum width.

## Filter rows

Enable **WHERE**, then add typed conditions or nested groups. Each group has an
explicit precedence boundary and may be inverted with **NOT**. Apply the filter
to run it; changing the draft does not silently replace the visible result.

Resource fields expose only supported Inspector-visible scalar leaves. For
example, a `BoxMesh.size` value is filtered through `size.x`, `size.y`, or
`size.z`, not by comparing the complete `Vector3`.

Save or discard pending row changes before applying or clearing a filter.

## Add and edit rows

Select **Add Row** to open one insert draft below the result table. Generated
identity and timestamp columns are not editable. Required values must be valid
before **Save** succeeds.

Double-click an editable cell, or focus it and press Enter, to edit an existing
row. Tab advances across editable cells; Enter accepts the value and advances
down the same column.

All pending edits are submitted as one transaction. If one row is invalid or a
constraint fails, none of the batch is committed and the drafts remain visible.

## Select, duplicate, and delete

Hold Ctrl or Shift while selecting rows.

- **Duplicate** inserts every selected row atomically when an automatic primary
  key can be generated and copied values do not need user decisions.
- If a manual identity, unique value, or owned Resource must change, Duplicate
  copies the first selected row into an editable Add Row draft instead.
- **Delete** confirms and deletes all selected rows in one transaction.

Referenced Resources preserve their asset identity. Owned Resources copied to
an insert draft are independent deep copies.

## Undo and redo

Undo and Redo cover successfully committed, non-Resource update batches for
the current editor session. Inserting, deleting, editing Resources, or restarting
Godot clears or ends that history. History is intentionally not persisted.
