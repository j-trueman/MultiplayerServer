extends Node

signal playerConnected(peer_id, player_info)
signal playerDisconnected(peer_id)
signal serverDisconnected
signal providedUsername(username)

const MultiplayerRoundManager = preload("res://scripts/MultiplayerRoundManager.gd")

var players = {}
var playersLoaded = 0

var playerInfo = {"name": "Name"}
var lobbyIdChars = 'qwertyuiopasdfgjklzxcvbnm123456789QWERTYUIOPASDFGJKLZXCVBNMM'
var joinCodeChars = 'qwertyuiopasdfghjklzxcvbnm'
var multiplayerRoundManager
var roundmanagerstore = []

func _ready():
	multiplayer.peer_connected.connect(_onPlayerConnected)
	multiplayer.peer_disconnected.connect(_onPlayerDisconnected)
	multiplayer.connected_to_server.connect(_onPlayerConnectedOk)
	multiplayer.connection_failed.connect(_onConnectionFail)
	multiplayer.server_disconnected.connect(_onServerDisconnected)
	_createServer()
	RoundManagerStoreTest()


func RoundManagerStoreTest():
	var roundmanagerinstance = MultiplayerRoundManager.new()
	roundmanagerstore.append(roundmanagerinstance)
	print(roundmanagerstore)

func _createServer():
	var multiplayerPeer = ENetMultiplayerPeer.new()
	var error = multiplayerPeer.create_server(2244, 1000)
	multiplayerRoundManager = MultiplayerRoundManager.new()
	multiplayerRoundManager.name = "multiplayer round manager"
	add_child(multiplayerRoundManager)
	
	if error:
		return error
	multiplayer.multiplayer_peer = multiplayerPeer
	print("CREATED SERVER")

func _removeMultiplayerPeer():
	multiplayer.multiplayer_peer = null

func _playerLoaded():
	if multiplayer.is_server():
		playersLoaded += 1

func _onPlayerConnected(id):
	registerPlayer.rpc_id(id, playerInfo)

@rpc("any_peer", "reliable")
func registerPlayer(newPlayerInfo):
	var newPlayerId = multiplayer.get_remote_sender_id()
	players[newPlayerId] = newPlayerInfo
	playerConnected.emit(newPlayerId, newPlayerInfo)
	print("Player %s connected" % newPlayerId)
	_playerLoaded()

func _onPlayerDisconnected(id):
	players.erase(id)
	playerDisconnected.emit(id)
	print("someone disconnected")

func _onPlayerConnectedOk():
	var peerId = multiplayer.get_unique_id()
	players[peerId] = playerInfo
	playerConnected.emit(peerId, playerInfo)

func _onConnectionFail():
	multiplayer.multiplayer_peer = null

func _onServerDisconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	serverDisconnected.emit()
	
#@rpc("any_peer", "reliable")
#func create_lobby(max_players, turn_type, lobby_type):
	#var lobby_id = generate_ID(lobbyIdChars, 20)
	#var lobby_join_code = generate_ID(joinCodeChars, 5)
	#var lobby_info = {"host" : multiplayer.get_remote_sender_id(), "players" : [multiplayer.get_remote_sender_id()], "max players" : max_players, "turn type": turn_type, "lobby_type" : lobby_type, "join_code" : lobby_join_code}
	#if lobby_type == "public":
		#publicLobbies[lobby_id] = lobby_info
	#else:
		#privateLobbies[lobby_id] = lobby_info
	#print("CREATED NEW %s LOBBY %s:\n\t%s" % [lobby_info["lobby_type"],lobby_id, lobby_info])
	#receive_lobby_id.rpc(lobby_id)
	
func generate_ID(chars, length):
	var word: String
	var n_char = len(chars)
	for i in range(length):
		word += chars[randi()% n_char]
	return word
	
#@rpc("any_peer")
#func closeLobby(id):
	#var authenticatedUsername = await verifyUserId(multiplayer.get_remote_sender_id())
	#if !authenticatedUsername:
		#return false
	#publicLobbies.erase(id)
	#privateLobbies.erase(id)
	#print("%s CLOSED LOBBY %s" % [authenticatedUsername,id])

@rpc("any_peer", "reliable")
func createNewMultiplayerUser(username : String):
	username = username.to_lower()
	var signatureAndKey = AuthManager._generateUserCredentials()
	var success = AuthManager._InsertNewUser(username, signatureAndKey[0])
	if success:
		receiveUserKey.rpc_id(multiplayer.get_remote_sender_id(), signatureAndKey[1])
		receiveUserCreationStatus.rpc_id(multiplayer.get_remote_sender_id(), true, username)
		#AuthManager._loginToUserAccount(username)
		#notifySuccessfulLogin.rpc_id(multiplayer.get_remote_sender_id())
	else:
		receiveUserCreationStatus.rpc(false)

@rpc("any_peer")
func verifyUserCreds(username : String, key):
	username = username.to_lower()
	var signature = AuthManager._getUserSignature(username)
	if !signature:
		terminateSession(multiplayer.get_remote_sender_id(), "nonexistentUser")
		return false
	var credsAreCorrect = AuthManager._verifyUserSignature(signature, key)
	if !credsAreCorrect:
		terminateSession(multiplayer.get_remote_sender_id(), "incorrectCreds")
		return false
	AuthManager._loginToUserAccount(username)
	notifySuccessfulLogin.rpc_id(multiplayer.get_remote_sender_id())

func verifyUserId(id : int):
	requestSenderUsername.rpc_id(id)
	var username = await providedUsername
	var usernameInDatabase = AuthManager.loggedInPlayerIds.keys()[AuthManager.loggedInPlayerIds.values().find(id)]
	if usernameInDatabase == username:
		return username
	return false

func terminateSession(id, reason : String):
	closeSession.rpc_id(id, reason)

@rpc("any_peer") func receiveSenderUsername(username): 
	username = username.to_lower()
	providedUsername.emit(username)

@rpc("any_peer")
func requestPlayerList():
	receivePlayerList.rpc_id(multiplayer.get_remote_sender_id(), AuthManager.loggedInPlayerIds)
	
@rpc("any_peer")
func inviteUser(receiverID, senderUsername):
	var receiverUsername = AuthManager.loggedInPlayerIds.keys()[AuthManager.loggedInPlayerIds.values().find(receiverID)]
	print("%s sent an invite to %s with id %s" % [senderUsername, receiverUsername, receiverID])
	receiveInvite.rpc_id(receiverID, senderUsername, multiplayer.get_remote_sender_id())

# GHOST FUNCTIONS
@rpc("any_peer") func closeSession(reason): pass
#@rpc("any_peer") func receiveLobbyList(): pass
#@rpc("any_peer") func receive_lobby_id(): pass
@rpc("any_peer") func receiveUserCreationStatus(return_value: bool, username): pass
@rpc("authority") func notifySuccessfulLogin(): pass
@rpc("any_peer") func requestSenderUsername(): pass
@rpc("authority") func receiveUserKey(keyString): pass 
@rpc("authority") func receivePlayerList(dict): pass
@rpc("authority") func receiveInvite(from, id): pass

# DEBUG INPUTS
func _input(ev):
	if Input.is_key_pressed(KEY_L):
		print(str(AuthManager.loggedInPlayerIds))
