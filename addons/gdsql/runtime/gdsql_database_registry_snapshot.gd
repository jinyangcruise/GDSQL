class_name GDSQLDatabaseRegistrySnapshot
extends RefCounted
## Typed durable state read or written by a database registry store.

var registrations: Array[GDSQLDatabaseRegistration] = []
var role_bindings: Array[GDSQLDatabaseRoleBinding] = []
