extends TextureRect

var pos
func _ready():
	self.rect_scale = Vector2.ZERO
	pos = self.rect_position
	pass


func _process(delta):
	if self.visible && self.rect_scale != Vector2.ONE:
		self.rect_scale += Vector2(delta / 0.3, delta / 0.3)
		if self.rect_scale > Vector2.ONE:
			self.rect_scale = Vector2.ONE
			get_node("../../Area2D").visible = true
		self.rect_position = pos + (Vector2.ONE - self.rect_scale) * self.rect_size / 2
