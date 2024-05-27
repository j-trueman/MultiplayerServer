extends Node

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
	var error = multiplayerPeer.create_server(2244, 1000)
	if error:
		return error
	multiplayer.multiplayer_peer = multiplayerPeer
	print("CREATED SERVER")

func terminateSession(id, reason : String):
	closeSession.rpc_id(id, reason)

@rpc("any_peer", "reliable")
func requestNewUser(username : String):
	var key = AuthManager._CreateNewUser(username)
	if !key:
		terminateSession(multiplayer.get_remote_sender_id(), "userExists")
	receivePrivateKey.rpc_id(multiplayer.get_remote_sender_id(), key)

@rpc("any_peer")
func verifyUserCreds(keyFileData : PackedByteArray):
	var keyFileDataString = keyFileData.get_string_from_utf8().split(":")
	var keyData = keyFileDataString[0]
	var username = keyFileDataString[1]
	var verified = AuthManager._verifyKeyFile(username, keyData)
	if !verified:
		return false
	AuthManager._loginToUserAccount(username)

@rpc("any_peer")
func requestPlayerList():
	var list = AuthManager.loggedInPlayerIds.duplicate()
	list.erase(list.find_key(multiplayer.get_remote_sender_id()))
	receivePlayerList.rpc_id(multiplayer.get_remote_sender_id(), list)
	
@rpc("any_peer")
func requestUserExistsStatus(username : String):
	print("requesting status of " + username)
	if len(AuthManager._checkUserExists(username.to_lower())) > 0:
		terminateSession(multiplayer.get_remote_sender_id(), "userExists")
		return false
	terminateSession(multiplayer.get_remote_sender_id(), "nonexistentUser")

@rpc("any_peer")
func createInvite(to):
	var invite = inviteManager.Invite.new(multiplayer.get_remote_sender_id(), to)
	inviteManager.activeInvites.append(invite)
	
@rpc("any_peer")
func acceptInvite(from):
	if !inviteManager.acceptInvite(from, multiplayer.get_remote_sender_id()):
		print("This user does not have an invite from %s" % from)

@rpc("any_peer")
func denyInvite(from):
	if !inviteManager.denyInvite(from, multiplayer.get_remote_sender_id()):
		print("This user does not have an invite from %s" % from)
		
@rpc("any_peer") 
func retractInvite(to): 
	inviteManager.retractInvite(multiplayer.get_remote_sender_id(), to)
	
@rpc("any_peer") 
func rectractAllInvites(): 
	inviteManager.retractAllInvites(multiplayer.get_remote_sender_id())
	
# GHOST FUNCTIONS
@rpc("any_peer") func closeSession(reason): pass
@rpc("any_peer") func receiveUserCreationStatus(return_value: bool, username): pass
@rpc("authority") func notifySuccessfulLogin(username : String): pass
@rpc("authority") func receivePrivateKey(keyString): pass 
@rpc("authority") func receivePlayerList(dict): pass
@rpc("authority") func receiveInvite(from, id): pass
@rpc("authority") func receiveInviteStatus(status): pass
