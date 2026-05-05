extends Object

## Usage:
#var USER_PASSWORD = "我的密码123"
#var CONFIG_PATH = "user://settings.cfg"
#
#var dek_base64 = GDSQL.CryptoUtil.generate_dek()
#var encrypted_dek_data = GDSQL.CryptoUtil.encrypt_dek(dek_base64, USER_PASSWORD)
#
#var cfg = ConfigFile.new()
#cfg.set_value("settings", "volume", 80)
#cfg.set_value("settings", "fullscreen", true)
#
#GDSQL.CryptoUtil.save_encrypted_config(cfg, dek_base64, CONFIG_PATH)
#print("✅ 加密配置保存成功")
#
#var new_cfg = ConfigFile.new()
#var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(encrypted_dek_data, "我的密www码13")
#printt(recovered_dek == dek_base64)
#if recovered_dek != "":
	#GDSQL.CryptoUtil.load_encrypted_config(new_cfg, recovered_dek, CONFIG_PATH)
	#print("\n✅ 解密成功：")
	#print("volume: ", new_cfg.get_value("settings", "volume"))
	#print("fullscreen: ", new_cfg.get_value("settings", "fullscreen"))
#else:
	#print("Wrong passwrod!")
	
const VERIFY_CONTENT = "Hello World!"

static func _pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var pad_len = 16 - (data.size() % 16)
	for i in pad_len:
		data.append(pad_len)
	return data
	
static func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	var pad_len = data[-1]
	return data.slice(0, data.size() - pad_len)
	
static func generate_dek() -> String:
	var crypto = Crypto.new()
	var dek_bytes = crypto.generate_random_bytes(32)
	return Marshalls.raw_to_base64(dek_bytes)
	
static func encrypt_dek(dek: String, user_password: String) -> String:
	var crypto = Crypto.new()
	var salt = crypto.generate_random_bytes(16)
	var iv = crypto.generate_random_bytes(16)
	var iv_verify = crypto.generate_random_bytes(16)
	
	var key = crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		salt,
		user_password.to_utf8_buffer()
	).slice(0, 32)
	
	# AES-CBC 加密（严格文档模式）
	var aes = AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	var dek_padded = _pkcs7_pad(dek.to_utf8_buffer())
	var encrypted_dek = aes.update(dek_padded)
	aes.finish()
	
	var ede64 = Marshalls.raw_to_base64(encrypted_dek)
	var salt64 = Marshalls.raw_to_base64(salt)
	var iv64 = Marshalls.raw_to_base64(iv)
	var iv_verify64 = Marshalls.raw_to_base64(iv_verify)
	
	# 直接加密一个字符串以便后面解密的时候做验证
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv_verify)
	var verify_code = aes.update(_pkcs7_pad(VERIFY_CONTENT.to_utf8_buffer()))
	var verify_code64 = Marshalls.raw_to_base64(verify_code)
	aes.finish()
	
	return ede64 + "|" + iv64 + "|" + salt64 + "|" + verify_code64 + "|" + iv_verify64
	
static func decrypt_dek(encrypted_dek_info: String, user_password: String) -> String:
	var parts = encrypted_dek_info.split("|")
	var encrypted_dek_b64 = parts[0]
	var iv_b64 = parts[1]
	var salt_b64 = parts[2]
	var verify_code64 = parts[3]
	var iv_verify_code64 = parts[4]
	
	var encrypted_dek = Marshalls.base64_to_raw(encrypted_dek_b64)
	var iv = Marshalls.base64_to_raw(iv_b64)
	var salt = Marshalls.base64_to_raw(salt_b64)
	var verify_code = Marshalls.base64_to_raw(verify_code64)
	var iv_verify = Marshalls.base64_to_raw(iv_verify_code64)
	
	var crypto = Crypto.new()
	var key = crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		salt,
		user_password.to_utf8_buffer()
	).slice(0, 32)
	
	var aes = AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, key, iv_verify)
	var encrypted_verify_code = aes.update(verify_code)
	aes.finish()
	var decrypted_verify_code = _pkcs7_unpad(encrypted_verify_code)
	if decrypted_verify_code != VERIFY_CONTENT.to_utf8_buffer():
		return "" # Wrong password!
		
	aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	var dek_bytes = aes.update(encrypted_dek)
	aes.finish()
	
	var dek_str = _pkcs7_unpad(dek_bytes).get_string_from_utf8()
	var dek_raw = Marshalls.base64_to_raw(dek_str)
	if dek_raw.size() == 32:
		return dek_str
	else:
		return "" # Wrong password!
		
static func save_encrypted_config(cfg: ConfigFile, dek_base64: String, path: String) -> Error:
	var dek_raw = Marshalls.base64_to_raw(dek_base64)
	return cfg.save_encrypted(path, dek_raw)
	
static func load_encrypted_config(cfg: ConfigFile, dek_base64: String, path: String) -> Error:
	var dek_raw = Marshalls.base64_to_raw(dek_base64)
	return cfg.load_encrypted(path, dek_raw)
