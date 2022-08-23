extends Node2D

var wait_time
var op_nick
var op_tank
var map
var initial_packet
var level
var tank
var scene

var server_frame = -1
var client_frame = 1

const WIDTH = 1280
const HEIGHT = 720
const PERIOD = 1.0 / 30.0
var c_tank_body
var c_tank_gun
var op_tank_body
var op_tank_gun
var time = 0
var objects = []
var max_op_hp
var max_my_hp
var max_op_hp_width
var max_my_hp_width
var op_tank_info
var my_tank_info
var body_rotation: float = 0.0
var gun_rotation: float = 0.0
var in_move = false
var ready_shoot = false

var explosions = []

onready var move_joystick: VirtualJoystick = get_node("UI/Move")
onready var shoot_joystick: VirtualJoystick = get_node("UI/Shoot")
onready var explosion_res = GlobalVariables.loader.get_resource("res://Battle/Explosion.tscn")

func set_map_size(x: int, y: int):
	x -= WIDTH / 2
	y += HEIGHT / 2
	$Map.rect_position = Vector2(-x if x < 0 else 0, max(0, y - $Map.texture.atlas.get_height()))	
	var region = Rect2(max(x, 0), max(0, $Map.texture.atlas.get_height() - y), $Map.texture.atlas.get_width() - x if x + WIDTH > $Map.texture.atlas.get_width() else WIDTH, min(y, HEIGHT))
	$Map.texture.region = region

func _on_Ok_pressed():
	call_deferred("set_new_scene", scene)

func _ready():
	
	GlobalVariables.current_scene = self
	Client.connect("explosion_packet", self, "__on_explosion_packet")
	Client.connect("battle_end", self, "_battle_end")
	
	op_tank_info = GlobalVariables.get_tank_by_id(op_tank.id)
	my_tank_info = GlobalVariables.get_tank_by_id(tank.id)
	
	initial_packet.time_left -= wait_time
	client_frame = initial_packet.frame_num
	max_op_hp = int(op_tank_info.characteristics.hp as float * (1 + (op_tank.level - 1) as float / 10))
	max_my_hp = int(my_tank_info.characteristics.hp as float * (1 + (level - 1) as float / 10))
	max_op_hp_width = get_node("UI/OpHP/Fill").rect_size.x
	max_my_hp_width = get_node("UI/MyHP/Fill").rect_size.x
	$UI/Nick.text = op_nick + " (" + op_tank_info.characteristics.name + " LVL" + str(op_tank.level) + ")" 	
	Client.connect("battle_packet", self, "_on_battle_packet")
	$Map.texture.atlas = load("res://Maps/" + map.name + ".png")
	initial_packet.my_data.body_rotation += 180
	set_map_size(initial_packet.my_data.x, initial_packet.my_data.y)
	
	get_node("UI/Reloading").text = "%.1f" % initial_packet.my_data.cool_down	
	get_node("UI/CountDown").text = str(wait_time)
	
	for obj in map.objects:
		var object = Sprite.new()
		object.texture = GlobalVariables.loader.get_resource("res://Maps/MapObjects/" + str(obj.id) + ".png")
		obj.x += object.texture.get_size().x / 2
		obj.y = $Map.texture.atlas.get_height() - obj.y - object.texture.get_size().y / 2
		object.position = $Map.rect_position + Vector2(obj.x - $Map.texture.region.position.x, obj.y - $Map.texture.region.position.y)
		object.rotation_degrees = reverse_obj_angle(obj.rotation)
		objects.append([object, Vector2(obj.x, obj.y)])
		if obj.id == 7 || obj.id == 8:
			$Objects/Bushes.add_child(object)
		else:
			$Objects.add_child(object)
	
	c_tank_body = Sprite.new()
	c_tank_body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
	c_tank_body.position = Vector2(WIDTH, HEIGHT) / 2
	c_tank_gun = Sprite.new()
	c_tank_gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
	var offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + c_tank_gun.texture.get_size() / 2
	c_tank_gun.set_offset(offset)
	c_tank_gun.position = -c_tank_body.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + c_tank_gun.texture.get_size() / 2	
	c_tank_gun.position -= offset
	c_tank_body.rotation_degrees = reverse_angle(initial_packet.my_data.body_rotation)
	c_tank_body.add_child(c_tank_gun)
	op_tank_body = Sprite.new()
	op_tank_body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + op_tank_info.graphicsInfo.tankBodyName + ".png")
	initial_packet.opponent_data.y = $Map.texture.atlas.get_height() - initial_packet.opponent_data.y
	op_tank_body.position = $Map.rect_position + Vector2(initial_packet.opponent_data.x - $Map.texture.region.position.x,initial_packet.opponent_data.y - $Map.texture.region.position.y)
	op_tank_gun = Sprite.new()
	op_tank_gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + op_tank_info.graphicsInfo.tankGunName + ".png")
	offset = -Vector2(op_tank_info.graphicsInfo.gunOriginX, op_tank_info.graphicsInfo.gunOriginY) + op_tank_gun.texture.get_size() / 2
	op_tank_gun.set_offset(offset)
	op_tank_gun.position = -op_tank_body.texture.get_size() / 2 + Vector2(op_tank_info.graphicsInfo.gunX, op_tank_info.graphicsInfo.gunY) + op_tank_gun.texture.get_size() / 2	
	op_tank_gun.position -= offset
	op_tank_body.rotation_degrees = reverse_angle(initial_packet.opponent_data.body_rotation)
	op_tank_gun.rotation_degrees = - op_tank_body.rotation_degrees
	op_tank_body.add_child(op_tank_gun)
	$Objects.add_child(op_tank_body)
	$Objects.add_child(c_tank_body)
	get_node("UI/OpHP/Text").text = str(max_op_hp) + "/" + str(max_op_hp)
	get_node("UI/MyHP/Text").text = str(max_my_hp) + "/" + str(max_my_hp) 
		
func _on_battle_packet(packet):
	call_deferred("assign", packet)

func _on_explosion_packet(x, y, hit):
	var explosion = explosion_res.instance()
	explosion.hit = hit
	y = $Map.texture.atlas.get_height() - y
	explosion.rect_position = $Map.rect_position + Vector2(x - $Map.texture.region.position.x, y - $Map.texture.region.position.y)
	$Objects.add_child(explosion)
	explosions.append([x, y, explosion])

func _battle_end(data, profile):
	call_deferred("__battle_end", data, profile)

func set_new_scene(scene_resource):
	if scene_resource == null:
		scene_resource = GlobalVariables.loader.get_resource("res://Menu/Menu.tscn").instance()
	queue_free()
	get_tree().get_root().add_child(scene_resource)
	
func __battle_end(data, profile):
	GlobalVariables.player = profile
	get_node("UI/Message").visible = true
	get_node("UI/Message/Title").text = str(data.result)
	get_node("UI/Message/GridContainer/Accuracy").text = "Accuracy - " + ("%.1f" % (data.accuracy * 100.0)) + "%"
	get_node("UI/Message/GridContainer/DamageDealt").text = "Damage dealt - " + str(data.damage_dealt)
	get_node("UI/Message/GridContainer/DamageTaken").text = "Damage taken - " + str(data.damage_taken)
	get_node("UI/Message/GridContainer/Efficiency").text = "Efficiency - " + "%.1f" % (data.efficiency * 100.0) + "%"
	get_node("UI/Message/XP").text = "+" + str(data.xp) + "xp"
	get_node("UI/Message/Trophies/Label").text = str(data.trophies)
	get_node("UI/Message/Coins/Label").text = str(data.coins)
	
func __on_explosion_packet(x, y, hit):
	call_deferred("_on_explosion_packet", x, y, hit)
	
func reverse_obj_angle(angle):
	if angle > 0:
		return 180 - angle
	elif angle < 0:
		return -180 - angle
	return 0

func reverse_angle(angle):
	angle = deg2rad(angle)
	var vec = Vector2(cos(angle), sin(angle))
	vec.y *= -1
	return rad2deg(vec.angle())

func assign(packet):
	if server_frame >= packet.frame_num:
		return
	else:
		server_frame = packet.frame_num
	initial_packet = packet
	c_tank_body.rotation_degrees = reverse_angle(initial_packet.my_data.body_rotation)
	op_tank_body.rotation_degrees = reverse_angle(initial_packet.opponent_data.body_rotation)
	c_tank_gun.rotation_degrees = reverse_angle(initial_packet.my_data.gun_rotation)
	op_tank_gun.rotation_degrees = reverse_angle(initial_packet.opponent_data.gun_rotation)
	set_map_size(initial_packet.my_data.x, initial_packet.my_data.y)
	initial_packet.opponent_data.y = $Map.texture.atlas.get_height() - initial_packet.opponent_data.y
	op_tank_body.position = $Map.rect_position + Vector2(initial_packet.opponent_data.x - $Map.texture.region.position.x,initial_packet.opponent_data.y - $Map.texture.region.position.y)
	for object in objects:
		var size = object[1]
		object[0].position = $Map.rect_position + Vector2(size.x - $Map.texture.region.position.x, size.y - $Map.texture.region.position.y)
	get_node("UI/OpHP/Fill").rect_size.x = max_op_hp_width as float * (initial_packet.opponent_data.hp as float / max_op_hp)
	get_node("UI/OpHP/Text").text = str(initial_packet.opponent_data.hp) + "/" + str(max_op_hp)
	get_node("UI/MyHP/Fill").rect_size.x = max_my_hp_width as float * (initial_packet.my_data.hp as float / max_my_hp)
	get_node("UI/MyHP/Text").text = str(initial_packet.my_data.hp) + "/" + str(max_my_hp)
	get_node("UI/Reloading").text = "%.1f" % initial_packet.my_data.cool_down
	
	var node = get_node("Objects/Bullets")
	for child in node.get_children():
		node.remove_child(child)
	for bullet in initial_packet.my_data.bullets:
		var sprite = Sprite.new()
		sprite.texture = GlobalVariables.loader.get_resource("res://Tanks/Bullets/" + my_tank_info.graphicsInfo.bulletName + ".png")
		sprite.rotation_degrees = reverse_angle(bullet.rotation)
		bullet.y = $Map.texture.atlas.get_height() - bullet.y
		sprite.position = $Map.rect_position + Vector2(bullet.x - $Map.texture.region.position.x, bullet.y - $Map.texture.region.position.y)
		node.add_child(sprite)
	for bullet in initial_packet.opponent_data.bullets:
		var sprite = Sprite.new()
		sprite.texture = GlobalVariables.loader.get_resource("res://Tanks/Bullets/" + op_tank_info.graphicsInfo.bulletName + ".png")
		sprite.rotation_degrees = reverse_angle(bullet.rotation)
		bullet.y = $Map.texture.atlas.get_height() - bullet.y
		sprite.position = $Map.rect_position + Vector2(bullet.x - $Map.texture.region.position.x, bullet.y - $Map.texture.region.position.y)
		node.add_child(sprite)

func _process(delta):
	for i in range(len(explosions)):
		if i >= len(explosions):
			break
		var explosion = explosions[i]
		if !is_instance_valid(explosion[2]):
			explosions.remove(i)
		else:
			var x = explosion[0]
			var y = explosion[1]
			explosion[2].rect_position = $Map.rect_position + Vector2(x - $Map.texture.region.position.x, y - $Map.texture.region.position.y)
		
	$UI/Ping.text = str(min(999, Client.get_ping())) + " ms"
	var tm = int(initial_packet.time_left)
	var minute = int(tm / 60)
	tm -= minute * 60
	$UI/Time.text = ("0" + str(minute) if minute < 10 else str(minute)) + ":" + ("0" + str(tm) if tm < 10 else str(tm))
	if wait_time == 0:
		$UI/CountDown.visible = false
	else:
		wait_time -= delta
		$UI/CountDown.visible = true
		wait_time = max(0, wait_time)
		$UI/CountDown.text = str(int(wait_time) + 1)
	time += delta
	if time >= PERIOD:
		time -= PERIOD
		Client.send_position(client_frame, body_rotation, gun_rotation, in_move)
		client_frame += 1
	
	if move_joystick.get_output() != Vector2.ZERO:
		var move = move_joystick.get_output()
		move.y *= -1
		body_rotation = move.angle() + PI / 2.0
		in_move = true
	else:
		var move = Vector2.ZERO
		move.x = Input.get_axis("ui_left_move", "ui_right_move")
		move.y = Input.get_axis("ui_down_move", "ui_up_move")
		in_move = false
		if move != Vector2.ZERO:
			body_rotation = move.angle() + PI / 2.0
		else:
			body_rotation = 0.0
	if shoot_joystick.get_output() != Vector2.ZERO:
		var shoot = shoot_joystick.get_output()
		shoot.y *= -1
		gun_rotation = shoot.angle() + PI / 2.0
		ready_shoot = true
	else:
		var shoot = Vector2.ZERO
		shoot.x = Input.get_axis("ui_left_shoot", "ui_right_shoot")
		shoot.y = Input.get_axis("ui_down_shoot", "ui_up_shoot")
		if shoot != Vector2.ZERO:
			ready_shoot = false
			gun_rotation = shoot.angle() + PI / 2.0
		else:
			gun_rotation = 0.0
			if ready_shoot:
				Client.shoot()
				ready_shoot = false
