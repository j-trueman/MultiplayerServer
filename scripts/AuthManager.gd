extends Node

var database : SQLite

# Called when the node enters the scene tree for the first time.
func _ready():
	database = SQLite.new()
	database.path = "user://authsignatures.db"
	database.open_db()
	var result = database.query("SELECT * FROM users WHERE 0")
	if result:
		print("TABLE ALREADY EXISTS")
	else:
		print("TABLE DOES NOT EXIST. CREATING...")
		var table = {
			"username" : {"data_type" : "text", "primary_key":true, "not_null": true},
			"signature" : {"data_type": "blob", "not_null":true}
		}
		database.create_table("users", table)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _InsertNewUser(username : String, signature : PackedByteArray) -> bool:
	username = username.to_lower()
	var data = {
		"username" : username,
		"signature" : signature,
	}
	var success = database.insert_row("users", data)
	if success:
		print("CREATED NEW USER %s" % username)
		return true
	else:
		print("FAILED TO CREATE, USER %s ALREADY EXISTS" % username)
		return false
