extends Node2D

var tank_bg = preload("Btn.png")
var bar_container = preload("LevelBarContainer.png")
var bar = preload("LevelBar.png")
var fnt = preload("res://Fonts/SemiBold.ttf")
var bg_sel = preload("BgSelected.png")
var selected
var tank_sel
var gun_sel
var sel_id: int
var can_upgrade: bool = true
var lbl: Label
var time: float
var tree 

func _ready():
	GlobalVariables.current_scene = self
	Client.connect("get_chest", self, "_on_get_chest")
	Client.connect("upgrade_tank", self, "_on_upgrade_tank")
	Client.connect("get_daily_items", self, "_on_get_daily_items")
	Client.connect("buy_daily_item", self, "_on_buy_daily_item")
	time = 12 * 60 * 60 - Client.remaining_time(GlobalVariables.player)
	tree = get_tree()
	tree.create_timer(max(0, time)).connect("timeout", self, "daily_items")
	tree.create_timer(0.0).connect("timeout", self, "daily_items")	

func _on_buy_daily_item(player):
	call_deferred("__on_buy_daily_item", player)

func __on_buy_daily_item(player):
	if player != null:
		GlobalVariables.player = player
		update_stats()
		
func _on_get_chest(chest):
	if chest.name == "COMMON":
		GlobalVariables.player.coins -= 100
	var scene = GlobalVariables.loader.get_resource("res://Chest/ChestOpen.tscn").instance()
	scene.chest = chest
	scene.prev_scene = self
	call_deferred("chest_to_player", chest)
	tree.create_timer(0.0).connect("timeout", self, "daily_items")
	get_tree().create_timer(0.0).connect("timeout", self, "set_new_scene", [scene])

func _on_upgrade_tank(id):
	can_upgrade = true
	if id != null:
		for i in range(len(GlobalVariables.player.tanks)):
			if GlobalVariables.player.tanks[i].id == id:
				GlobalVariables.player.tanks[i].count -= int(pow(2, GlobalVariables.player.tanks[i].level - 1)) * 50
				GlobalVariables.player.tanks[i].level += 1
		call_deferred("update_stats")
	
func _on_get_daily_items(items, dtime):
	GlobalVariables.player.daily_items = items
	if dtime != null:
		GlobalVariables.player.daily_items_time = dtime
		call_deferred("set_time")
	call_deferred("update_stats")

func set_time():
	time = 12 * 60 * 60 - Client.remaining_time(GlobalVariables.player)
	tree.create_timer(max(0, time)).connect("timeout", self, "daily_items")

func chest_to_player(chest):
	GlobalVariables.player = Client.chest_to_player(chest, GlobalVariables.player)

func _on_map_found(data):
	call_deferred("__on_map_found", data)

func __on_map_found(data):
	var _scene = GlobalVariables.loader.get_resource("res://Battle/Battle.tscn").instance()
	_scene.wait_time = data[0]
	_scene.map = data[1]
	_scene.op_nick = data[2]
	_scene.op_tank = data[3]
	_scene.initial_packet = data[4]
	_scene.tank = GlobalVariables.get_tank_by_id(sel_id)
	for i in range(len(GlobalVariables.player.tanks)):
		if GlobalVariables.player.tanks[i].id == sel_id:
			_scene.level = GlobalVariables.player.tanks[i].level
	_scene.scene = self
	set_new_scene(_scene)

func update_stats():
	get_node("Bg/TabContainer/HOME/Bg/Coins/Count").text = str(GlobalVariables.player.coins)
	get_node("Bg/TabContainer/HOME/Bg/Diamond/Count").text = str(GlobalVariables.player.diamonds)
	get_node("Bg/TabContainer/PROFILE/LVL").text = "LVL" + str(GlobalVariables.player.rank_level)
	get_node("Bg/TabContainer/PROFILE/Label/Label").text = str(GlobalVariables.player.battles_count)
	get_node("Bg/TabContainer/PROFILE/Label2/Label").text = "%.1f" % (Client.player_efficiency(GlobalVariables.player) * 100) + "%"
	get_node("Bg/TabContainer/PROFILE/Label3/Label").text = "%.1f" % ((GlobalVariables.player.victories_count as float / GlobalVariables.player.battles_count * 100) if GlobalVariables.player.battles_count > 0 else 0) + "%"
	get_node("Bg/TabContainer/PROFILE/Label4/Label").text = "%.1f" % (GlobalVariables.player.accuracy as float * 100) + "%"	
	get_node("Bg/TabContainer/PROFILE/Label5/Label").text = str(GlobalVariables.player.damage_dealt)
	get_node("Bg/TabContainer/PROFILE/Label6/Label").text = str(GlobalVariables.player.damage_taken)
	get_node("Bg/TabContainer/PROFILE/Trophies").text = str(GlobalVariables.player.trophies)
	get_node("Bg/TabContainer/PROFILE/PlayerNameBackground/Nick").text = GlobalVariables.player.nickname
	if GlobalVariables.player.coins < 100:
		get_node("Bg/TabContainer/SHOP/CCFrame/Label2").set("custom_colors/font_color", Color("#D30000"))
	else:
		get_node("Bg/TabContainer/SHOP/CCFrame/Label2").set("custom_colors/font_color", Color(1, 1, 1, 1))
	var common_tank = GlobalVariables.get_tank_by_id(GlobalVariables.player.daily_items[0].tank_id)
	get_node("Bg/TabContainer/SHOP/DailyItems/Common/Label").text = common_tank.characteristics.name
	if GlobalVariables.player.daily_items[0].bought:
		get_node("Bg/TabContainer/SHOP/DailyItems/Common/Bought").visible = true
	else:
		get_node("Bg/TabContainer/SHOP/DailyItems/Common/Bought").visible = false
	get_node("Bg/TabContainer/SHOP/DailyItems/Common/Count").text = "x" + str(GlobalVariables.player.daily_items[0].count) if GlobalVariables.player.daily_items[0].count > 0 else "New vehicle!"
	get_node("Bg/TabContainer/SHOP/DailyItems/Common/Price").text = str(GlobalVariables.player.daily_items[0].price)
	var c_tank_body = get_node("Bg/TabContainer/SHOP/DailyItems/Common/TankBody")
	c_tank_body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + common_tank.graphicsInfo.tankBodyName + ".png")
	c_tank_body.position = get_node("Bg/TabContainer/SHOP/DailyItems/Common").rect_size / 2 - Vector2(0, 5)
	var c_tank_gun = get_node("Bg/TabContainer/SHOP/DailyItems/Common/TankBody/TankGun")
	c_tank_gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + common_tank.graphicsInfo.tankGunName + ".png")
	var scl = 80 as float / (common_tank.graphicsInfo.gunY + c_tank_gun.texture.get_size().y)
	c_tank_body.scale = Vector2(scl, scl)
	var offset = -Vector2(common_tank.graphicsInfo.gunOriginX, common_tank.graphicsInfo.gunOriginY) + c_tank_gun.texture.get_size() / 2
	c_tank_gun.set_offset(offset)
	c_tank_gun.position = -c_tank_body.texture.get_size() / 2 + Vector2(common_tank.graphicsInfo.gunX, common_tank.graphicsInfo.gunY) + c_tank_gun.texture.get_size() / 2	
	c_tank_gun.position -= offset
	c_tank_body.rotation_degrees = 180
	var rare_tank = GlobalVariables.get_tank_by_id(GlobalVariables.player.daily_items[1].tank_id)
	get_node("Bg/TabContainer/SHOP/DailyItems/Rare/Label").text = rare_tank.characteristics.name
	if GlobalVariables.player.daily_items[1].bought:
		get_node("Bg/TabContainer/SHOP/DailyItems/Rare/Bought").visible = true
	else:
		get_node("Bg/TabContainer/SHOP/DailyItems/Rare/Bought").visible = false
	get_node("Bg/TabContainer/SHOP/DailyItems/Rare/Count").text = "x" + str(GlobalVariables.player.daily_items[1].count) if GlobalVariables.player.daily_items[1].count > 0 else "New vehicle!"	
	get_node("Bg/TabContainer/SHOP/DailyItems/Rare/Price").text = str(GlobalVariables.player.daily_items[1].price)	
	var r_tank_body = get_node("Bg/TabContainer/SHOP/DailyItems/Rare/TankBody")
	r_tank_body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + rare_tank.graphicsInfo.tankBodyName + ".png")
	r_tank_body.position = get_node("Bg/TabContainer/SHOP/DailyItems/Rare").rect_size / 2 - Vector2(0, 5)
	var r_tank_gun = get_node("Bg/TabContainer/SHOP/DailyItems/Rare/TankBody/TankGun")
	r_tank_gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + rare_tank.graphicsInfo.tankGunName + ".png")
	scl = 80 as float / (rare_tank.graphicsInfo.gunY + r_tank_gun.texture.get_size().y)
	r_tank_body.scale = Vector2(scl, scl)
	offset = -Vector2(rare_tank.graphicsInfo.gunOriginX, rare_tank.graphicsInfo.gunOriginY) + r_tank_gun.texture.get_size() / 2
	r_tank_gun.set_offset(offset)
	r_tank_gun.position = -r_tank_body.texture.get_size() / 2 + Vector2(rare_tank.graphicsInfo.gunX, rare_tank.graphicsInfo.gunY) + r_tank_gun.texture.get_size() / 2	
	r_tank_gun.position -= offset
	r_tank_body.rotation_degrees = 180
	var epic_tank = GlobalVariables.get_tank_by_id(GlobalVariables.player.daily_items[2].tank_id)
	get_node("Bg/TabContainer/SHOP/DailyItems/Epic/Label").text = epic_tank.characteristics.name
	if GlobalVariables.player.daily_items[2].bought:
		get_node("Bg/TabContainer/SHOP/DailyItems/Epic/Bought").visible = true
	else:
		get_node("Bg/TabContainer/SHOP/DailyItems/Epic/Bought").visible = false
	get_node("Bg/TabContainer/SHOP/DailyItems/Epic/Count").text = "x" + str(GlobalVariables.player.daily_items[2].count) if GlobalVariables.player.daily_items[2].count > 0 else "New vehicle!"		
	get_node("Bg/TabContainer/SHOP/DailyItems/Epic/Price").text = str(GlobalVariables.player.daily_items[2].price)
	var e_tank_body = get_node("Bg/TabContainer/SHOP/DailyItems/Epic/TankBody")
	e_tank_body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + epic_tank.graphicsInfo.tankBodyName + ".png")
	e_tank_body.position = get_node("Bg/TabContainer/SHOP/DailyItems/Epic").rect_size / 2 - Vector2(0, 5)
	var e_tank_gun = get_node("Bg/TabContainer/SHOP/DailyItems/Epic/TankBody/TankGun")
	e_tank_gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + epic_tank.graphicsInfo.tankGunName + ".png")
	scl = 80 as float / (epic_tank.graphicsInfo.gunY + e_tank_gun.texture.get_size().y)
	e_tank_body.scale = Vector2(scl, scl)
	offset = -Vector2(epic_tank.graphicsInfo.gunOriginX, epic_tank.graphicsInfo.gunOriginY) + e_tank_gun.texture.get_size() / 2
	e_tank_gun.set_offset(offset)
	e_tank_gun.position = -e_tank_body.texture.get_size() / 2 + Vector2(epic_tank.graphicsInfo.gunX, epic_tank.graphicsInfo.gunY) + e_tank_gun.texture.get_size() / 2	
	e_tank_gun.position -= offset
	e_tank_body.rotation_degrees = 180
	var mythical_tank = GlobalVariables.get_tank_by_id(GlobalVariables.player.daily_items[3].tank_id)	
	get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/Label").text = mythical_tank.characteristics.name
	if GlobalVariables.player.daily_items[3].bought:
		get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/Bought").visible = true
	else:
		get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/Bought").visible = false
	get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/Count").text = "x" + str(GlobalVariables.player.daily_items[3].count) if GlobalVariables.player.daily_items[3].count > 0 else "New vehicle!"			
	get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/Price").text = str(GlobalVariables.player.daily_items[3].price)	
	var m_tank_body = get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/TankBody")
	m_tank_body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + mythical_tank.graphicsInfo.tankBodyName + ".png")
	m_tank_body.position = get_node("Bg/TabContainer/SHOP/DailyItems/Mythical").rect_size / 2 - Vector2(0, 5)
	var m_tank_gun = get_node("Bg/TabContainer/SHOP/DailyItems/Mythical/TankBody/TankGun")
	m_tank_gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + mythical_tank.graphicsInfo.tankGunName + ".png")
	scl = 80 as float / (mythical_tank.graphicsInfo.gunY + m_tank_gun.texture.get_size().y)
	m_tank_body.scale = Vector2(scl, scl)
	offset = -Vector2(mythical_tank.graphicsInfo.gunOriginX, mythical_tank.graphicsInfo.gunOriginY) + m_tank_gun.texture.get_size() / 2
	m_tank_gun.set_offset(offset)
	m_tank_gun.position = -m_tank_body.texture.get_size() / 2 + Vector2(mythical_tank.graphicsInfo.gunX, mythical_tank.graphicsInfo.gunY) + m_tank_gun.texture.get_size() / 2	
	m_tank_gun.position -= offset
	m_tank_body.rotation_degrees = 180

	
	var rank = int(GlobalVariables.player.trophies / 100)
	get_node("Bg/TabContainer/PROFILE/Rank").text = str(rank + 1) + " Rank"
	get_node("Bg/TabContainer/PROFILE/Rank0").texture = GlobalVariables.loader.get_resource("res://Menu/Ranks/rank" + str(rank) + ".png")
	var date = (str(GlobalVariables.player.reg_date.day) if GlobalVariables.player.reg_date.day > 9 else "0" + str(GlobalVariables.player.reg_date.day)) + "." + (str(GlobalVariables.player.reg_date.month) if GlobalVariables.player.reg_date.month > 9 else "0" + str(GlobalVariables.player.reg_date.month)) + "." + str(GlobalVariables.player.reg_date.year)
	var time =  (str(GlobalVariables.player.reg_date.hour) if GlobalVariables.player.reg_date.hour > 9 else "0" + str(GlobalVariables.player.reg_date.hour)) + ":" +  (str(GlobalVariables.player.reg_date.minute) if GlobalVariables.player.reg_date.minute > 9 else "0" + str(GlobalVariables.player.reg_date.minute))
	get_node("Bg/TabContainer/PROFILE/Reg").text = "Registered: " + date + " at " + time
	var xp_bound = int(pow(3, GlobalVariables.player.rank_level as float / 10) * GlobalVariables.player.rank_level * 50)
	var p_lvl : TextureRect = TextureRect.new()
	p_lvl.expand = true
	p_lvl.stretch_mode = TextureRect.STRETCH_SCALE
	p_lvl.texture = bar
	var container = get_node("Bg/TabContainer/PROFILE/LVL/XP")
	p_lvl.rect_size = container.rect_size
	p_lvl.rect_size.x *= min(1, GlobalVariables.player.xp as float / xp_bound)
	container.add_child(p_lvl)
	get_node("Bg/TabContainer/PROFILE/LVL/exp").text = str(GlobalVariables.player.xp) + "/" + str(xp_bound)
	var tanks_grid = get_node("Bg/TabContainer/HOME/Bg/TextureRect/ScrollContainer/Tanks")
	get_node("Bg/TabContainer/HOME/Bg/TextureRect/ScrollContainer").get_h_scrollbar().rect_scale.x = 0
	for x in tanks_grid.get_children():
		tanks_grid.remove_child(x)
	for i in range(len(GlobalVariables.player.tanks)):
		var bg : TextureRect = TextureRect.new()
		var tank = GlobalVariables.get_tank_by_id(GlobalVariables.player.tanks[i].id)		
		bg.connect("gui_input", self, "_on_gui_event", [bg, tank, GlobalVariables.player.tanks[i].level, GlobalVariables.player.tanks[i].count])
		if selected == null || sel_id == GlobalVariables.player.tanks[i].id:
			sel_id = tank.id
			bg.texture = bg_sel
			selected = bg
			if tank_sel == null:
				var bd = Sprite.new()
				bd.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
				bd.position = get_node("Bg/TabContainer/HOME/Bg").get_size() / 2 - Vector2(0, 100)
				var gn = Sprite.new()
				gn.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
				gn.position = -bd.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + gn.texture.get_size() / 2
				offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + gn.texture.get_size() / 2
				gn.set_offset(offset)
				gn.position -= offset
				bd.rotation_degrees = 180
				bd.add_child(gn)
				tank_sel = bd
				gun_sel = gn
				get_node("Bg/TabContainer/HOME/Bg").add_child(bd)
			else:
				tank_sel.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
				gun_sel.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
				gun_sel.position = -tank_sel.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + gun_sel.texture.get_size() / 2
				offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + gun_sel.texture.get_size() / 2
				gun_sel.set_offset(offset)
				gun_sel.position -= offset
			if lbl == null:
				lbl = Label.new()
				var fnt1 : DynamicFont = DynamicFont.new()
				fnt1.font_data = fnt
				lbl.rect_size = Vector2(160, 30)
				lbl.rect_position = Vector2(get_node("Bg/TabContainer/HOME/Bg").get_size().x / 2 - 80, 65)
				lbl.align = Label.ALIGN_CENTER
				lbl.text = str(GlobalVariables.player.tanks[i].level) + " LVL"
				fnt1.size = 36
				fnt1.use_filter = true
				lbl.set("custom_fonts/font", fnt1)
				get_node("Bg/TabContainer/HOME/Bg").add_child(lbl)
			else:
				lbl.text = str(GlobalVariables.player.tanks[i].level) + " LVL"
			get_node("Bg/TabContainer/HOME/Label1").text = "RARITY: " + tank.characteristics.rarity
			get_node("Bg/TabContainer/HOME/Label2").text = "HIT POINTS: " + str(int(tank.characteristics.hp as float * (1 + (GlobalVariables.player.tanks[i].level - 1) as float / 10)))
			get_node("Bg/TabContainer/HOME/Label3").text = "DAMAGE: " + str(int(tank.characteristics.damage as float * (1 + (GlobalVariables.player.tanks[i].level - 1) as float / 10)))
			get_node("Bg/TabContainer/HOME/Label4").text = "RELOADING: " + str(tank.characteristics.reloading)
			get_node("Bg/TabContainer/HOME/Label5").text = "VELOCITY: " + str(tank.characteristics.velocity)
			get_node("Bg/TabContainer/HOME/Label6").text = "BULLET SPEED: " + str(tank.characteristics.bulletSpeed)
			get_node("Bg/TabContainer/HOME/Label7").text = "BODY ROTATION SPEED: " + str(tank.characteristics.bodyRotateDegrees)
			get_node("Bg/TabContainer/HOME/Label8").text = "GUN ROTATION SPEED: " + str(tank.characteristics.gunRotateDegrees)
			if GlobalVariables.player.tanks[i].count >= int(pow(2, GlobalVariables.player.tanks[i].level - 1)) * 50:
				get_node("Bg/TabContainer/HOME/Upgrade").visible = true
			else:
				get_node("Bg/TabContainer/HOME/Upgrade").visible = false
		else:
			bg.texture = tank_bg
		bg.expand = true
		bg.rect_size = Vector2(160, 160)
		bg.rect_min_size = Vector2(160, 160)
		var font : DynamicFont = DynamicFont.new()
		font.font_data = fnt
		var label : Label = Label.new()
		label.rect_size = Vector2(160, 30)
		label.rect_position = Vector2(0, 3)
		label.align = Label.ALIGN_CENTER
		label.text = tank.characteristics.name
		font.size = 26
		font.size = min(font.size, font.size * (140 as float / font.get_string_size(label.text).x))
		label.set("custom_fonts/font", font)
		bg.add_child(label)
		var body = Sprite.new()
		body.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
		body.centered = true
		body.scale = Vector2(70, 70) / body.texture.get_size()
		body.position = bg.get_size() / 2 + Vector2(0, 10)
		var gun = Sprite.new()
		gun.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
		gun.centered = true
		gun.position = -body.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + gun.texture.get_size() / 2
		offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + gun.texture.get_size() / 2
		gun.set_offset(offset)
		gun.position -= offset
		body.rotation_degrees = 180
		body.add_child(gun)
		bg.add_child(body)
		var bound = int(pow(2, GlobalVariables.player.tanks[i].level - 1)) * 50
		var lvl_container : TextureRect = TextureRect.new()
		lvl_container.expand = true
		lvl_container.texture = bar_container
		lvl_container.rect_size = Vector2(130, 15)
		lvl_container.rect_position = Vector2(15, 135)
		var lvl : TextureRect = TextureRect.new()
		lvl.expand = true
		lvl.texture = bar
		lvl.rect_size = Vector2(130, 15)
		lvl.rect_size.x *= min(1, GlobalVariables.player.tanks[i].count as float / bound)
		lvl_container.add_child(lvl)
		var lvl_font : DynamicFont = DynamicFont.new()
		lvl_font.font_data = fnt
		lvl_font.size = 12
		var lvl_label : Label = Label.new()
		lvl_label.rect_size = Vector2(130, 15)
		lvl_label.rect_position = Vector2(0, -2)
		lvl_label.align = Label.ALIGN_CENTER
		lvl_label.set("custom_fonts/font", lvl_font)
		lvl_label.text = str(GlobalVariables.player.tanks[i].count) + "/" + str(bound)
		lvl.add_child(lvl_label)
		bg.add_child(lvl_container)
		tanks_grid.add_child(bg)
	
func _on_gui_event(event, emitter, tank, level, count):
	if event is InputEventMouseButton:
		if event.pressed:
			if selected != emitter:
				sel_id = tank.id
				selected.texture = tank_bg
				selected = emitter
				selected.texture = bg_sel
				tank_sel.texture = GlobalVariables.loader.get_resource("res://Tanks/TankBodies/" + tank.graphicsInfo.tankBodyName + ".png")
				gun_sel.texture = GlobalVariables.loader.get_resource("res://Tanks/TankGuns/" + tank.graphicsInfo.tankGunName + ".png")
				gun_sel.position = -tank_sel.texture.get_size() / 2 + Vector2(tank.graphicsInfo.gunX, tank.graphicsInfo.gunY) + gun_sel.texture.get_size() / 2
				var offset = -Vector2(tank.graphicsInfo.gunOriginX, tank.graphicsInfo.gunOriginY) + gun_sel.texture.get_size() / 2
				gun_sel.set_offset(offset)
				gun_sel.position -= offset
				get_node("Bg/TabContainer/HOME/Label1").text = "RARITY: " + tank.characteristics.rarity
				get_node("Bg/TabContainer/HOME/Label2").text = "HIT POINTS: " + str(int(tank.characteristics.hp as float * (1 + (level - 1) as float / 10)))
				get_node("Bg/TabContainer/HOME/Label3").text = "DAMAGE: " + str(int(tank.characteristics.damage as float * (1 + (level - 1) as float / 10)))
				get_node("Bg/TabContainer/HOME/Label4").text = "RELOADING: " + str(tank.characteristics.reloading)
				get_node("Bg/TabContainer/HOME/Label5").text = "VELOCITY: " + str(tank.characteristics.velocity)
				get_node("Bg/TabContainer/HOME/Label6").text = "BULLET SPEED: " + str(tank.characteristics.bulletSpeed)
				get_node("Bg/TabContainer/HOME/Label7").text = "BODY ROTATION SPEED: " + str(tank.characteristics.bodyRotateDegrees)
				get_node("Bg/TabContainer/HOME/Label8").text = "GUN ROTATION SPEED: " + str(tank.characteristics.gunRotateDegrees)	
				lbl.text = str(level) + " LVL"
				if count >= int(pow(2, level - 1)) * 50:
					get_node("Bg/TabContainer/HOME/Upgrade").visible = true
				else:
					get_node("Bg/TabContainer/HOME/Upgrade").visible = false

func daily_items():
	Client.get_daily_items()

func _process(delta):
	#ping
	var ping = Client.get_ping()
	if ping >= 150:
		get_node("Bg/Ping/bar3").visible = false
	else:
		get_node("Bg/Ping/bar3").visible = true
	if ping >= 300:
		get_node("Bg/Ping/bar2").visible = false
	else:
		get_node("Bg/Ping/bar2").visible = true
	get_node("Bg/Ping").text = str(min(ping, 999)) + " ms"
	if time >= 0:
		time -= delta
	var rt = time
	var hour = int(rt / 60 / 60)
	rt -= hour * 60 * 60
	var minute = int(rt / 60)
	rt -= minute * 60
	var second = int(rt)
	get_node("Bg/TabContainer/SHOP/Time").text = ("0" + str(hour) if hour < 10 else str(hour)) + ":" + ("0" + str(minute) if minute < 10 else str(minute)) + ":" + ("0" + str(second) if second < 10 else str(second))

func _on_CCFrame_gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			Client.buy_chest("COMMON")

func set_new_scene(scene_resource):
	var root = get_node("/root")
	root.remove_child(self)
	root.add_child(scene_resource)

func _on_Upgrade_pressed():
	if can_upgrade:
		Client.upgrade_tank(sel_id)
		can_upgrade = false


func _on_Node2D_tree_entered():
	Client.connect("map_found", self, "_on_map_found")
	GlobalVariables.current_scene = self
	call_deferred("update_stats")

func _on_Enter_pressed():
	Client.disconnect("map_found", self, "_on_map_found")
	var scene = GlobalVariables.loader.get_resource("res://Wait/SearchForOpponent.tscn").instance()
	for i in range(len(GlobalVariables.player.tanks)):
		if GlobalVariables.player.tanks[i].id == sel_id:
			scene.level = GlobalVariables.player.tanks[i].level
	scene.tank = GlobalVariables.get_tank_by_id(sel_id)
	scene.scene = self
	scene.sel_id = sel_id
	call_deferred("set_new_scene", scene)

func _on_Common_gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			Client.buy_daily_item(0)

func _on_Rare_gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			Client.buy_daily_item(1)

func _on_Epic_gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			Client.buy_daily_item(2)

func _on_Mythical_gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			Client.buy_daily_item(3)
