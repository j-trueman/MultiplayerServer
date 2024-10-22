extends Node

var database : SQLite
var loggedInPlayers = {}
var crypto = Crypto.new()
var dealerKey

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
			"key" : {"data_type": "blob", "not_null":true},
			"score" : {"data_type": "int", "not_null":true}
		}
		database.create_table("users", table)
	
	var dealerKeyFile = FileAccess.open("res://dealerkey.key", FileAccess.WRITE_READ)
	if !dealerKeyFile:
		dealerKey = crypto.generate_rsa(4096)
		dealerKeyFile.store_string(dealerKey.save_to_string())
	else:
		dealerKey = dealerKeyFile.get_buffer(dealerKeyFile.get_length())
	dealerKeyFile.close()

func _CreateNewUser(username : String):
	# Make sure username is all lowercase and no more than 8 characters
	username = username.to_lower()
	if len(username) > 10 || len(username) < 1: 
		return -1
	
	# Return false if user already exists
	if len(_checkUserExists(username)) > 0: 
		return -2
	
	# Generate private key
	var privateKey = crypto.generate_rsa(4096)
	
	# Insert user into database
	if !_InsertToDatabase(username, privateKey.save_to_string().to_utf8_buffer()): 
		return -3
	
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
		"score" : 0
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
		return -1
	# If the key in the database matches the provided key then the user can be authenticated
	if keyInDatabase[0].values()[0].get_string_from_utf8() != keyData:
		return -2
	return 0

# Only called if _verifyKeyFile returns true
func _loginToUserAccount(username : String):
	var id = multiplayer.get_remote_sender_id()
	var score = database.select_rows("users", "username = '%s'" % username, \
		["score"]).front().score
	loggedInPlayers[id] = {"username": username, \
		"status": false, "score": score}
	MultiplayerManager.notifySuccessfulLogin.rpc_id(id, username)
	print("USER %s LOGGED IN WITH ID %s" % [username, id])

# Called whenever a session disconnects
func _logoutOfUserAccount(sessionID):
	# Make sure the user is logged in before trying to log them out
	# (This avoids a weird bug where the server still tries to log a user out even if their initial connection fails)
	var found = loggedInPlayers.get(sessionID)
	if found != null:
		# Remove the player from the list of logged in players
		loggedInPlayers.erase(sessionID)
		MultiplayerManager.inviteManager.retractAllInvites(sessionID, true)
		# If the user was in a match, end it and tell the other player
		_killMRM(sessionID)
		print("SESSIONID %s LOGGED OUT" % sessionID)
		
func _killMRM(sessionID):
	var mrm = get_node("/root/MultiplayerManager/MultiplayerRoundManager")
	var activeMatch = mrm.getMatch(sessionID)
	if !activeMatch:
		print("NO MATCH FOUND")
		return
	if not activeMatch.end:
		activeMatch.scores[int(not activeMatch.players.find(sessionID))] = 2
		activeMatch.awardWager()
	activeMatch.players.erase(sessionID)
	if len(activeMatch.players) == 1 and activeMatch.players[0] > 0:
		MultiplayerManager.opponentDisconnect.rpc_id(activeMatch.players[0])
	mrm.eraseMatch(activeMatch)
	print("ENDED MATCH")

func awardWager(sessionID, wager):
	if sessionID > 0:
		var player = loggedInPlayers[sessionID]
		player.score += wager
		database.update_rows("users", "username = '%s'" % player.username, \
			{"score": player.score})
