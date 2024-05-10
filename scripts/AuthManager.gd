extends Node

var database : SQLite
var loggedInPlayerIds = {}
var crypto = Crypto.new()
var data = "multiplayersignature"

# Called when the node enters the scene tree for the first time.
func _ready():
	MultiplayerManager.playerDisconnected.connect(_logoutOfUserAccount)
	database = SQLite.new()
	database.path = "res://authsignatures.db"
	database.open_db()
	var result = database.query("SELECT * FROM users WHERE 0")
	if result:
		print("TABLE ALREADY EXISTS")
	else:
		print("TABLE DOES NOT EXIST. CREATING...")
		var table = {
			"username" : {"data_type" : "text", "primary_key":true, "not_null": true},
			"signature" : {"data_type": "blob", "not_null":true}
		}
		database.create_table("users", table)

func _generateUserCredentials():
	var privateKey = CryptoKey.new()
	privateKey = crypto.generate_rsa(4096)
	var signature = crypto.sign(HashingContext.HASH_SHA256, data.sha256_buffer(), privateKey)
	var keyAsString = privateKey.save_to_string()
	return [signature,keyAsString]

func _InsertNewUser(username : String, signature : PackedByteArray) -> bool:
	username = username.to_lower()
	var data = {
		"username" : username,
		"signature" : signature,
	}
	var success = database.insert_row("users", data)
	if success:
		print("CREATED NEW USER %s" % username)
		return true
	else:
		print("FAILED TO CREATE, USER %s ALREADY EXISTS" % username)
		return false
		
func _getUserSignature(username : String):
	var signature = database.select_rows("users", "username = '%s'" % username,["signature"])
	if len(signature) == 0:
		print("USER DOES NOT EXIST")
		return false
	return signature[0].get("signature", PackedByteArray())
	
func _verifyUserSignature(signature : PackedByteArray, key):
	var keyToUse = CryptoKey.new()
	keyToUse.load_from_string(key)
	var verified = crypto.verify(HashingContext.HASH_SHA256, data.sha256_buffer(), signature, keyToUse)
	if !verified:
		return false
	return true
	
func _loginToUserAccount(accountName : String):
	loggedInPlayerIds[accountName] = multiplayer.get_remote_sender_id()
	print("USER %s LOGGED IN WITH ID %s" % [accountName, multiplayer.get_remote_sender_id()])

func _logoutOfUserAccount(accountID):
	loggedInPlayerIds.erase(loggedInPlayerIds.keys()[loggedInPlayerIds.values().find(accountID)])
