class_name MRM extends Node

const items = ["magnifying glass","cigarettes","beer","handcuffs","handsaw",
			"expired medicine","inverter","burner phone","adrenaline"]

var settings = {
	"minShells": 2,
	"maxShells": 8,
	"percentageShells": 0.5,
	"percentageMedicine": 0.5,
	"minHealth": 4,
	"maxHealth": 6,
	"minItems": 2,
	"maxItems": 5,
	"adrenalineTimeout": 7.0,
	"timeout": 5
}
var itemAmountsArray = [
	3,
	1,
	2,
	1,
	3,
	0,
	2,
	1,
	0
]
var itemAmounts = {}

var matchID
var players = []
var scores
var currentPlayerTurn
var roundIdx
var loadIdx
var shellArray = []
var totalShells
var liveCount
var health
var healthPlayers
var numItems
var actionReady = 0
var actionReady_first
var itemsOnTable
var itemsOnTable_ready
var itemsForPlayers
var itemAmounts_available
var isSawed
var isHandcuffed
var isStealing
var stealGrace = false
var timerRunning = false
var mainTimer = 0.0
var stealTimer = 0.0
var end = false

var matches_num = 1
var wager = 0

var dealer = false
var dealer_pid = 0
var dealer_action = 0
var dealer_shotgunFlag = false
var dealer_roundIdx = -1
var dealer_loadIdx = -1
var dealer_savedAction = ""
var dealer_knownShells = []
var dealer_ready = false
var dealer_wait = 2
var dealer_end = 0
var dealer_table
var dealer_bruteforceID = 0

var dealerChat_history = []
var dealerChat_busy = false

func _ready():
	var parent = get_parent()
	if parent.name == "MultiplayerRoundManager":
		settings = parent.settings
		itemAmounts = parent.itemAmounts
	else:
		for i in range(items.size()):
			itemAmounts[items[i]] = itemAmountsArray[i]

func _process(delta):
	if dealer_ready:
		if dealer_action > 0 or not dealer_savedAction.is_empty():
			dealer_ready = false
			var action = dealer_action
			dealer_action = 0
			dealer_action_do(action)
	if timerRunning:
		mainTimer += delta
		if mainTimer > settings["timeout"]:
			multiplayer.multiplayer_peer.disconnect_peer(players[currentPlayerTurn])
			timerRunning = false
			timerRunning = 0.0

func getMatch(id):
	if id > 0:
		for child in get_children():
			if child.players.find(id) >= 0:
				return child
	return false

func createMatch(players_forMatch):
	if not (getMatch(players_forMatch.front()) or getMatch(players_forMatch.back())):
		var mrm = MRM.new()
		mrm.matchID = matches_num
		if players_forMatch.has(0):
			mrm.dealer = true
		else:
			for player in players_forMatch:
				AuthManager.loggedInPlayers[player].status = true
		mrm.players = players_forMatch
		add_child(mrm)
		if not players_forMatch.front() > 0:
			mrm.actionReady = 1
			mrm.dealer_bruteforceID = -1
			mrm.wager = 70
			var process = ProjectSettings.globalize_path("res://dealer.exe") \
				if OS.get_name() == "Windows" else "./dealer.x86_64"
			dealer_pid = OS.create_process(process,[])
		matches_num += 1
		mrm.beginMatch()
	
func eraseMatch(mrm : MRM):
	if mrm.dealer_bruteforceID > 0 and multiplayer.get_peers().has(mrm.dealer_bruteforceID):
		multiplayer.multiplayer_peer.disconnect_peer(mrm.dealer_bruteforceID)
	remove_child(mrm)
	mrm.queue_free()

@rpc("any_peer", "reliable")
func receivePlayerInfo():
	print("calling")
	var id = multiplayer.get_remote_sender_id()
	var mrm = getMatch(id)
	if !mrm:
		print("could not find match!")
		return
	sendPlayerInfo.rpc_id(id, mrm.players)

@rpc("any_peer", "reliable")
func sendPlayerInfo(_players): pass

func beginMatch():
	if not dealer:
		players.shuffle()
	scores = [0,0]
	roundIdx = 0
	itemsOnTable_ready = 0
	beginRound()

func beginRound():
	itemsOnTable = [["","","","","","","",""],
					["","","","","","","",""]]
	dealer_table = itemsOnTable.duplicate(true)
	loadIdx = 0
	
	match roundIdx:
		0: currentPlayerTurn = 0
		1: currentPlayerTurn = 1
		2: currentPlayerTurn = 0 if dealer else randi_range(0,1)
	
	health = randi_range(settings["minHealth"], settings["maxHealth"])
	healthPlayers = [health, health]
	beginLoad()

func beginLoad():
	shellArray = []
	isSawed = false
	isHandcuffed = [0, 0]
	isStealing = false
	
	totalShells = max(randi_range(settings["minShells"], settings["maxShells"]),1)
	liveCount = max(floori(float(totalShells) * settings["percentageShells"]),1)
	for i in range(0, totalShells):
		if i < liveCount:
			shellArray.append(1)
		else:
			shellArray.append(0)
	shellArray.shuffle()
	
	if dealer:
		dealer_knownShells.clear()
		for shell in shellArray: dealer_knownShells.append(false)
		dealer_roundIdx = roundIdx
		dealer_loadIdx = loadIdx
		dealer_wait = 3 if (roundIdx == 2 and loadIdx == 0) else 2
	
	pickItems()

func pickItems():
	itemsForPlayers = [[],[]]
	itemAmounts_available = [itemAmounts.duplicate(true), itemAmounts.duplicate(true)]
	numItems = randi_range(settings["minItems"], settings["maxItems"])
	for i in range(2):
		var num_itemsOnTable = 0
		for item_onTable in itemsOnTable[i]:
			if item_onTable != "":
				num_itemsOnTable += 1
				var newAmt = itemAmounts_available[i][item_onTable]
				newAmt -= 1
				itemAmounts_available[i][item_onTable] = newAmt
		for j in range(min(numItems, 8-num_itemsOnTable)):
			if loadIdx == 0 and health <= 4:
					if itemsForPlayers[i].has("handcuffs") \
						and itemsForPlayers[i].has("handsaw"):
						itemAmounts_available[i]["handsaw"] = 0
					elif itemsForPlayers[i].count("handsaw") > 1:
						itemAmounts_available[i]["handcuffs"] = 0
			var availableItemArray = []
			for item_available in itemAmounts_available[i]:
				if itemAmounts_available[i][item_available] > 0:
					availableItemArray.append(item_available)
			var item_forPlayer = availableItemArray.pick_random()
			if item_forPlayer != null:
				itemsForPlayers[i].append(item_forPlayer)
				if dealer: dealer_table[i].append(item_forPlayer)
				var newAmt = itemAmounts_available[i][item_forPlayer]
				newAmt -= 1
				itemAmounts_available[i][item_forPlayer] = newAmt
	for player in players:
		performRPC("items", player, itemsForPlayers)

@rpc("any_peer", "reliable")
func receiveLoadInfo():
	print("ReceiveLoadInfo")
	var id = multiplayer.get_remote_sender_id()
	var mrm = getMatch(id)
	print("SendLoadInfo: " + str(mrm.roundIdx) + ", " + str(mrm.loadIdx) + ", " + str(mrm.currentPlayerTurn) \
		+ ", " + str(mrm.healthPlayers) + ", " + str(mrm.totalShells) + ", " + str(mrm.liveCount))
	sendLoadInfo.rpc_id(id, mrm.roundIdx, mrm.loadIdx, mrm.currentPlayerTurn, \
		mrm.healthPlayers, mrm.totalShells, mrm.liveCount)

@rpc("any_peer", "reliable")
func sendLoadInfo(_currentPlayerTurn, _healthPlayers, _totalShells, _liveCount): pass

@rpc("any_peer", "reliable")
func receiveItems():
	if not end:
		print("ReceiveItems")
		var id = multiplayer.get_remote_sender_id()
		var mrm = getMatch(id)
		print("SendItems: " + str(mrm.itemsForPlayers))
		sendItems.rpc_id(id, mrm.itemsForPlayers)

@rpc("any_peer", "reliable")
func sendItems(_itemsForPlayers): pass

@rpc("any_peer", "reliable")
func receiveItemsOnTable(itemTableIdxArray):
	if not end:
		print("ReceiveItemsOnTable: " + str(itemTableIdxArray))
		var id = multiplayer.get_remote_sender_id()
		var mrm = getMatch(id)
		var playerIdx = mrm.players.find(id)
		if itemTableIdxArray.size() == mrm.itemsForPlayers[playerIdx].size():
			for idx in itemTableIdxArray:
				if mrm.itemsOnTable[playerIdx][idx].is_empty():
					mrm.itemsOnTable[playerIdx][idx] = mrm.itemsForPlayers[playerIdx][0]
					mrm.itemsForPlayers[playerIdx].remove_at(0)
		mrm.itemsOnTable_ready += 1
		if mrm.itemsOnTable_ready > 1:
			print("SendItemsOnTable: " + str(mrm.itemsOnTable))
			for player in mrm.players:
				mrm.performRPC("table", player, mrm.itemsOnTable)
			mrm.itemsOnTable_ready = 0

@rpc("any_peer", "reliable")
func sendItemsOnTable(_itemsOnTable): pass

@rpc("any_peer", "reliable")
func receiveActionValidation(action):
	if not end:
		print("ReceiveActionValidation: " + action)
		var id = multiplayer.get_remote_sender_id()
		var action_temp = action
		var result = null
		var mrm = getMatch(id)
		var playerIdx = mrm.players.find(id)
		var opponentIdx = int(not playerIdx)
		var validActions
		if mrm.isStealing:
			validActions = mrm.itemsOnTable[opponentIdx].duplicate(true)
			validActions.erase("adrenaline")
		else:
			validActions = mrm.itemsOnTable[playerIdx].duplicate(true)
			validActions.append_array(["pickup shotgun", "shoot self", "shoot opponent"])
		while validActions.has(""):
			validActions.erase("")
		if mrm.isSawed: validActions.erase("handsaw")
		if mrm.isHandcuffed[opponentIdx]: validActions.erase("handcuffs")
		if action.length() == 1:
			action = mrm.itemsOnTable[playerIdx][int(action)]
		if playerIdx != mrm.currentPlayerTurn or validActions.find(action) < 0:
			action_temp = "invalid"
		else: result = mrm.doAction(action, action_temp, playerIdx)
		print("SendActionValidation: " + action_temp + ", " + str(result))
		for player in mrm.players:
			mrm.performRPC("action", player, action_temp, result)
		if mrm.currentPlayerTurn == 0 and mrm.dealer:
			mrm.dealer_action_send()

func doAction(action, action_temp, playerIdx):
	var result
	var opponentIdx = int(not playerIdx)
	match action:
		"pickup shotgun": pass
		"shoot self":
			dealer_shotgunFlag = true
			var shell = shellArray.pop_front()
			result = shell
			if shell == 1:
				var damage = 2 if isSawed else 1
				healthPlayers[playerIdx] -= damage
			if (shell == 1 and isHandcuffed[opponentIdx] != 2) \
				or shellArray.is_empty():
				currentPlayerTurn = int(not playerIdx)
			if isHandcuffed[opponentIdx] > 0:
				if shellArray.is_empty(): isHandcuffed[opponentIdx] = 0
				elif shell == 1: isHandcuffed[opponentIdx] -= 1
			isSawed = false
			if dealer: dealer_knownShells.pop_front()
		"shoot opponent":
			dealer_shotgunFlag = true
			var shell = shellArray.pop_front()
			result = shell
			if shell == 1:
				var damage = 2 if isSawed else 1
				healthPlayers[opponentIdx] -= damage
			if isHandcuffed[opponentIdx] != 2 or shellArray.is_empty():
				currentPlayerTurn = int(not playerIdx)
			if isHandcuffed[opponentIdx] > 0:
				if shellArray.is_empty(): isHandcuffed[opponentIdx] = 0
				else: isHandcuffed[opponentIdx] -= 1
			isSawed = false
			if dealer: dealer_knownShells.pop_front()
		"handsaw":
			doItem(action_temp, playerIdx)
			isSawed = true
		"magnifying glass":
			doItem(action_temp, playerIdx)
			result = shellArray.front()
			if dealer and not bool(playerIdx):
				dealer_knownShells[0] = true
		"beer":
			doItem(action_temp, playerIdx)
			result = shellArray.pop_front()
			if shellArray.is_empty():
				currentPlayerTurn = int(not playerIdx)
			if dealer: dealer_knownShells.pop_front()
		"cigarettes":
			doItem(action_temp, playerIdx)
			healthPlayers[playerIdx] = min(health, healthPlayers[playerIdx] + 1)
			result = healthPlayers[playerIdx]
		"handcuffs":
			doItem(action_temp, playerIdx)
			isHandcuffed[opponentIdx] = 2
		"expired medicine":
			doItem(action_temp, playerIdx)
			result = randf_range(0.0, 1.0) < settings["percentageMedicine"]
			if result: healthPlayers[playerIdx] -= 1
			else: healthPlayers[playerIdx] += 2
		"burner phone":
			doItem(action_temp, playerIdx)
			if shellArray.size() > 1:
				var rand = randi_range(1,shellArray.size()-1)
				if rand == 7: rand -= 1
				result = rand if shellArray[rand] else -rand
				if dealer and not bool(playerIdx):
					dealer_knownShells[rand] = true
			else:
				result = 0
		"adrenaline":
			doItem(action_temp, playerIdx)
			isStealing = true
		"inverter":
			doItem(action_temp, playerIdx)
			shellArray[0] = int(not shellArray[0])
	var roundOver = false
	var winner
	for i in range(2):
		if healthPlayers[i] < 1:
			winner = int(not i)
			roundOver = true
			break
	if roundOver:
		scores[winner] += 1
		roundIdx += 1
		if scores.max() > 1 or roundIdx > 2:
			end = true
			awardWager()
		else:
			beginRound()
	elif (shellArray.is_empty()):
		loadIdx += 1
		beginLoad()
	return result

func doItem(action_temp, playerIdx):
	if isStealing:
		playerIdx = int(not playerIdx)
		isStealing = false
		stealGrace = false
		stealTimer = 0.0
	var action = itemsOnTable[playerIdx][int(action_temp)]
	itemsOnTable[playerIdx][int(action_temp)] = ""
	if dealer: dealer_table[playerIdx].erase(action)

@rpc("any_peer", "reliable")
func sendActionValidation(_action, _result): pass

@rpc("any_peer", "reliable")
func sendTimeoutAdrenaline(): pass

@rpc("any_peer", "reliable")
func receiveActionReady():
	var id = multiplayer.get_remote_sender_id()
	var mrm = getMatch(id)
	var playerIdx = mrm.players.find(id)
	print("ReceiveActionReady from " + str(mrm.players[playerIdx]))
	if mrm.actionReady_first != id:
		mrm.actionReady += 1
		mrm.actionReady_first = id
	if mrm.actionReady > 1:
		mrm.actionReady = 0
		mrm.actionReady_first = 0
		for player in mrm.players:
			mrm.performRPC("ready", player)
		print("SendActionReady")

@rpc("any_peer", "reliable")
func sendActionReady(): pass

func performRPC(type, id, var1 = null, var2 = null):
	if timerRunning:
		timerRunning = false
		mainTimer = 0.0
		for player in players:
			alertCountdown.rpc_id(player,0)
	if id == 0: type = type + " dealer"
	match type:
		"items":
			get_parent().sendItems.rpc_id(id, var1)
		"items dealer":
			dealer_items()
		"table":
			get_parent().sendItemsOnTable.rpc_id(id, var1)
		"table dealer":
			pass
		"action":
			get_parent().sendActionValidation.rpc_id(id, var1, var2)
		"action dealer":
			pass
		"ready":
			get_parent().sendActionReady.rpc_id(id)
		"ready dealer":
			if dealer and end: dealer_end += 1
			if not dealer or dealer_end < 2: actionReady += 1
			elif players.back() > 0:
				await get_tree().create_timer(2, false).timeout
				get_parent().sendActionReady.rpc_id(players.back())
			if dealer_shotgunFlag: dealer_shotgunFlag = false
			elif dealer_roundIdx == roundIdx and dealer_loadIdx == loadIdx \
				and currentPlayerTurn == 0 and dealer_wait == 0 and not end:
				dealer_ready = true
			if dealer_wait > 0: dealer_wait -= 1

func dealer_items():
	for item in itemsForPlayers[0]:
		var grids = [0,1,2,3,4,5,6,7]
		grids.shuffle()
		for i in grids:
			if itemsOnTable[0][i].is_empty():
				itemsOnTable[0][i] = item
				break
	itemsOnTable_ready += 1

func dealer_action_send():
	var d = [0, health, healthPlayers[0]]
	var p = [1, health, healthPlayers[1]]
	for i in range(9):
		d.append(dealer_table[0].count(items[i]))
	for i in range(9):
		p.append(dealer_table[1].count(items[i]))
	var lives = shellArray.count(1)
	var blanks = shellArray.count(0)
	var livesUnknown = 0
	var blanksUnknown = 0
	if dealer_knownShells.count(true) >= dealer_knownShells.size() - 1 \
		or lives == 0 or blanks == 0:
		dealer_knownShells.fill(true)
	else:
		var isLive = false
		for i in shellArray.size():
			isLive = bool(shellArray[i])
			if isLive: livesUnknown += 0 if dealer_knownShells[i] else 1
			else: blanksUnknown += 0 if dealer_knownShells[i] else 1
	var magnifyingGlassResult = 0
	if dealer_knownShells.front(): magnifyingGlassResult = shellArray.front() \
		if bool(shellArray.front()) else 2
	var s = [isHandcuffed[1], magnifyingGlassResult, isSawed, \
			isStealing, lives - livesUnknown, blanks - blanksUnknown]
	print("sending bruteforce request")
	get_parent().sendBruteforce.rpc_id(dealer_bruteforceID, 0, lives, blanks, d, p, s)

func dealer_action_do(option):
	await get_tree().create_timer(0.7).timeout
	var action
	var action_temp
	if dealer_savedAction.is_empty():
		match option:
			1: action = "shoot self"
			3: action = items[0]
			4: action = items[1]
			5: action = items[2]
			6: action = items[3]
			7: action = items[4]
			8: action = items[5]
			9: action = items[6]
			10: action = items[7]
			11: action = items[8]
			_:
				action = "shoot opponent"
				option = 2
		print("Dealer chose option " + str(option) + ": " + action)
		action_temp = str(itemsOnTable[0].find(action)) if option >= 3 else action
		if action.split(" ")[0] == "shoot":
			dealer_savedAction = action
			action = "pickup shotgun"
			action_temp = "pickup shotgun"
	else:
		print("performing saved action: " + dealer_savedAction)
		action = dealer_savedAction
		action_temp = dealer_savedAction
		dealer_savedAction = ""
	var result = doAction(action, action_temp, 0)
	get_parent().sendActionValidation.rpc_id(players[1], action_temp, result)
	if currentPlayerTurn == 0 and dealer_savedAction.is_empty():
		dealer_action_send()

@rpc("any_peer", "reliable")
func receiveBruteforce(option):
	print("received bruteforce response")
	var id = multiplayer.get_remote_sender_id()
	var mrm = null
	for child in get_children():
		if child.dealer_bruteforceID == id:
			mrm = child
			break
	if mrm != null:
		mrm.dealer_action = option
	else: multiplayer.multiplayer_peer.disconnect_peer(id,true)

@rpc("any_peer", "reliable")
func sendBruteforce(_roundType, _liveCount, _blankCount, _player, _opponent, _tempState): pass

func awardWager():
	if wager > 0:
		var winner = players[scores.find(2)]
		AuthManager.awardWager(winner, wager)
		wager = 0

@rpc("any_peer", "reliable")
func requestCountdown():
	return
	if not dealer:
		var id = multiplayer.get_remote_sender_id()
		var mrm = getMatch(id)
		if id != mrm.players[mrm.currentPlayerTurn]:
			for player in mrm.players:
				alertCountdown.rpc_id(player,mrm.settings["timeout"])
			mrm.timerRunning = true

@rpc("any_peer", "reliable")
func alertCountdown(_timeout): pass

func dealerChat(message):
	if not dealerChat_busy:
		dealerChat_busy = true
		var username = AuthManager.loggedInPlayers[players.back()].username
		if MultiplayerManager.chatgpt.checkRateLimit(username):
			var vibeCheck = await MultiplayerManager.chatgpt.moderate(message)
			if vibeCheck:
				var knownShell = ("is " + "Live" if bool(shellArray.front()) else "Blank") \
					if dealer_knownShells.front() else "?"
				var turn = "player's turn" if bool(currentPlayerTurn) else "Dealer's turn"
				var status = "[Dealer " + str(healthPlayers.front()) + "/Player " + \
					str(healthPlayers.back()) + ", Live " + str(shellArray.count(1)) + \
					"/Blank " + str(shellArray.count(0)) + ", " + knownShell + ", " + turn + "]"
				while dealerChat_history.size() > 18:
					dealerChat_history.pop_front()
				var dealerChat_toSubmit = dealerChat_history.duplicate(true)
				dealerChat_toSubmit.append({"role": "system", "content": status})
				dealerChat_toSubmit.append({"role": "user", "content": message})
				dealerChat_history.append({"role": "user", "content": message})
				var response = await MultiplayerManager.chatgpt.complete(username, dealerChat_toSubmit)
				if not response.is_empty():
					dealerChat_history.append({"role": "assistant", "content": response})
					MultiplayerManager.receiveChat.rpc_id(players.back(), response)
		dealerChat_busy = false
