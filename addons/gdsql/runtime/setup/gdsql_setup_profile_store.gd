@abstract
class_name GDSQLSetupProfileStore
extends RefCounted
## Storage-independent boundary for the selected project setup profile.


@abstract
func load_profile() -> GDSQLOperationResult


@abstract
func save_profile(profile: GDSQLSetupProfile.Kind) -> GDSQLOperationResult


@abstract
func clear_profile() -> GDSQLOperationResult
