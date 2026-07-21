extends RigidBody3D

@export var distraction_radius: float = 8.0
@export var max_bounces_allowed: int = 3
@export var acoustic_ripple_scene: PackedScene = preload("res://scenes/acoustic_ripple.tscn")

var current_bounce_count: int = 0

func _ready() -> void:
	# =============================================================================
	#     1. CINEMATIC HTTYD PHYSICS WEIGHT ARCHITECTURE
	# =============================================================================
	# Keep gravity consistent and snappy so it arcs gracefully through the air
	gravity_scale = 1.3
	
	# AERODYNAMIC FLIGHT: Zero out dampening constants completely to prevent mid air slowdowns!
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.05                     # Minimal aerodynamic friction drag
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4                     # Let the stone spin dynamically while flying
	
	# Create a clean, crisp, bouncy tactile material override
	var material_override = PhysicsMaterial.new()
	material_override.friction = 0.45       # Allows it to roll slightly after its final hop
	material_override.bounce = 0.55         # Elastic return makes it spring away from masonry walls!
	physics_material_override = material_override

	# Enable internal contact monitoring so the stone actively registers floor hits!
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_impact_registered)

func _on_impact_registered(body: Node) -> void:
	if body.name == "Player" or body.name == "Smudge" or body.is_in_group("PlayerGroup"): 
		return
		
	current_bounce_count += 1
	var impact_location: Vector3 = global_position
	
	# =============================================================================
	#     2. CINEMATIC FLOAT SLOW-MOTION JUMP MATRIX
	# =============================================================================
	if current_bounce_count < max_bounces_allowed:
		# Keep gravity natural (1.3) instead of floating down like slow motion!
		gravity_scale = 1.3
		
		# Inject a gentle, decaying vertical pop upward on each surface strike
		var movie_hop_force: float = 2.4 / float(current_bounce_count)
		apply_central_impulse(Vector3(0.0, movie_hop_force, 0.0))
		
		# Add a minor torque kick to make the tumble look hand animated
		apply_torque_impulse(Vector3(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8), randf_range(-0.8, 0.8)))
	else:
		# TERMINAL SETTLING: Instantly choke sliding matrices the moment it hits its final hop limit
		linear_damp = 8.0                  # Stops sliding skates across floor tiles
		angular_damp = 18.0                # Halts the tumbling spin loop
		
		# Let the pebble rest visibly on the ground geometry for a moment before deletion
		get_tree().create_timer(0.5).timeout.connect(queue_free)

	# =============================================================================
	#     3. ACOUSTIC RADAR RIPPLES & SIGNAL BUS EXECUTIONS [PDF: 0.1.61]
	# =============================================================================
	if is_instance_valid(acoustic_ripple_scene):
		var ripple_instance = acoustic_ripple_scene.instantiate() as Node3D
		get_tree().root.add_child(ripple_instance)
		ripple_instance.global_position = impact_location + Vector3(0.0, 0.01, 0.0)
		
		var ripple_tween = create_tween()
		ripple_instance.scale = Vector3.ZERO
		ripple_tween.tween_property(ripple_instance, "scale", Vector3(distraction_radius, 1.0, distraction_radius), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ripple_tween.tween_callback(ripple_instance.queue_free)

	# Global signal autoload EventBus alerts for guard AI nodes
	if is_instance_valid(EventBus) and EventBus.has_signal("distraction_sound_emitted"):
		EventBus.distraction_sound_emitted.emit(impact_location, distraction_radius)
		
	var guards_list = get_tree().get_nodes_in_group("EnemyGroup")
	for guard in guards_list:
		if is_instance_valid(guard) and guard.has_method("investigate_noise_location"):
			if impact_location.distance_to(guard.global_position) <= distraction_radius:
				guard.investigate_noise_location(impact_location)
