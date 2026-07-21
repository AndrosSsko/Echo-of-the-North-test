extends RigidBody3D

@export var spike_projectile_blueprint: PackedScene = preload("res://scenes/gadgets/dragon_spine_spike.tscn")
@export var fuse_duration_timer: float = 2.2 # Explodes after roughly 2 seconds in flight

var is_already_detonated: bool = false

func _ready() -> void:
	is_already_detonated = false
	# Handle countdown timer loop
	get_tree().create_timer(fuse_duration_timer).timeout.connect(execute_shrapnel_burst)
	# Symmetrical fallback: Detonate instantly if it bounces hard onto the floor tiles
	body_entered.connect(func(_body): get_tree().create_timer(0.15).timeout.connect(execute_shrapnel_burst))

func execute_shrapnel_burst() -> void:
	if is_already_detonated: return
	is_already_detonated = true
	
	print("💥 BOMB IMPACT: Spring triggers released! Spikes expanding in all directions.")
	
	# =============================================================================
	#     3D SPHERICAL EXPLOSION FAN VECTOR DISTRIBUTOR
	# =============================================================================
	# Computes an even, symmetrical omni-directional burst layout grid around the core sphere
	var base_burst_directions: Array[Vector3] = [
		Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN,
		Vector3(1, 1, 1).normalized(), Vector3(-1, 1, 1).normalized(),
		Vector3(1, -1, 1).normalized(), Vector3(1, 1, -1).normalized(),
		Vector3(-1, -1, 1).normalized(), Vector3(-1, 1, -1).normalized(),
		Vector3(1, -1, -1).normalized(), Vector3(-1, -1, -1).normalized()
	]
	
	if spike_projectile_blueprint:
		for dir in base_burst_directions:
			var spike_instance = spike_projectile_blueprint.instantiate() as Node3D
			get_tree().current_scene.add_child(spike_instance)
			
			# Spawn the spike right at the center shell position and point its tips outward
			spike_instance.global_position = global_position
			spike_instance.set("move_direction", dir)
			spike_instance.look_at(global_position + dir, Vector3.UP)
			
	# Trigger a quick cloud dust particle ripple before freeing the core case mesh node
	queue_free()
