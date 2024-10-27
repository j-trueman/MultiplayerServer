extends Node

const SCORE_MAX = 999999999999
const VERSION = "0.3.4"
var port = 2095
var maxClients = 1000
var dealerMode = true
var chatgptMode = false

var mrm : MRM
var chatgpt : ChatGPTManager
var inviteManager : InviteManager
var regex : RegEx

func _ready():
	multiplayer.server_relay = false
	
	mrm = MRM.new()
	mrm.name = "MultiplayerRoundManager"
	add_child(mrm)
	
	inviteManager = InviteManager.new()
	inviteManager.name = "InviteManager"
	add_child(inviteManager)
	
	chatgpt = ChatGPTManager.new()
	chatgpt.name = "ChatGPTManager"
	add_child(chatgpt)
	
	var configFile = ConfigFile.new()
	var configPath = "res://server.properties"
	if configFile.load(configPath) != OK or configFile.get_sections().is_empty():
		configFile.set_value("server", "port", port)
		configFile.set_value("server", "maxClients", maxClients)
		configFile.set_value("server", "dealerMode", dealerMode)
		configFile.set_value("server", "chatgptMode", dealerMode and chatgptMode)
		for setting in mrm.settings.keys():
			configFile.set_value("round", setting, mrm.settings[setting])
		for item in mrm.itemAmounts.keys():
			configFile.set_value("items", item.to_camel_case(), mrm.itemAmounts[item])
		for setting in chatgpt.settings.keys():
			configFile.set_value("chatgpt", setting, chatgpt.settings[setting])
		configFile.save(configPath)
	else:
		port = configFile.get_value("server", "port")
		maxClients = configFile.get_value("server", "maxClients")
		dealerMode = configFile.get_value("server", "dealerMode")
		chatgptMode = dealerMode and configFile.get_value("server", "chatgptMode")
		for key in configFile.get_section_keys("round"):
			mrm.settings[key] = configFile.get_value("round", key)
		for key in configFile.get_section_keys("items"):
			mrm.itemAmounts[key.capitalize().to_lower()] = configFile.get_value("items", key)
		for key in configFile.get_section_keys("chatgpt"):
			chatgpt.settings[key] = configFile.get_value("chatgpt", key)
	
	if chatgptMode:
		chatgpt.initDB()
	
	regex = RegEx.new()
	regex.compile("^[A-Za-z0-9 ~!@#%&_=:;'<>,/\\-\\$\\^\\*\\(\\)\\+\\{\\}\\|\\[\\]\\.\\?\\\"]+$")
	
	_createServer()
	
	if dealerMode:
		AuthManager.loggedInPlayers[0] = {"username": "dealer", "status": false, \
			"score": SCORE_MAX}

func isValidString(input):
	return true if regex.search(input) != null else false

func _createServer():
	var multiplayerPeer = ENetMultiplayerPeer.new()
	var error = multiplayerPeer.create_server(port, maxClients)
	if error:
		return error
	multiplayer.multiplayer_peer = multiplayerPeer
	print("CREATED SERVER")

func terminateSession(id, reason : String):
	print("%s: %s" % [id, reason])
	closeSession.rpc_id(id, reason)
	await get_tree().create_timer(5, false).timeout
	multiplayer.multiplayer_peer.disconnect_peer(id, true)

@rpc("any_peer", "reliable")
func requestNewUser(username : String):
	var id = multiplayer.get_remote_sender_id()
	var key
	while username.length() > 0 and username.begins_with(" "):
		username = username.substr(1,username.length()-1)
	while username.length() > 0 and username.ends_with(" "):
		username = username.substr(0,username.length()-1)
	if isValidString(username):
		key = AuthManager._CreateNewUser(username)
	else:
		key = -1
	if typeof(key) != TYPE_STRING:
		match key:
			-1:
				terminateSession(id, "invalidUsername")
				return
			-2:
				terminateSession(id, "userAlreadyExists")
				return
			-3:
				terminateSession(id, "databaseError")
				return
	receivePrivateKey.rpc_id(id, key)

@rpc("any_peer", "reliable")
func verifyUserCreds(keyFileData : PackedByteArray, client_version : String):
	var id = multiplayer.get_remote_sender_id()
	if client_version != VERSION:
		terminateSession(id, "outdatedClient")
		return
	var keyFileDataString = keyFileData.get_string_from_utf8().split(":")
	if len(keyFileDataString) != 2:
		terminateSession(id, "malformedKey")
		return
	var keyData = keyFileDataString[0]
	var username = keyFileDataString[1]
	var verified = AuthManager._verifyKeyFile(username, keyData)
	if verified != 0:
		match verified:
			-1:
				terminateSession(id, "nonExistentUser")
				return
			-2:
				terminateSession(id, "invalidCreds")
				return
	AuthManager._loginToUserAccount(username)

@rpc("any_peer", "reliable")
func requestPlayerList():
	receivePlayerList.rpc_id(multiplayer.get_remote_sender_id(), \
		AuthManager.loggedInPlayers)
	
#@rpc("any_peer", "reliable")
#func requestUserExistsStatus(username : String):
	#print("requesting status of " + username)
	#if len(AuthManager._checkUserExists(username.to_lower())) > 0:
		#terminateSession(multiplayer.get_remote_sender_id(), "userExists")
		#return false
	#terminateSession(multiplayer.get_remote_sender_id(), "nonexistentUser")

@rpc("any_peer", "reliable")
func createInvite(toID):
	var id = multiplayer.get_remote_sender_id()
	var inviteTo = AuthManager.loggedInPlayers[toID]
	var found = mrm.getMatch(toID)
	if not found or found.dealer:
		if dealerMode and toID == 0:
			await get_tree().create_timer(1).timeout
			receiveInviteStatus.rpc_id(id, "dealer", "accept")
			mrm.createMatch([0, id])
		elif inviteTo.status:
			receiveInviteStatus.rpc_id(id, inviteTo.username, "busy")
		else:
			var invite = inviteManager.Invite.new(id, toID)
			inviteManager.activeInvites.append(invite)
	
@rpc("any_peer", "reliable")
func acceptInvite(from):
	if !inviteManager.acceptInvite(from, multiplayer.get_remote_sender_id()):
		print("This user does not have an invite from %s" % from)

@rpc("any_peer", "reliable")
func denyInvite(from):
	if !inviteManager.denyInvite(from):
		print("This user does not have an invite from %s" % from)
		
@rpc("any_peer", "reliable") 
func retractInvite(to): 
	inviteManager.retractInvite(multiplayer.get_remote_sender_id(), to)
	
@rpc("any_peer", "reliable") 
func retractAllInvites(): 
	inviteManager.retractAllInvites(multiplayer.get_remote_sender_id())
	
@rpc("any_peer", "reliable")
func getInvites(type):
	var list
	match type:
		"incoming":
			list = inviteManager.getInboundInvites(multiplayer.get_remote_sender_id())
		"outgoing":
			list = inviteManager.getOutboundInvites(multiplayer.get_remote_sender_id())
	receiveInviteList.rpc_id(multiplayer.get_remote_sender_id(), list)
	
@rpc("any_peer", "reliable")
func sendChat(message):
	if isValidString(message):
		var id = multiplayer.get_remote_sender_id()
		var target = mrm.getMatch(id)
		if target:
			var receiver = target.players.duplicate(true)
			receiver.erase(id)
			if receiver.front() > 0:
				receiveChat.rpc_id(receiver.front(), message.substr(0,200))
			elif chatgptMode:
				target.dealerChat(message.substr(0,200))

@rpc("any_peer", "reliable")
func verifyDealer(key, playerID):
	var id = multiplayer.get_remote_sender_id()
	var found = false
	if key == AuthManager.dealerKey:
		print("dealer connected")
		for child in get_node("MultiplayerRoundManager").get_children():
			if (playerID == 0 and child.dealer_bruteforceID == -1) or child.players[1] == playerID:
				child.dealer_bruteforceID = id
				linkDealer.rpc_id(id, child.players[1])
				found = true
				break
	if not found:
		multiplayer.multiplayer_peer.disconnect_peer(id)

@rpc("any_peer", "reliable")
func startDealer():
	var id = multiplayer.get_remote_sender_id()
	for child in get_node("MultiplayerRoundManager").get_children():
		if child.dealer_bruteforceID == id:
			child.dealer_action_send()
			break

@rpc("any_peer", "reliable")
func requestLeaderboard():
	var id = multiplayer.get_remote_sender_id()
	AuthManager.database.query("SELECT username, score FROM users "+\
		"WHERE score > 0 ORDER BY score DESC LIMIT 10")
	receiveLeaderboard.rpc_id(id, AuthManager.database.query_result)

# GHOST FUNCTIONS
@rpc("any_peer", "reliable") func closeSession(_reason): pass
@rpc("any_peer", "reliable") func receiveUserCreationStatus(_return_value: bool, _username): pass
@rpc("any_peer", "reliable") func notifySuccessfulLogin(_username : String): pass
@rpc("any_peer", "reliable") func receivePrivateKey(_keyString): pass 
@rpc("any_peer", "reliable") func receivePlayerList(_dict): pass
@rpc("any_peer", "reliable") func receiveInvite(_from, _id): pass
@rpc("any_peer", "reliable") func receiveInviteStatus(_username, _status): pass
@rpc("any_peer", "reliable") func receiveInviteList(_list): pass
@rpc("any_peer", "reliable") func receiveLeaderboard(_list): pass
@rpc("any_peer", "reliable") func opponentDisconnect(): pass
@rpc("any_peer", "reliable") func receiveChat(_message): pass
@rpc("any_peer", "reliable") func linkDealer(_id): pass
