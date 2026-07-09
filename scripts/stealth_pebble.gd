extends RigidBody3D

@export var distraction_radius: float = 4.5

func _ready() -> void:
	# Natively bind the body entry collision signal loop
	body_entered.connect(_on_impact_registered)

func _on_impact_registered(body: Node) -> void:
	# 1. THE SAFETY GUARD: Move this to the ABSOLUTE top of the function!
	# If the pebble clips Eira or Smudge on spawn, discard it instantly and exit.
	if body.name == "Player" or body.name == "Smudge": 
		return
		
	print("PEBBLE IMPACT: Clattered against ", body.name, "! Broadcasting sound wave...")
	
	# 2. CACHE POSITION LAYER
	var impact_location: Vector3 = global_position
	
	# 3. INSTANTIATE THE TACTICAL AUDIO RADAR RING
	var ring_blueprint = load("res://scenes/hearing_radius_ring.tscn")
	if ring_blueprint:
		var ring_instance = ring_blueprint.instantiate()
		get_tree().root.add_child(ring_instance)
		ring_instance.global_position = impact_location + Vector3(0.0, 0.01, 0.0)
		if ring_instance.has_method("initialize_hearing_expansion"):
			ring_instance.initialize_hearing_expansion(distraction_radius)
	
	# THE RECONCILIATION FIX: Cache the raw global coordinates into a local vector variable!
	# This safely reads the position *before* the node's tree transform link is broken.
	
	# 1. THE VISUAL WAVE BLOOM
	var ripple_blueprint = load("res://scenes/acoustic_ripple.tscn")
	if ripple_blueprint:
		var ripple_instance = ripple_blueprint.instantiate() as MeshInstance3D
		
		# SAFE SEQUENCE: Add the child to the scene tree root FIRST...
		get_tree().root.add_child(ripple_instance)
		
		# ...and NOW it is completely safe to assign its 3D global position vectors!
		ripple_instance.global_position = impact_location
		ripple_instance.global_position.y += 0.01 
		
	# 2. THE STEALTH AUDIO BROADCAST RADAR
	var all_hunters = get_tree().get_nodes_in_group("EnemyGroup")
	for hunter in all_hunters:
		if is_instance_valid(hunter) and hunter.has_method("investigate_noise"):
			var distance_to_hunter: float = impact_location.distance_to(hunter.global_position)
			
			if distance_to_hunter <= distraction_radius:
				hunter.investigate_noise(impact_location)
				
	# Cleanly erase the projectile tracking data from physics memory layers
	queue_free()
	
