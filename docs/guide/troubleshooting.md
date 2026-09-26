# Troubleshooting

## Start with GDSQL Logs

Open the **GDSQL Logs** bottom dock. Its status indicator summarizes recent
plugin messages. Operation failures include an action name and structured GDSQL
diagnostics. Script compatibility failures are also sent to Godot's Output so
parser and dependency errors remain visible with normal engine errors.

## Runtime did not start

Call `GDSQLRuntime.get_start_result()` and print its diagnostics. Common causes
are an incomplete Welcome checklist, an unbound logical role, a missing
registration, or an invalid Managed Content package/cache configuration.

Do not query or register models until `GDSQLRuntime.is_started()` is true.

## Model Assistant reports a script error

Open the user-owned model through the assistant and fix Godot parser or
dependency errors first. The model must extend its generated base and be
instantiable for normal runtime registration. An empty `relationships()` method
is valid because same-database foreign-key relationships are inferred.

Regenerate the base after changing table columns. GDSQL preserves the user-owned
script, so custom functions remain intact.

## A row cannot be saved

Correct highlighted type or required-value errors first. If validation passes,
inspect the GDSQL Logs diagnostic for unique, primary-key, foreign-key, or
read-only failures. A batch is atomic: one failing row prevents every pending
row in that batch from committing.

## A referenced row cannot be selected

Same-database pickers require one unambiguous foreign key. Cross-role content
pickers require a mapping registered through the save model's Model Assistant.
Both pickers currently load a bounded first result set; large-data server-side
search and paging remain future work.

## A Resource is unavailable

Confirm that the asset still exists, its type matches the column's concrete
Resource subtype, and the column is **Referenced** when it points to a saved
asset. Imported audio should be selected from an existing audio file, not
created as an empty `AudioStreamMP3` or `AudioStreamOggVorbis` Resource.

## Undo is unavailable

Editor Undo/Redo is bounded to committed non-Resource update batches in the
current session. Inserts, deletes, Resource edits, and editor restarts do not
have recoverable row history.
