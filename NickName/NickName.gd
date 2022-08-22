extends Node2D

var scene

func _ready():
	GlobalVariables.current_scene = self
	Client.connect("set_nickname", self, "_on_set_nickname")
	Client.connect("get_chest", self, "_on_get_chest")

func _on_get_chest(chest):
	while scene == null:
		pass
	scene.chest = chest
	scene.prev_scene = GlobalVariables.loader.get_resource("res://Menu/Menu.tscn").instance()
	call_deferred("chest_to_player", chest)
	get_tree().create_timer(0.0).connect("timeout", self, "set_new_scene", [scene])
	
func chest_to_player(chest):
	GlobalVariables.player = Client.chest_to_player(chest, GlobalVariables.player)
	
func _on_Enter_pressed():
	var nick = get_node("Background/Box/LineEdit").text
	Client.set_nickname(nick)
	
func _on_set_nickname(err, nick):
	if err != null:
		OS.alert(err, "Nickname error")
	else:
		GlobalVariables.player.nickname = nick
		scene = GlobalVariables.loader.get_resource("res://Chest/ChestOpen.tscn").instance()
	
func set_new_scene(scene_resource):
	queue_free()
	get_tree().get_root().add_child(scene_resource)
