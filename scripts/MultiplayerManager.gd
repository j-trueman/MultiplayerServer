extends Node

var version = "0.2.2"

const MultiplayerRoundManager = preload("res://scripts/MultiplayerRoundManager.gd")
const InviteManager = preload("res://scripts/InviteManager.gd")
var multiplayerRoundManager
var inviteManager

func _ready():
	multiplayer.server_relay = false
	
	multiplayerRoundManager = MultiplayerRoundManager.new()
	multiplayerRoundManager.name = "MultiplayerRoundManager"
	add_child(multiplayerRoundManager)
	
	inviteManager = InviteManager.new()
	inviteManager.name = "InviteManager"
	add_child(inviteManager)
	
	_createServer()

func _createServer():
	var multiplayerPeer = ENetMultiplayerPeer.new()
	var error = multiplayerPeer.create_server(2095, 1000)
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
	var key = AuthManager._CreateNewUser(username)
	if typeof(key) != TYPE_STRING:
		match key:
			-1:
				terminateSession(multiplayer.get_remote_sender_id(), "invalidUsername")
				return
			-2:
				terminateSession(multiplayer.get_remote_sender_id(), "userAlreadyExists")
				return
			-3:
				terminateSession(multiplayer.get_remote_sender_id(), "databaseError")
				return
	receivePrivateKey.rpc_id(multiplayer.get_remote_sender_id(), key)

@rpc("any_peer", "reliable")
func verifyUserCreds(keyFileData : PackedByteArray, client_version : String):
	if client_version != version:
		terminateSession(multiplayer.get_remote_sender_id(), "outdatedClient")
		return
	var keyFileDataString = keyFileData.get_string_from_utf8().split(":")
	if len(keyFileDataString) != 2:
		terminateSession(multiplayer.get_remote_sender_id(), "malformedKey")
		return
	var keyData = keyFileDataString[0]
	var username = keyFileDataString[1]
	var verified = AuthManager._verifyKeyFile(username, keyData)
	if verified != 0:
		match verified:
			-1:
				terminateSession(multiplayer.get_remote_sender_id(), "nonExistentUser")
				return
			-2:
				terminateSession(multiplayer.get_remote_sender_id(), "invalidCreds")
				return
	AuthManager._loginToUserAccount(username)

@rpc("any_peer", "reliable")
func requestPlayerList():
	receivePlayerList.rpc_id(multiplayer.get_remote_sender_id(), AuthManager.loggedInPlayerIds)
	
#@rpc("any_peer", "reliable")
#func requestUserExistsStatus(username : String):
	#print("requesting status of " + username)
	#if len(AuthManager._checkUserExists(username.to_lower())) > 0:
		#terminateSession(multiplayer.get_remote_sender_id(), "userExists")
		#return false
	#terminateSession(multiplayer.get_remote_sender_id(), "nonexistentUser")

@rpc("any_peer", "reliable")
func createInvite(to):
	if not multiplayerRoundManager.getMatch(to):
		var invite = inviteManager.Invite.new(multiplayer.get_remote_sender_id(), to)
		inviteManager.activeInvites.append(invite)
	
@rpc("any_peer", "reliable")
func acceptInvite(from):
	if !inviteManager.acceptInvite(from, multiplayer.get_remote_sender_id()):
		print("This user does not have an invite from %s" % from)

@rpc("any_peer", "reliable")
func denyInvite(from):
	if !inviteManager.denyInvite(from, multiplayer.get_remote_sender_id()):
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
	var id = multiplayer.get_remote_sender_id()
	var mrm = multiplayerRoundManager.getMatch(id)
	if mrm:
		var receiver = mrm.players.duplicate()
		receiver.erase(id)
		receiveChat.rpc_id(receiver.front(), message.substr(0,200))

# GHOST FUNCTIONS
@rpc("any_peer", "reliable") func closeSession(reason): pass
@rpc("any_peer", "reliable") func receiveUserCreationStatus(return_value: bool, username): pass
@rpc("any_peer", "reliable") func notifySuccessfulLogin(username : String): pass
@rpc("any_peer", "reliable") func receivePrivateKey(keyString): pass 
@rpc("any_peer", "reliable") func receivePlayerList(dict): pass
@rpc("any_peer", "reliable") func receiveInvite(from, id): pass
@rpc("any_peer", "reliable") func receiveInviteStatus(username, status): pass
@rpc("any_peer", "reliable") func receiveInviteList(list): pass
@rpc("any_peer", "reliable") func opponentDisconnect(): pass
@rpc("any_peer", "reliable") func receiveChat(message): pass
