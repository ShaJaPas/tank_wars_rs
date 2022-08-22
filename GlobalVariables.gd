extends Node

var player
var loader
var tanks

var loader_scene = preload("res://Loading/LoadingScreen.tscn")

var current_scene

var tree 
func _ready():
	tree = get_tree()
	Client.connect("connection_closed", self, "reconnect")
	Client.connect("map_found", self, "_on_map_found")

func _on_map_found(data):
	get_tree().create_timer(0.0).connect("timeout", self, "set_battle_scene", [data])

func reconnect():
	player = null
	get_tree().create_timer(0.0).connect("timeout", self, "set_new_scene", [loader_scene])

func set_battle_scene(data):
	var scene = loader.get_resource("res://Battle/Battle.tscn").instance()
	scene.wait_time = data[0]
	scene.map = data[1]
	scene.op_nick = data[2]
	scene.op_tank = data[3]
	scene.initial_packet = data[4]
	for i in range(len(player.tanks)):
		if player.tanks[i].id == data[5].id:
			scene.level = player.tanks[i].level
	scene.tank = get_tank_by_id(data[5].id)
	scene.scene = loader.get_resource("res://Menu/Menu.tscn").instance()
	current_scene.queue_free()
	tree.get_root().add_child(scene)

func set_new_scene(scene):
	current_scene.queue_free()
	var inst = scene.instance()
	inst.reconnect = true
	tree.get_root().add_child(inst)

func get_tank_by_id(id: int):
	for tank in tanks:
		if tank.id == id:
			return tank
