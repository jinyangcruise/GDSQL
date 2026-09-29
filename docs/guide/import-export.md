# Import and Export — Planned

Portable database interchange is backlog work and is not available in the
current editor.

The planned feature will import or export tables and query results without
depending on the active storage backend. A ConfigFile database and a future
paged-binary database should therefore use the same interchange contracts.

Initial formats:

- CSV for spreadsheet workflows and scalar table data.
- JSON for structured data exchange.
- GDSQL-native interchange for Godot Variant values that JSON and CSV cannot
  represent losslessly.

Imports must provide schema mapping and validation, a change preview, explicit
append/replace/upsert behavior, structured diagnostics, and one atomic mutation
boundary. Export must define Resource handling, null encoding, stable column
order, and format/version metadata where required.

Network replication is a separate concern. An exported file or snapshot may be
transferred between players in the future, but receiving it must not grant
permission to execute arbitrary queries or overwrite authoritative runtime
state.
