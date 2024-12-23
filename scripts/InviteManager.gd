class_name InviteManager extends Node

@export var activeInvites : Array

signal newInvite(from, to)

class Invite:
	var inviteTo : int
	var inviteFrom : int
	var activeInvites : Array
	var inviteFromUsername
	var inviteToUsername
	
	func _init(from, to):
		self.inviteFrom = from
		self.inviteTo = to
		self.inviteToUsername = AuthManager.loggedInPlayers[inviteTo].username
		self.inviteFromUsername = AuthManager.loggedInPlayers[inviteFrom].username
		self.send()
	
	func send():
		MultiplayerManager.receiveInvite.rpc_id(inviteTo, inviteFromUsername, inviteFrom)
	
	func accept():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteFrom, inviteToUsername, "accept")
		var toMatch = MultiplayerManager.mrm.getMatch(inviteTo)
		if toMatch:
			if toMatch.dealer:
				MultiplayerManager.mrm.eraseMatch(toMatch)
		MultiplayerManager.mrm.createMatch([inviteFrom, inviteTo])
		
	func deny():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteFrom, inviteToUsername, "deny")
		
	func cancel():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteTo, inviteFromUsername, "cancel")
		
	func busy():
		MultiplayerManager.receiveInviteStatus.rpc_id(inviteFrom, inviteToUsername, "busy")
	
func getInboundInvites(to):
	var invitesForPlayer = []
	for invite in activeInvites:
		if invite.inviteTo == to:
			invitesForPlayer.append({invite.inviteFromUsername:"username",invite.inviteFrom:"id"})
	return invitesForPlayer
	
func getOutboundInvites(from):
	var invitesFromPlayer = []
	for invite in activeInvites:
		if invite.inviteFrom == from:
			invitesFromPlayer.append({invite.inviteToUsername:"username",invite.inviteTo:"id"})
	return invitesFromPlayer

func acceptInvite(from, to):
	for invite in activeInvites:
		if invite.inviteFrom == from && invite.inviteTo == to:
			invite.accept()
			activeInvites.erase(invite)
			retractAllInvites(from)
			for inboundInvite in activeInvites:
				if (inboundInvite.inviteTo == from) or (inboundInvite.inviteTo == to):
					inboundInvite.busy()
					activeInvites.erase(inboundInvite)
			return true
	return false

func denyInvite(from):
	for invite in activeInvites:
		if invite.inviteFrom == from:
			invite.deny()
			activeInvites.erase(invite)
			return true
	return false

func retractInvite(from, to):
	for invite in activeInvites:
		if invite.inviteFrom == from && invite.inviteTo == to:
			invite.cancel()
			activeInvites.erase(invite)
			return true
	return false

func retractAllInvites(from, dual = false):
	for invite in activeInvites:
		if invite.inviteFrom == from or (dual and invite.inviteTo == from):
			if AuthManager.loggedInPlayers.has(invite.inviteTo):
				invite.cancel()
			activeInvites.erase(invite)
