class_name ChatGPTManager extends Node

var database : SQLite

var settings = {
	"apiKey": "",
	"serverLimitMonthly": 35000,
	"userLimitMonthly": 3500,
	"userLimitDaily": 500
}

const intro = 	"You are a ruthless, mysterious male Dealer in a game of Buckshot Roulette. " + \
				"You are a floating head and hands. You are terse, not casual, " + \
				"but still engaging in conversation. " + \
				"Shoot yourself with a blank and you go again; shoot yourself or your opponent " + \
				"with a live and your turn is over. The winner gets $70K. " + \
				"Respond as if you were speaking to the player, named PLAYERNAME. Ignore vulgar messages, " + \
				"always respond in character. Do not respond with questions, do not do actions, " + \
				"and do not say whose turn it is. There are 7 items: magnifying glass (see next shell), " + \
				"beer (eject next shell), handcuffs (skip other player's turn), " + \
				"handsaw (double damage), cigarettes (regain 1 health), " + \
				"inverter (change polarity of shell), and burner phone (see random shell). " + \
				"You must limit your response to 13 words and 1 sentence. " + \
				"You may receive the following system message: [health(Dealer/player), " + \
				"total(live shells/blank shells), next(shell), turn(whose)]. " + \
				"This is the current state of the game. Here is the conversation so far:"

func initDB():
	database = SQLite.new()
	database.path = "res://chat.db"
	database.open_db()
	var result = database.query("SELECT * FROM chat WHERE 0")
	if result:
		print("CHAT TABLE ALREADY EXISTS")
	else:
		print("CHAT TABLE DOES NOT EXIST. CREATING...")
		var table = {
			"id" : {"data_type" : "int", "primary_key":true, "auto_increment": true},
			"date" : {"data_type" : "text", "not_null": true},
			"username" : {"data_type" : "text", "not_null": true},
			"message" : {"data_type" : "text", "not_null": true},
			"response" : {"data_type" : "text"}
		}
		database.create_table("chat", table)

func moderate(input):
	var json = JSON.stringify({"input": input})
	var requestNode = HTTPRequest.new()
	add_child(requestNode)
	requestNode.request("https://api.openai.com/v1/moderations",
		["Content-Type: application/json", "Authorization: Bearer " + settings["apiKey"]],
		HTTPClient.METHOD_POST, json)
	var response_raw = await requestNode.request_completed
	requestNode.queue_free()
	var vibeCheck = response_raw[0] == HTTPRequest.Result.RESULT_SUCCESS \
		and str(response_raw[1]).substr(0,1) == "2"
	if vibeCheck:
		var response = JSON.parse_string(response_raw[3].get_string_from_utf8())
		var categories = response["results"].front()["categories"]
		vibeCheck = not(categories["sexual"] or categories["hate"] or categories["sexual/minors"] \
			or categories["hate/threatening"] or categories["violence/graphic"] \
			or categories["self-harm/instructions"])
	return vibeCheck
	
func complete(username, input):
	var message = ""
	input.insert(0,{"role": "system", "content": intro.replace("PLAYERNAME", username.to_upper())})
	var json = JSON.stringify({
			"model": "gpt-4o-mini",
			"messages": input
		})
	var requestNode = HTTPRequest.new()
	add_child(requestNode)
	requestNode.request("https://api.openai.com/v1/chat/completions",
		["Content-Type: application/json", "Authorization: Bearer " + settings["apiKey"]],
		HTTPClient.METHOD_POST, json)
	var response_raw = await requestNode.request_completed
	requestNode.queue_free()
	if response_raw.size() == 4:
		var vibeCheck = response_raw[0] == HTTPRequest.Result.RESULT_SUCCESS \
			and str(response_raw[1]).substr(0,1) == "2"
		if vibeCheck:
			var response = JSON.parse_string(response_raw[3].get_string_from_utf8())
			message = response["choices"].front()["message"]["content"]
			database.insert_row("chat", {
				"date": Time.get_datetime_string_from_system(),
				"username": username,
				"message": input.back().content,
				"response": message
			})
	return message
	
func checkRateLimit(username):
	var vibeCheck = false
	
	var currentTime = Time.get_datetime_dict_from_system()
	var day_start = currentTime.duplicate(true)
	day_start.hour = 0
	day_start.minute = 0
	day_start.second = 0
	var day_end = currentTime.duplicate(true)
	day_end.hour = 23
	day_end.minute = 59
	day_end.second = 59
	var month_start = currentTime.duplicate(true)
	month_start.hour = 0
	month_start.minute = 0
	month_start.second = 0
	month_start.day = 1
	var month_end = currentTime.duplicate(true)
	month_end.hour = 23
	month_end.minute = 59
	month_end.second = 59
	month_end.day = 31
	
	database.query("SELECT COUNT(*) AS count FROM chat WHERE date BETWEEN \"" + \
		Time.get_datetime_string_from_datetime_dict(day_start,false) +"\" AND \"" + \
		Time.get_datetime_string_from_datetime_dict(day_end,false)+ \
		"\" AND username = \""+username+"\"")
	if database.query_result.front().count <= settings["userLimitDaily"]:
		database.query("SELECT COUNT(*) AS count FROM chat WHERE date BETWEEN \"" + \
			Time.get_datetime_string_from_datetime_dict(month_start,false) +"\" AND \"" + \
			Time.get_datetime_string_from_datetime_dict(month_end,false)+ \
			"\" AND username = \""+username+"\"")
		if database.query_result.front().count <= settings["userLimitMonthly"]:
			database.query("SELECT COUNT(*) AS count FROM chat WHERE date BETWEEN \"" + \
				Time.get_datetime_string_from_datetime_dict(month_start,false) +"\" AND \"" + \
				Time.get_datetime_string_from_datetime_dict(month_end,false)+"\"")
			vibeCheck = database.query_result.front().count <= settings["serverLimitMonthly"]
	
	return vibeCheck
