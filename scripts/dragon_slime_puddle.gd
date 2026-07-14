extends Area3D

@export var puddle_lifetime: float = 8.0
var has_tripped_an_enemy: bool = false # SINGLE-TARGET SHUTTER GATE

func _ready() -> void:
	body_entered.connect(_on_entity_stepped_in)
	body_exited.connect(_on_entity_exited)
	
	scale = Vector3(1.0, 1.0, 1.0)
	
	var puddle_decal = get_node_or_null("Decal")
	if is_instance_valid(puddle_decal):
		var target_size: Vector3 = puddle_decal.size
		puddle_decal.size = Vector3(0.05, target_size.y, 0.05)
		
		var growth_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		growth_tween.tween_property(puddle_decal, "size", target_size, 0.35)
		
		get_tree().create_timer(puddle_lifetime).timeout.connect(func():
			if is_instance_valid(puddle_decal):
				var fade_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
				fade_tween.tween_property(puddle_decal, "size", Vector3(0.01, target_size.y, 0.01), 0.5)
				fade_tween.tween_callback(queue_free)
		)
	else:
		get_tree().create_timer(puddle_lifetime).timeout.connect(queue_free)

func _on_entity_stepped_in(body: Node) -> void:
	if has_tripped_an_enemy: return
	
	if body.is_in_group("EnemyGroup"):
		if body.has_method("execute_cascade_stumble_fall"):
			# Lock the puddle to this single target instantly
			has_tripped_an_enemy = true
			print("SLIME PIPELINE: Locked onto single target: ", body.name, ". Shutting out all other duplicates.")
			
			body.execute_cascade_stumble_fall()
			
			# Accelerate the puddle decay so it dissolves shortly after doing its job
			var puddle_decal = get_node_or_null("Decal")
			if is_instance_valid(puddle_decal):
				var consume_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
				consume_tween.tween_property(puddle_decal, "size", Vector3(0.01, puddle_decal.size.y, 0.01), 2.0)
				consume_tween.tween_callback(queue_free)

func _on_entity_exited(_body: Node) -> void:
	pass
