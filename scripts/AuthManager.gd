extends Node

var database : SQLite
var loggedInPlayerIds = {}
var crypto = Crypto.new()

func _ready():
	multiplayer.peer_disconnected.connect(_logoutOfUserAccount)
	database = SQLite.new()
	database.path = "res://authkeys.db"
	database.open_db()
	var result = database.query("SELECT * FROM users WHERE 0")
	if result:
		print("TABLE ALREADY EXISTS")
	else:
		print("TABLE DOES NOT EXIST. CREATING...")
		var table = {
			"username" : {"data_type" : "text", "primary_key":true, "not_null": true},
			"key" : {"data_type": "blob", "not_null":true}
		}
		database.create_table("users", table)

func _CreateNewUser(username : String):
	# Make sure username is all lowercase and less than 11 characters
	username = username.to_lower()
	if len(username) > 10: 
		return null
	
	# Return false if user already exists
	if len(_checkUserExists(username)) > 0: 
		return null
	
	# Generate private key
	var privateKey = CryptoKey.new()
	privateKey = crypto.generate_rsa(4096)
	
	# Insert user into database
	if !_InsertToDatabase(username, privateKey.save_to_string().to_utf8_buffer()): 
		return null
	
	# Append username to private key and return this to user for storage
	var keyString = privateKey.save_to_string() + ":%s" % username
	return keyString

func _checkUserExists(usernameToCheck : String):
	# Check database for requested user
	var userExists = database.select_rows("users", "username = '%s'" % usernameToCheck, ["*"])
	return userExists

func _InsertToDatabase(username : String, privateKey : PackedByteArray) -> bool:
	username = username.to_lower()
	var data = {
		"username" : username,
		"key" : privateKey,
	}
	# Attempt to insert new user data into database
	var success = database.insert_row("users", data)
	if !success:
		return false
	print("CREATED NEW USER %s" % username)
	return true
	
func _verifyKeyFile(username : String, keyData : String):
	# Get the key in the database for the requested user
	var keyInDatabase = database.select_rows("users", "username = '%s'" % username, ["key"])
	# If a key is not returned, the user does not exist
	if len(keyInDatabase) == 0:
		print("User does not exist")
		return false
	# If the key in the database matches the provided key then the user can be authenticated
	if keyInDatabase[0].values()[0].get_string_from_utf8() != keyData:
		return false
	return true

# Only called if _verifyKeyFile returns true
func _loginToUserAccount(username : String):
	loggedInPlayerIds[username] = multiplayer.get_remote_sender_id()
	MultiplayerManager.notifySuccessfulLogin.rpc_id(multiplayer.get_remote_sender_id(), username)
	print("USER %s LOGGED IN WITH ID %s" % [username, multiplayer.get_remote_sender_id()])

# Called whenever a session disconnects
func _logoutOfUserAccount(sessionID):
	# Make sure the user is logged in before trying to log them out
	# (This avoids a weird bug where the server still tries to log a user out even if their initial connection fails)
	var found = loggedInPlayerIds.find_key(sessionID)
	if found != null:
		# Remove the player from the list of logged in players
		loggedInPlayerIds.erase(found)
		print("SESSIONID %s LOGGED OUT" % sessionID)
