class_name GDSQLConfigFileContentPackageFingerprintProvider
extends GDSQLContentPackageFingerprintProvider
## Hashes a directory package using sorted relative paths and file bytes.

func fingerprint(source: GDSQLContentPackageSource) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if source == null or source.manifest == null or not DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(source.package_root),
	):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_PACKAGE_FINGERPRINT_SOURCE_INVALID",
				"Cannot fingerprint a package without an accessible source directory.",
			),
		)
		return result
	var relative_paths: Array[String] = []
	_collect_files(source.package_root, "", relative_paths)
	relative_paths.sort()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_PACKAGE_FINGERPRINT_FAILED",
				"Could not initialize the package fingerprint.",
			),
		)
		return result
	for relative_path in relative_paths:
		var file := FileAccess.open(source.package_root.path_join(relative_path), FileAccess.READ)
		if file == null:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_PACKAGE_FINGERPRINT_FILE_UNREADABLE",
					"Could not fingerprint package file '%s'." % relative_path,
				),
			)
			return result
		var length := file.get_length()
		hashing.update(
			("%d:%s:%d:" % [relative_path.length(), relative_path, length]).to_utf8_buffer(),
		)
		hashing.update(file.get_buffer(length))
	result.value = GDSQLContentPackageFingerprint.new(
		source.manifest.package_id,
		source.manifest.version,
		hashing.finish().hex_encode(),
	)
	return result


func _collect_files(
		root: String,
		relative_directory: String,
		files: Array[String],
) -> void:
	var directory_path := root.path_join(relative_directory)
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	var file_names := directory.get_files()
	file_names.sort()
	for file_name in file_names:
		files.append(relative_directory.path_join(file_name))
	var directory_names := directory.get_directories()
	directory_names.sort()
	for directory_name in directory_names:
		_collect_files(root, relative_directory.path_join(directory_name), files)
