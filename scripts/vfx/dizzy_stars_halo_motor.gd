extends Node3D

# Preload our source single star mesh asset blueprint cleanly
const STAR_MESH_BLUEPRINT: PackedScene = preload("res://scenes/vfx/dizzy_star_mesh.tscn")

@export var orbital_radius: float = 0.42     # Horizontal distance from his helmet center point
@export var rotation_speed: float = 5.8      # How fast the stars sprint around his head
@export var total_stars_count: int = 4       # Number of stars arranged in the ring
@export var vertical_wobble_speed: float = 4.0 # How fast they wave up and down
@export var wobble_amplitude: float = 0.06   # Height thickness of the wavy float movement

var active_running_time: float = 0.0
var tracking_spawned_stars_list: Array[Node3D] = []

func _ready() -> void:
	# Hide the system by default until the guard slips and face-plants
	visible = false
	_instantiate_and_arrange_orbital_ring()

func _process(delta: float) -> void:
	if not visible: return
	
	active_running_time += delta
	
	# 1. SPIN LOOP MOTOR: Continuously swivels the entire parent halo container row!
	global_rotation.y += rotation_speed * delta
	
	# 2. DYNAMIC WOBBLE PIPELINE: Moves each individual star along a smooth sine wave
	# This creates that high-fidelity cartoon wobble effect where they offset vertically as they pass!
	for i in range(tracking_spawned_stars_list.size()):
		var star_instance = tracking_spawned_stars_list[i]
		if is_instance_valid(star_instance):
			# Offsetting the wave based on the index ensures they don't move up and down together stiffly!
			var individual_wave_phase_shift: float = (i * (PI * 2.0 / total_stars_count))
			var wave_height_offset: float = sin((active_running_time * vertical_wobble_speed) + individual_wave_phase_shift) * wobble_amplitude
			
			# Re-align local coordinates
			star_instance.position.y = wave_height_offset
			# Self-spin the star mesh on its own axis to catch specular highlights!
			star_instance.rotation.y += 2.0 * delta

func start_dizzy_halo_sequence() -> void:
	# Reset system visibility transformations instantly on launch
	visible = true
	scale = Vector3(1.0, 1.0, 1.0)
	active_running_time = 0.0
	
	# AAA VISUAL POP IN TWEEN: Make the ring expand outward dynamically on frame one!
	var entrance_swell = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	var _baseline_target_radius: float = orbital_radius
	
	# Start collapsed tight at zero, then expand the orbital ring outward beautifully over 0.4 seconds!
	for i in range(tracking_spawned_stars_list.size()):
		var star = tracking_spawned_stars_list[i]
		if is_instance_valid(star):
			star.scale = Vector3.ZERO
			entrance_swell.parallel().tween_property(star, "scale", Vector3(1.0, 1.0, 1.0), 0.4)

func stop_dizzy_halo_sequence() -> void:
	# Smoothly shrink the ring into nothingness when he recovers and stands back up
	var exit_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	exit_tween.tween_property(self, "scale", Vector3.ZERO, 0.35)
	exit_tween.tween_callback(func(): visible = false)

func _instantiate_and_arrange_orbital_ring() -> void:
	# Clean out any pre-existing zombie node remnants safely
	for star in tracking_spawned_stars_list:
		if is_instance_valid(star): star.queue_free()
	tracking_spawned_stars_list.clear()
	
	# === 3D GEOMETRIC ARRANGEMENT MATRIX ===
	# Math formulas calculate equal circle spacing coordinates based on total star count counts!
	for i in range(total_stars_count):
		var target_star_node_instance = STAR_MESH_BLUEPRINT.instantiate() as Node3D
		add_child(target_star_node_instance)
		
		# Divide a 360-degree radian slice symmetrically across our index positions
		var slice_angle: float = i * (PI * 2.0 / total_stars_count)
		
		# Plot horizontal circumference coordinates along X and Z axes
		var local_spawn_x: float = cos(slice_angle) * orbital_radius
		var local_spawn_z: float = sin(slice_angle) * orbital_radius
		
		target_star_node_instance.position = Vector3(local_spawn_x, 0.0, local_spawn_z)
		tracking_spawned_stars_list.append(target_star_node_instance)
