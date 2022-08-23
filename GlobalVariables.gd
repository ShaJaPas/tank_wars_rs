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

func reconnect():
	player = null
	get_tree().create_timer(0.0).connect("timeout", self, "set_new_scene", [loader_scene])

func set_new_scene(scene):
	current_scene.queue_free()
	var inst = scene.instance()
	inst.reconnect = true
	tree.get_root().add_child(inst)

func get_tank_by_id(id: int):
	for tank in tanks:
		if tank.id == id:
			return tank
