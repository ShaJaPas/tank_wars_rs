extends Node2D

var time = 0
var scene
var tank
var level
var found = false
var sel_id
var data

func _ready():
	GlobalVariables.current_scene = self
	get_node("Bg/AnimatedSprite").playing = true
	$Bg/LoadingAnimation.play("Loading")
	$Bg/Selected.text = tank.characteristics.name + " (" + str(level) +  "LVL)"
	var bd = Sprite.new()
	bd.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
	bd.position = $Bg.get_size() / 2 + Vector2(0, 100)
	bd.scale = Vector2(2, 2)
	var gn = Sprite.new()
	gn.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
	gn.position = -bd.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + gn.texture.get_size() / 2
	var offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + gn.texture.get_size() / 2
	gn.set_offset(offset)
	gn.position -= offset
	bd.rotation_degrees = 180
	bd.add_child(gn)
	$Bg.add_child(bd)
	Client.disconnect("map_found", GlobalVariables, "_on_map_found")
	Client.connect("map_found", self, "_on_map_found")
	Client.join_balancer(sel_id)

func _on_map_found(_data):
	GlobalVariables.loader.queue_resource("res://Battle/Battle.tscn")
	$Bg/Cancel.call_deferred("set_visible", false)
	$Bg/LoadingAnimation.call_deferred("stop", true)
	$Bg/Search.call_deferred("set_text", "")
	data = _data
	found = true

func _process(delta):
	time += delta
	$Bg/Time.text = str(int(time)) + "s"
	if found:
		if GlobalVariables.loader.is_ready("res://Battle/Battle.tscn"):
			var _scene = GlobalVariables.loader.get_resource("res://Battle/Battle.tscn").instance()
			_scene.wait_time = data[0]
			_scene.map = data[1]
			_scene.op_nick = data[2]
			_scene.op_tank = data[3]
			_scene.initial_packet = data[4]
			_scene.tank = tank
			_scene.level = level
			_scene.scene = scene
			set_new_scene(_scene)

func set_new_scene(scene_resource):
	Client.connect("map_found", GlobalVariables, "_on_map_found")
	Client.disconnect("map_found", self, "_on_map_found")
	queue_free()
	get_tree().get_root().add_child(scene_resource)
	
func _on_Cancel_pressed():
	Client.disconnect("map_found", self, "_on_map_found")
	call_deferred("set_new_scene", scene)
	Client.exit_balancer()
