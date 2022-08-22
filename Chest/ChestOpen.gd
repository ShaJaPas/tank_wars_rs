extends Node2D

var pos = null
var chest
var prev_scene

var diamonds = preload("Diamond.png")
var common = preload("SmallFeaturedItem1.png")
var rare = preload("FrameBrown.png")
var epic = preload("FrameBlue.png")
var mythical = preload("FrameGreen.png")
var legendary = preload("FramePink.png")

func _ready():
	GlobalVariables.current_scene = self
	if chest != null:
		get_node("Bg/Label").text = chest.name + " CHEST"
		
	
func _on_Area2D_input_event(_viewport, event, _shape_idx):
	var button = get_node("Bg/TextureButton")
	if event is InputEventMouseButton:
		if !event.pressed && pos == null:
			return
		if button.visible:
			if event.pressed:
				pos = button.rect_position
				button.rect_position += Vector2(button.rect_size * 0.03) / 2
				button.rect_scale = Vector2(0.97, 0.97)
			else:
				if !button.pressed && pos != null:
					button.rect_position = pos
					button.rect_scale = Vector2.ONE
					button.visible = false
					var anim = get_node("Bg/ChestAnimation")
					get_node("Area2D").visible = false
					anim.visible = true
					anim.playing = true
				else:
					button.rect_position = pos
					button.rect_scale = Vector2.ONE
					get_node("Area2D").visible = false
					var text = get_node("Bg/TextureButton/Cards/Text")
					var loot = get_node("Bg/Loot")
					var loot_text = get_node("Bg/Loot/Count")
					if len(chest.loot) < int(text.text):
						loot_text.text = str(chest.diamonds)
						loot.texture = diamonds
						text.text = str(int(text.text) - 1)
						loot.rect_scale = Vector2.ZERO
					else:
						delete_children(loot)
						get_node("Area2D").visible = false						
						var i = int(text.text) - 1
						if i == -1:
							call_deferred("set_new_scene", prev_scene)
						else:
							text.text = str(i)
							var tank = GlobalVariables.get_tank_by_id(chest.loot[i].id)
							loot_text.rect_position.y = -125
							loot.rect_scale = Vector2.ZERO
							match tank.characteristics.rarity:
								"COMMON":
									loot.texture = common
								"RARE":
									loot.texture = rare
								"EPIC":
									loot.texture = epic
								"MYTHICAL":
									loot.texture = mythical
								"LEGENDARY":
									loot.texture = legendary
							var body = Sprite.new()
							body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
							body.centered = true
							body.position = loot.get_size() / 2
							var gun = Sprite.new()
							gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
							gun.centered = true
							gun.position = -body.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + gun.texture.get_size() / 2
							var offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + gun.texture.get_size() / 2
							gun.set_offset(offset)
							gun.position -= offset
							body.rotation_degrees = 180
							body.add_child(gun)
							loot.add_child(body)
							if chest.loot[i].count == 0:
								loot_text.text = "New Item!\n" + tank.characteristics.name
							else: 
								loot_text.text = "x" + str(chest.loot[i].count) + "\n" + tank.characteristics.name

static func delete_children(node):
	for n in node.get_children():
		if n is Sprite:
			node.remove_child(n)
			n.queue_free()
		
func _on_ChestAnimation_animation_finished():
	var anim = get_node("Bg/ChestAnimation")
	var button = get_node("Bg/TextureButton")
	var cards = get_node("Bg/TextureButton/Cards")
	var coins = get_node("Bg/Loot")	
	var coins_cnt = get_node("Bg/Loot/Count")
	var text = get_node("Bg/TextureButton/Cards/Text")	
	coins.visible = true
	coins_cnt.text = "x" + str(chest.coins)
	var count = len(chest.loot)
	anim.visible = false
	button.pressed = true
	button.visible = true
	cards.visible = true
	if chest.diamonds != 0:
		count += 1
	text.text = str(count)

func set_new_scene(scene_resource):
	queue_free()
	get_tree().get_root().add_child(scene_resource)
