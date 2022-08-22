extends Control

export var hit := false

func _ready():
	if !hit:
		$Explosion.play("Explosion")
	else:
		$Explosion.play("ExplosionHit")

func _on_Explosion_animation_finished():
	queue_free()
