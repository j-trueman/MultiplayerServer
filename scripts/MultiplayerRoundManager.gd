extends Node

const itemAmounts = {
	"handsaw": [8, 3],
	"magnifying glass": [8, 3],
	"beer": [8, 2],
	"cigarettes": [2, 1],
	"handcuffs": [8, 1],
	"expired medicine": [0, 1],
	"burner phone": [0, 1],
	"adrenaline": [0, 2],
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

var players
var scores
var currentPlayerTurn
var matchStarter
var roundIdx
var shellArray
var health
var healthPlayers
var numItems
var itemsOnTable
var itemsForPlayers
var itemAmounts_available
var isSawed
var isHandcuffed
var isStealing = false
var stealGrace = false
var mode
var mainTimer = 0.0
var stealTimer = 0.0

func _process(delta):
	if (isStealing):
		stealTimer += get_process_delta_time()
		if stealTimer >= adrenalineTimeout + 5.0:
			if not stealGrace: sendTimeoutAdrenaline.rpc()
			stealGrace = true
			if stealTimer >= adrenalineTimeout + 5.5:
				isStealing = false
				stealGrace = false
				stealTimer = 0.0

func beginMatch():
	scores = []
	matchStarter = randi_range(0,1)
	roundIdx = 0
	mode = 1
	beginRound()

func beginRound():
	itemsOnTable = [[],[]]
	itemAmounts_available = [itemAmounts, itemAmounts]
	
	match roundIdx:
		0: currentPlayerTurn = matchStarter
		1: currentPlayerTurn = int(not matchStarter)
		2: currentPlayerTurn = randi_range(0,1)
	
	health = randi_range(minHealth, maxHealth)
	healthPlayers = [health, health]
	beginLoad()

func beginLoad():
	shellArray = []
	isHandcuffed = [0, 0]
	
	var totalShells = randi_range(minShells, maxShells)
	var liveCount = floori(float(totalShells) * percentageShells)
	for i in range(0, totalShells):
		if i < liveCount:
			shellArray.append(1)
		else:
			shellArray.append(0)
	shellArray.shuffle()
	sendLoadInfo.rpc(currentPlayerTurn, healthPlayers, totalShells, liveCount)	
	pickItems()

func pickItems():
	itemsForPlayers = [[],[]]
	numItems = randi_range(minItems, maxItems)
	for i in range(0,1):
		for item_onTable in itemsOnTable[i]:
			itemAmounts_available[i][item_onTable][mode] -= 1
		for j in range(0,min(numItems, 8-itemsOnTable[i].size())):
			var availableItemArray
			for item_available in itemAmounts_available[i]:
				if itemAmounts_available[item_available][mode] > 0:
					availableItemArray.append(item_available)
			var item_forPlayer = availableItemArray.pick_random()
			itemsForPlayers[i].append(item_forPlayer)
			itemsOnTable[i].append(item_forPlayer)
	sendItems.rpc(itemsForPlayers)

@rpc("any_peer")
func sendLoadInfo(currentPlayerTurn, healthPlayers, totalShells, liveCount): pass

@rpc("any_peer")
func sendItems(itemsForPlayers): pass

@rpc("any_peer")
func recieveActionValidation(action):
	var result = null
	var playerIdx = players.find(multiplayer.get_remote_sender_id())
	var opponentIdx = int(not playerIdx)
	var validActions
	if isStealing:
		validActions = itemsOnTable[opponentIdx].duplicate()
		validActions.erase("adrenaline")
	else:
		validActions = itemsOnTable[playerIdx].duplicate()
		validActions.append_array(["shoot self", "shoot opponent"])
	if isSawed: validActions.erase("handsaw")
	if isHandcuffed[opponentIdx]: validActions.erase("handcuffs")
	if playerIdx != currentPlayerTurn or validActions.find(action) < 0:
		action = "invalid"
	else: match action:
		"shoot self":
			var shell = shellArray.pop_front()
			result = shell
			if shell == 1:
				var damage = 2 if isSawed else 1
				health[playerIdx] -= damage
			if (shell == 1 and isHandcuffed[opponentIdx] != 2) \
				or shellArray.is_empty():
					currentPlayerTurn = int(not playerIdx)
			if isHandcuffed[opponentIdx] > 0:
				isHandcuffed[opponentIdx] -= 1
			isSawed = false
		"shoot opponent":
			var shell = shellArray.pop_front()
			result = shell
			if shell == 1:
				var damage = 2 if isSawed else 1
				health[opponentIdx] -= damage
			if isHandcuffed[opponentIdx] != 2:
				currentPlayerTurn = int(not playerIdx)
			if isHandcuffed[opponentIdx] > 0:
				isHandcuffed[opponentIdx] -= 1
			isSawed = false
		"handsaw":
			doItem(action, playerIdx)
			isSawed = true
		"magnifying glass":
			doItem(action, playerIdx)
			result = shellArray.front()
		"beer":
			doItem(action, playerIdx)
			result = shellArray.pop_front()
			if shellArray.is_empty():
				currentPlayerTurn = int(not playerIdx)
		"cigarettes":
			doItem(action, playerIdx)
			healthPlayers[playerIdx] = min(health, healthPlayers[playerIdx] + 1)
			result = healthPlayers[playerIdx]
		"handcuffs":
			doItem(action, playerIdx)
			isHandcuffed[opponentIdx] = 2
		"expired medicine":
			doItem(action, playerIdx)
			result = randf_range(0.0, 1.0) < percentageMedicine
			if result: health[playerIdx] -= 1
			else: health[playerIdx] += 2
		"burner phone":
			doItem(action, playerIdx)
			var rand = randi_range(1,shellArray.size()-1)
			result = rand if shellArray[rand] else -rand
		"adrenaline":
			doItem(action, playerIdx)
			isStealing = true
		"inverter":
			doItem(action, playerIdx)
			shellArray[0] = int(not shellArray[0])
	sendActionValidation.rpc(action, result)
	var roundOver = false
	var winner
	for i in range(0,2):
		if healthPlayers[i] < 1:
			winner = int(not i)
			roundOver = true
			break
	if roundOver:
		scores[winner] += 1
		roundIdx += 1
		if scores.max() > 1 or roundIdx > 2:
			pass	# ending stuff
		else:
			beginRound()
	elif (shellArray.is_empty()):
		beginLoad()

func doItem(action, playerIdx):
	if isStealing:
		playerIdx = int(not playerIdx)
		isStealing = false
	itemsOnTable[playerIdx].erase(action)
	itemAmounts_available[playerIdx][action][mode] += 1

@rpc("any_peer")
func sendActionValidation(action, result): pass

@rpc("any_peer")
func sendTimeoutAdrenaline(): pass
