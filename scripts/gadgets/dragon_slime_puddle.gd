extends Area3D

@export var puddle_lifetime: float = 8.0
var has_tripped_an_enemy: bool = false # SINGLE-TARGET SHUTTER GATE [PDF: 0.1.6]

func _ready() -> void:
	body_entered.connect(_on_entity_stepped_in)
	body_exited.connect(_on_entity_exited)
	scale = Vector3(1.0, 1.0, 1.0)
	
	var puddle_decal = get_node_or_null("Decal")
	if is_instance_valid(puddle_decal):
		var target_size: Vector3 = puddle_decal.size
		puddle_decal.size = Vector3(0.05, target_size.y, 0.05)
		
		# Procedural puddle expansion tween on impact frame [PDF: 0.1.6]
		var growth_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		growth_tween.tween_property(puddle_decal, "size", target_size, 0.35)
		
		get_tree().create_timer(puddle_lifetime).timeout.connect(func():
			if is_instance_valid(puddle_decal):
				var fade_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
				var zero_size = Vector3(0.01, target_size.y, 0.01)
				fade_tween.tween_property(puddle_decal, "size", zero_size, 0.5)
				fade_tween.tween_callback(queue_free)
		)
	else:
		get_tree().create_timer(puddle_lifetime).timeout.connect(queue_free)

func _on_entity_stepped_in(body: Node) -> void:
	if has_tripped_an_enemy: return
	
	if body.is_in_group("EnemyGroup"):
		if body.has_method("execute_cascade_stumble_fall"):
			# Lock the puddle instance instantly to this specific guard capsule [PDF: 0.1.7]
			has_tripped_an_enemy = true
			print("SLIME PIPELINE: Hazard locked onto target: ", body.name)
			
			# Dispatch structural impact data safely via our EventBus system [PDF: 0.1.7]
			EventBus.gadget_impact.emit(1, body.global_position, 1.0)
			
			var puddle_decal = get_node_or_null("Decal")
			if is_instance_valid(puddle_decal):
				var consume_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
				var dissolve_size = Vector3(0.01, puddle_decal.size.y, 0.01)
				consume_tween.tween_property(puddle_decal, "size", dissolve_size, 2.0)
				consume_tween.tween_callback(queue_free)

func _on_entity_exited(_body: Node) -> void:
	pass
