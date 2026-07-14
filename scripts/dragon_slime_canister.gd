extends RigidBody3D

# Preload the puddle scene layout so the canister can dynamically spawn it on impact
const PUDDLE_SCENE: PackedScene = preload("res://scenes/dragon_slime_puddle.tscn")

func _ready() -> void:
	# Enable contact monitoring so the rigid body can throw collision signals instantly
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_impact_registered)

func throw_canister(direction_vector: Vector3, impulse_force: float) -> void:
	# Add a slight upward angle lift for a beautiful physics toss trajectory path arc
	var lift_vector: Vector3 = (direction_vector + Vector3(0.0, 0.25, 0.0)).normalized()
	apply_central_impulse(lift_vector * impulse_force)

func _on_impact_registered(body: Node) -> void:
	# 1. SAFETY GATE: Avoid clipping her own bounding capsule frames on launch
	if body == self or body.is_in_group("PlayerGroup") or body.name == "Player": 
		return
		
	# === THE DET == 0 FIX: DE-ACTIVATE ALL PHYSICS MATRIX TRACKERS IMMEDIATELY ===
	# Turning off contact monitoring and collision shapes stops the physics engine from 
	# trying to calculate overlapping matrices with your newly spawned puddle cylinder shape!
	call_deferred("set_contact_monitor", false)
	max_contacts_reported = 0
	
	# If you have a collision shape node named CollisionShape3D, disable it right here:
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)
	
	# 2. SPAWN THE INTERACTIVE HAZARD PUDDLE
	var puddle_instance = PUDDLE_SCENE.instantiate() as Area3D
	get_tree().current_scene.add_child(puddle_instance)
	puddle_instance.global_position = global_position + Vector3(0.0, 0.05, 0.0)
	
	print("SLIME PIPELINE: Canister deactivated safely. Deploying fluid puddle decal!")
	
	# 3. Clean up the node safely at the end of the frame tick
	queue_free()
