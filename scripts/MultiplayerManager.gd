extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

const PORT = 2244
const DEFAULT_SERVER_IP = "localhost"
const MAX_CONNECTIONS = 1000

var players = {}
var public_lobbies = {}
var private_lobbies = {}

var player_info = {"name": "Name"}
var characters = 'qwertyuiopasdfgjklzxcvbnm123456789QWERTYUIOPASDFGJKLZXCVBNMM'
var join_code_chars = 'qwertyuiopasdfghjklzxcvbnm'
var players_loaded = 0

var loggedInPlayerIds = {}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	create_game()

func create_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CONNECTIONS)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	print("CREATED SERVER")

@rpc("any_peer")
func request_lobby_list():
	recieve_lobby_list.rpc(public_lobbies)

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null

func player_loaded():
	if multiplayer.is_server():
		players_loaded += 1

func _on_player_connected(id):
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)
	print("Player %s connected" % new_player_id)
	player_loaded()

func _on_player_disconnected(id):
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)

func _on_connected_fail():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
	
@rpc("any_peer", "reliable")
func create_lobby(max_players, turn_type, lobby_type):
	var lobby_id = generate_ID(characters, 20)
	var lobby_join_code = generate_ID(join_code_chars, 5)
	var lobby_info = {"host" : multiplayer.get_remote_sender_id(), "players" : [multiplayer.get_remote_sender_id()], "max players" : max_players, "turn type": turn_type, "lobby_type" : lobby_type, "join_code" : lobby_join_code}
	if lobby_type == "public":
		public_lobbies[lobby_id] = lobby_info
	else:
		private_lobbies[lobby_id] = lobby_info
	print("CREATED NEW %s LOBBY %s:\n\t%s" % [lobby_info["lobby_type"],lobby_id, lobby_info])
	recieve_lobby_id.rpc(lobby_id)
	
func generate_ID(chars, length):
	var word: String
	var n_char = len(chars)
	for i in range(length):
		word += chars[randi()% n_char]
	return word
	
@rpc("any_peer")
func close_lobby(id):
	public_lobbies.erase(id)
	private_lobbies.erase(id)
	print("ERASED LOBBY %s" % id)

@rpc("any_peer", "reliable")
func create_new_multiplayer_user(username : String, signature : PackedByteArray):
	var success = AuthManager._InsertNewUser(username, signature)
	if success:
		user_creation_status.rpc(true)
	else:
		user_creation_status.rpc(false)

@rpc("any_peer")
func verifyUserCreds(username : String, key):
	var signature = AuthManager._getUserSignature(username)
	if !signature:
		terminateSession(multiplayer.get_remote_sender_id(), "User does not exist")
		return false
	var credsAreCorrect = AuthManager._verifyUserSignature(signature, key)
	if !credsAreCorrect:
		terminateSession(multiplayer.get_remote_sender_id(), "Incorrect Credentials")
		return false
	AuthManager._loginToUserAccount(username)
	notifySuccessfulLogin.rpc_id(multiplayer.get_remote_sender_id())

func terminateSession(id, reason : String):
	closeSession.rpc_id(id, reason)

# GHOST FUNCTIONS
@rpc("any_peer") func closeSession(reason): pass
@rpc("any_peer") func recieve_lobby_list(): pass
@rpc("any_peer") func recieve_lobby_id(): pass
@rpc("any_peer") func user_creation_status(return_value: bool): pass
@rpc("authority") func notifySuccessfulLogin(): pass

# DEBUG INPUTS
func _input(ev):
	if Input.is_key_pressed(KEY_L):
		print(str(AuthManager.loggedInPlayerIds))
