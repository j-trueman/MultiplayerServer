class_name MRM extends Node

const itemAmounts = {
	"handsaw": [8, 3],
	"magnifying glass": [8, 3],
	"beer": [8, 2],
	"cigarettes": [2, 1],
	"handcuffs": [8, 1],
	"expired medicine": [0, 0],	#1 - DISABLED FOR NOW
	"burner phone": [0, 1],
	"adrenaline": [0, 0],	#2 - DISABLED FOR NOW
	"inverter": [0, 2]
}
const minShells = 2
const maxShells = 8
const percentageShells = 0.5
const percentageMedicine = 0.5
const minHealth = 4
const maxHealth = 6
const minItems = 2
const maxItems = 5
const adrenalineTimeout = 7.0

var players = []
var scores
var currentPlayerTurn
var roundIdx
var loadIdx
var shellArray
var totalShells
var liveCount
var health
var healthPlayers
var numItems
var actionReady
var actionReady_first
var itemsOnTable
var itemsOnTable_ready
var itemsForPlayers
var itemAmounts_available
var isSawed
var isHandcuffed
var isStealing = false
var stealGrace = false
var mode
var mainTimer = 0.0
var stealTimer = 0.0

var matches_num = 1

#func _process(delta):
#	if (isStealing):
#		stealTimer += get_process_delta_time()
#		if stealTimer >= adrenalineTimeout + 5.0:
#			if not stealGrace: sendTimeoutAdrenaline.rpc()
#			stealGrace = true
#			if stealTimer >= adrenalineTimeout + 5.5:
#				isStealing = false
#				stealGrace = false
#				stealTimer = 0.0

func getMatch(id, idx : Array):
	var found = false
	for child in get_children():
		var i = 0
		for player in child.players:
			if player.keys()[0] == id:
				idx[0] = i
				return child
			else:
				i += 1
	return null

func createMatch(players_forMatch):
	var mrm = MRM.new()
	mrm.name = "Match " + str(matches_num)
	mrm.players = players_forMatch
	add_child(mrm)
	mrm.beginMatch()
	matches_num += 1

@rpc("any_peer")
func receivePlayerInfo():
	var mrm = getMatch(multiplayer.get_remote_sender_id(), [0])
	sendPlayerInfo.rpc_id(multiplayer.get_remote_sender_id(), mrm.players)

@rpc("any_peer")
func sendPlayerInfo(players): pass

func beginMatch():
	players.shuffle()
	scores = [0,0]
	roundIdx = 0
	mode = 1
	actionReady = 0
	itemsOnTable_ready = 0
	beginRound()

func beginRound():
	itemsOnTable = [["","","","","","","",""],
					["","","","","","","",""]]
	loadIdx = 0
	
	match roundIdx:
		0: currentPlayerTurn = 0
		1: currentPlayerTurn = 1
		2: currentPlayerTurn = randi_range(0,1)
	
	health = randi_range(minHealth, maxHealth)
	healthPlayers = [health, health]
	beginLoad()

func beginLoad():
	shellArray = []
	isHandcuffed = [0, 0]
	
	totalShells = randi_range(minShells, maxShells)
	liveCount = floori(float(totalShells) * percentageShells)
	for i in range(0, totalShells):
		if i < liveCount:
			shellArray.append(1)
		else:
			shellArray.append(0)
	shellArray.shuffle()
	pickItems()

func pickItems():
	itemsForPlayers = [[],[]]
	itemAmounts_available = [itemAmounts.duplicate(), itemAmounts.duplicate()]
	numItems = randi_range(minItems, maxItems)
	for i in range(0,2):
		var num_itemsOnTable = 0
		for item_onTable in itemsOnTable[i]:
			if item_onTable != "":
				num_itemsOnTable += 1
				var newAmt = itemAmounts_available[i][item_onTable]
				newAmt = [newAmt[0], newAmt[1] - 1] if bool(mode) else [newAmt[0] - 1, newAmt[1]]
				itemAmounts_available[i][item_onTable] = newAmt
		for j in range(0,min(numItems, 8-num_itemsOnTable)):
			var availableItemArray = []
			for item_available in itemAmounts_available[i]:
				if itemAmounts_available[i][item_available][mode] > 0:
					availableItemArray.append(item_available)
			var item_forPlayer = availableItemArray.pick_random()
			itemsForPlayers[i].append(item_forPlayer)
			var newAmt = itemAmounts_available[i][item_forPlayer]
			newAmt = [newAmt[0], newAmt[1] - 1] if bool(mode) else [newAmt[0] - 1, newAmt[1]]
			itemAmounts_available[i][item_forPlayer] = newAmt
	get_parent().sendItems.rpc(itemsForPlayers)

@rpc("any_peer")
func receiveLoadInfo():
	print("ReceiveLoadInfo")
	var mrm = getMatch(multiplayer.get_remote_sender_id(), [0])
	print("SendLoadInfo: " + str(mrm.roundIdx) + ", " + str(mrm.loadIdx) + ", " + str(mrm.currentPlayerTurn) \
		+ ", " + str(mrm.healthPlayers) + ", " + str(mrm.totalShells) + ", " + str(mrm.liveCount))
	sendLoadInfo.rpc_id(multiplayer.get_remote_sender_id(), mrm.roundIdx, mrm.loadIdx, mrm.currentPlayerTurn, \
		mrm.healthPlayers, mrm.totalShells, mrm.liveCount)

@rpc("any_peer")
func sendLoadInfo(currentPlayerTurn, healthPlayers, totalShells, liveCount): pass

@rpc("any_peer")
func receiveItems():
	print("ReceiveItems")
	var mrm = getMatch(multiplayer.get_remote_sender_id(), [0])
	print("SendItems: " + str(mrm.itemsForPlayers))
	sendItems.rpc_id(multiplayer.get_remote_sender_id(), mrm.itemsForPlayers)

@rpc("any_peer")
func sendItems(itemsForPlayers): pass

@rpc("any_peer")
func receiveItemsOnTable(itemTableIdxArray):
	print("ReceiveItemsOnTable: " + str(itemTableIdxArray))
	var idxArray = [0]
	var mrm = getMatch(multiplayer.get_remote_sender_id(), idxArray)
	var playerIdx = idxArray.pop_front()
	if itemTableIdxArray.size() == mrm.itemsForPlayers[playerIdx].size():
		for idx in itemTableIdxArray:
			if mrm.itemsOnTable[playerIdx][idx].is_empty():
				mrm.itemsOnTable[playerIdx][idx] = mrm.itemsForPlayers[playerIdx][0]
				mrm.itemsForPlayers[playerIdx].remove_at(0)
	mrm.itemsOnTable_ready += 1
	if mrm.itemsOnTable_ready > 1:
		for player in mrm.players:
			print("SendItemsOnTable: " + str(mrm.itemsOnTable))
			sendItemsOnTable.rpc_id(player.keys()[0], mrm.itemsOnTable)
		mrm.itemsOnTable_ready = 0

@rpc("any_peer")
func sendItemsOnTable(itemsOnTable): pass

@rpc("any_peer")
func receiveActionValidation(action):
	print("ReceiveActionValidation: " + action)
	var action_temp = action
	var result = null
	var idxArray = [0]
	var mrm = getMatch(multiplayer.get_remote_sender_id(), idxArray)
	var playerIdx = idxArray.pop_front()
	var opponentIdx = int(not playerIdx)
	var validActions
	if mrm.isStealing:
		validActions = mrm.itemsOnTable[opponentIdx].duplicate()
		validActions.erase("adrenaline")
	else:
		validActions = mrm.itemsOnTable[playerIdx].duplicate()
		validActions.append_array(["pickup shotgun", "shoot self", "shoot opponent"])
	while validActions.has(""):
		validActions.erase("")
	if mrm.isSawed: validActions.erase("handsaw")
	if mrm.isHandcuffed[opponentIdx]: validActions.erase("handcuffs")
	if action.length() == 1:
		action = mrm.itemsOnTable[playerIdx][int(action)]
	if playerIdx != mrm.currentPlayerTurn or validActions.find(action) < 0:
		action = "invalid"
	else: match action:
		"pickup shotgun": pass
		"shoot self":
			var shell = mrm.shellArray.pop_front()
			result = shell
			if shell == 1:
				var damage = 2 if mrm.isSawed else 1
				mrm.healthPlayers[playerIdx] -= damage
			if (shell == 1 and mrm.isHandcuffed[opponentIdx] != 2) \
				or mrm.shellArray.is_empty():
					mrm.currentPlayerTurn = int(not playerIdx)
			if mrm.isHandcuffed[opponentIdx] > 0:
				mrm.isHandcuffed[opponentIdx] -= 1
			mrm.isSawed = false
		"shoot opponent":
			var shell = mrm.shellArray.pop_front()
			result = shell
			if shell == 1:
				var damage = 2 if mrm.isSawed else 1
				mrm.healthPlayers[opponentIdx] -= damage
			if mrm.isHandcuffed[opponentIdx] != 2:
				mrm.currentPlayerTurn = int(not playerIdx)
			if mrm.isHandcuffed[opponentIdx] > 0:
				mrm.isHandcuffed[opponentIdx] -= 1
			mrm.isSawed = false
		"handsaw":
			mrm.doItem(action_temp, playerIdx)
			mrm.isSawed = true
		"magnifying glass":
			mrm.doItem(action_temp, playerIdx)
			result = mrm.shellArray.front()
		"beer":
			mrm.doItem(action_temp, playerIdx)
			result = mrm.shellArray.pop_front()
			if mrm.shellArray.is_empty():
				mrm.currentPlayerTurn = int(not playerIdx)
		"cigarettes":
			mrm.doItem(action_temp, playerIdx)
			mrm.healthPlayers[playerIdx] = min(mrm.health, mrm.healthPlayers[playerIdx] + 1)
			result = mrm.healthPlayers[playerIdx]
		"handcuffs":
			mrm.doItem(action_temp, playerIdx)
			mrm.isHandcuffed[opponentIdx] = 2
		"expired medicine":
			mrm.doItem(action_temp, playerIdx)
			result = randf_range(0.0, 1.0) < mrm.percentageMedicine
			if result: mrm.healthPlayers[playerIdx] -= 1
			else: mrm.healthPlayers[playerIdx] += 2
		"burner phone":
			mrm.doItem(action_temp, playerIdx)
			var rand = randi_range(1,mrm.shellArray.size()-1)
			if rand == 7: rand -= 1
			result = rand if mrm.shellArray[rand] else -rand
		"adrenaline":
			mrm.doItem(action_temp, playerIdx)
			mrm.isStealing = true
		"inverter":
			mrm.doItem(action_temp, playerIdx)
			mrm.shellArray[0] = int(not mrm.shellArray[0])
	print("SendActionValidation: " + action_temp + ", " + str(result))
	for player in mrm.players:
		sendActionValidation.rpc_id(player.keys()[0], action_temp, result)
	var roundOver = false
	var winner
	for i in range(2):
		if mrm.healthPlayers[i] < 1:
			winner = int(not i)
			roundOver = true
			break
	if roundOver:
		mrm.scores[winner] += 1
		mrm.roundIdx += 1
		if mrm.scores.max() > 1 or mrm.roundIdx > 2:
			pass	# ending stuff
		else:
			mrm.beginRound()
	elif (mrm.shellArray.is_empty()):
		mrm.loadIdx += 1
		mrm.beginLoad()

func doItem(action_temp, playerIdx):
	if isStealing:
		playerIdx = int(not playerIdx)
		isStealing = false
		stealGrace = false
		stealTimer = 0.0
	var action = itemsOnTable[playerIdx][int(action_temp)]
	itemsOnTable[playerIdx][int(action_temp)] = ""
	var newAmt = itemAmounts_available[playerIdx][action]
	newAmt = [newAmt[0], newAmt[1] + 1] if bool(mode) else [newAmt[0] + 1, newAmt[1]]
	itemAmounts_available[playerIdx][action] = newAmt

@rpc("any_peer")
func sendActionValidation(action, result): pass

@rpc("any_peer")
func sendTimeoutAdrenaline(): pass

@rpc("any_peer")
func receiveActionReady():
	var idxArray = [0]
	var mrm = getMatch(multiplayer.get_remote_sender_id(), idxArray)
	var playerIdx = idxArray.pop_front()
	print("ReceiveActionReady from " + mrm.players[playerIdx].values()[0])
	if mrm.actionReady_first != multiplayer.get_remote_sender_id():
		mrm.actionReady += 1
		mrm.actionReady_first = multiplayer.get_remote_sender_id()
	if mrm.actionReady > 1:
		for player in mrm.players:
			sendActionReady.rpc_id(player.keys()[0])
		print("SendActionReady")
		mrm.actionReady = 0
		mrm.actionReady_first = 0

@rpc("any_peer")
func sendActionReady(): pass
