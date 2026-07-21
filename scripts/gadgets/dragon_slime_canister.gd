extends RigidBody3D

const PUDDLE_SCENE: PackedScene = preload("res://scenes/gadgets/dragon_slime_puddle.tscn")

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_impact_registered)

func throw_canister(direction_vector: Vector3, impulse_force: float) -> void:
	var lift_vector: Vector3 = (direction_vector + Vector3(0.0, 0.25, 0.0)).normalized()
	apply_central_impulse(lift_vector * impulse_force)

func _on_impact_registered(body: Node) -> void:
	if body == self or body.is_in_group("PlayerGroup") or body.name == "Player":
		return
		
	# === THE DET == 0 FIX: SAFELY FLUSH RIGID MATRIX COLLIDERS [PDF: 0.1.8] ===
	call_deferred("set_contact_monitor", false)
	max_contacts_reported = 0
	
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)
		
	# 2. SPAWN THE HAZARD ZONE AREA TRAP [PDF: 0.1.9]
	var puddle_instance = PUDDLE_SCENE.instantiate() as Area3D
	get_tree().current_scene.add_child(puddle_instance)
	puddle_instance.global_position = global_position + Vector3(0.0, 0.05, 0.0)
	
	print("SLIME PIPELINE: Canister broken cleanly. Materializing puddle hazard.")
	queue_free()
