class_name InviteManager extends Node

@export var activeInvites : Array

signal newInvite(from, to)

class Invite:
	var inviteTo : int
	var inviteFrom : int
	var activeInvites : Array
	
	func _init(from, to):
		self.inviteFrom = from
		self.inviteTo = to
		self.send()
	
	func send():
		var username = AuthManager.loggedInPlayerIds.find_key(inviteFrom)
		MultiplayerManager.receiveInvite.rpc_id(inviteTo, username, inviteFrom)
	
	func accept():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteFrom, "accept")
		
	func deny():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteFrom, "deny")
		
	func cancel():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteTo, "cancel")
	
func getInboundInvites(to):
	var invitesForPlayer = []
	for invite in activeInvites:
		if invite.inviteTo == to:
			invitesForPlayer.append(invite.inviteFrom)
	return invitesForPlayer
	
func getOutBoundInvites(from):
	var invitesFromPlayer = []
	for invite in activeInvites:
		if invite.inviteFrom == from:
			invitesFromPlayer.append(invite.inviteTo)
	return invitesFromPlayer

func acceptInvite(from, to):
	for invite in activeInvites:
		if invite.inviteFrom == from && invite.inviteTo == to:
			invite.accept()
			activeInvites.remove_at(activeInvites.find(invite))
			return true
	return false

func denyInvite(from, to):
	for invite in activeInvites:
		if invite.inviteFrom == from:
			invite.deny()
			activeInvites.remove_at(activeInvites.find(invite))
			return true
	return false

func retractInvite(from, to):
	for invite in activeInvites:
		if invite.inviteFrom == from && invite.inviteTo == to:
			invite.cancel()
			activeInvites.remove_at(activeInvites.find(invite))
			return true
	return false

func retractAllInvites(from):
	for invite in activeInvites:
		if invite.inviteFrom == from:
			invite.cancel()
			activeInvites.remove_at(activeInvites.find(invite))
