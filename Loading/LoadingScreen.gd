extends Node2D

var current_scene
var reconnect = false
var battle_req = false
var data = null

func _ready():
	GlobalVariables.current_scene = self
	if !reconnect:
		GlobalVariables.loader = preload("res://resource_queue.gd").new()	
		GlobalVariables.loader.start()
	var root = get_tree().get_root()
	current_scene = root.get_child(root.get_child_count() -1)
	$Background/LoadingAnimation.play("Loading")
	$Background/EternalLoading.play()
	Client.connect("sign_in", self, "_on_sign_in")
	Client.connect("files_sync", self, "_on_files_sync")
	Client.connect("map_found", self, "_on_map_found")
	
	Client.connect_to_server("209.25.141.180:60024")

func _on_map_found(dt):
	if dt != null:
		data = dt
	battle_req = true
	
func _on_sign_in(success: bool, player):
	GlobalVariables.player = player
	if success:
		call_deferred("sign_in")
	else:
		alert('Error: server is unreachable. Check your network connection, and try to reconnect.', 'Connection Error')

func set_battle_scene(data):
	current_scene.queue_free()
	var scene = load("res://Battle/Battle.tscn").instance()
	scene.wait_time = data[0]
	scene.map = data[1]
	scene.op_nick = data[2]
	scene.op_tank = data[3]
	scene.initial_packet = data[4]
	for i in range(len(GlobalVariables.player.tanks)):
		if GlobalVariables.player.tanks[i].id == data[5].id:
			scene.level = GlobalVariables.player.tanks[i].level
	scene.tank = GlobalVariables.get_tank_by_id(data[5].id)
	get_tree().get_root().add_child(scene)

func alert(text: String, title: String='Message') -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = text
	dialog.window_title = title
	dialog.rect_min_size = Vector2(300, 100)
	dialog.connect('confirmed', self, "reconnect")
	add_child(dialog)
	dialog.popup_centered()

func reconnect():
	Client.connect_to_server("209.25.141.180:60024")

func sign_in():
	load_pngs_from_directory("res://Menu/Ranks")
	load_pngs_from_directory("res://Tanks/TankBodies")
	load_pngs_from_directory("res://Tanks/TankGuns")
	load_pngs_from_directory("res://Tanks/Bullets")
	load_pngs_from_directory("res://Maps/MapObjects")
	GlobalVariables.loader.queue_resource("res://NickName/NickName.tscn")
	GlobalVariables.loader.queue_resource("res://Chest/ChestOpen.tscn")
	GlobalVariables.loader.queue_resource("res://Menu/Menu.tscn")
	GlobalVariables.loader.queue_resource("res://Wait/SearchForOpponent.tscn")
	GlobalVariables.loader.queue_resource("res://Battle/Explosion.tscn")
	var node = get_node("Background/LoadingText")  
	node.set_text("Getting data...")
	var font = node.get_font("font")
	var width = font.get_string_size("Getting data").x / 2
	node.rect_position.x = 640 - width
	
func set_new_scene(scene_resource):
	current_scene.queue_free()
	current_scene = scene_resource
	get_node("/root").add_child(current_scene)
	
func _process(_delta):
	if GlobalVariables.loader.remaining_count() == 0 && GlobalVariables.player != null && GlobalVariables.player.nickname == null && battle_req:
		if data == null:
			var scene = GlobalVariables.loader.get_resource("res://NickName/NickName.tscn").instance()
			call_deferred("set_new_scene", scene)
		else:
			set_battle_scene(data)
		set_process(false)
	elif GlobalVariables.loader.remaining_count() == 0 && battle_req:
		if GlobalVariables.player != null && GlobalVariables.player.nickname != null:
			if data == null:
				GlobalVariables.loader.cancel_resource("res://NickName.tscn")
				var scene = GlobalVariables.loader.get_resource("res://Menu/Menu.tscn").instance()
				call_deferred("set_new_scene", scene)
			else:
				set_battle_scene(data)
			set_process(false)
			
func _on_files_sync():
	call_deferred("files_sync")

func files_sync():
	var node = get_node("Background/LoadingText")  	
	node.set_text("Loading textures...")
	var font = node.get_font("font")
	var width = font.get_string_size("Loading textures").x / 2
	node.rect_position.x = 640 - width
	GlobalVariables.tanks = get_tanks_from_directory("user://Tanks")	

func get_tanks_from_directory(path):
	var files = []
	var dir = Directory.new()
	dir.open(path)
	dir.list_dir_begin()

	while true:
		var file: String = dir.get_next()
		if file == "":
			break
		elif not file.begins_with("."):
			var h_file = File.new()
			h_file.open(path + "/" + file, File.READ)
			var text = h_file.get_as_text()
			var dict = JSON.parse(text).result
			h_file.close()
			if dict != null:
				files.append(dict)

	dir.list_dir_end()

	return files

func load_pngs_from_directory(path):
	var dir = Directory.new()
	dir.open(path)
	dir.list_dir_begin()

	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif not file.begins_with(".") && file.ends_with(".png"):
			GlobalVariables.loader.queue_resource(path + "/" + file)

	dir.list_dir_end()

