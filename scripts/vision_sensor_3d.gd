extends Node3D
class_name VisionSensor3D

signal player_detected(suspicion: float)
signal player_lost()

@export var vision_range: float = 9.0
@export var vision_angle: float = 45.0 # Half-FOV radius angle
@export var suspicion_build_speed: float = 85.0
@export var suspicion_decay_speed: float = 65.0

var player_ref: CharacterBody3D = null
var current_suspicion: float = 0.0

func _ready() -> void:
	player_ref = get_tree().get_first_node_in_group("PlayerGroup") as CharacterBody3D

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("PlayerGroup") as CharacterBody3D
		return
		
	var is_player_tracked: bool = false
	
	# FOLIAGE/STEALTH SAFETY GATES
	if "is_player_currently_visible" in player_ref and not player_ref.is_player_currently_visible:
		decay_suspicion(delta)
		return

	var distance_to_player = global_position.distance_to(player_ref.global_position)
	
	if distance_to_player <= vision_range:
		var forward_heading: Vector3 = -global_transform.basis.z.normalized()
		var vector_to_player: Vector3 = (player_ref.global_position - global_position).normalized()
		
		# RADAR DOT PRODUCT CALCULATION
		var angle_dot = forward_heading.dot(vector_to_player)
		var actual_angle = rad_to_deg(acos(clampf(angle_dot, -1.0, 1.0)))
		
		if actual_angle <= vision_angle:
			var space_state = get_world_3d().direct_space_state
			var ray_query = PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.5, 0.0), player_ref.global_position + Vector3(0.0, 0.5, 0.0))
			ray_query.exclude = [get_parent().get_rid()]
			
			var ray_hit = space_state.intersect_ray(ray_query)
			if ray_hit.is_empty() or ray_hit["collider"] == player_ref:
				is_player_tracked = true

	if is_player_tracked:
		var closeness = remap(clampf(distance_to_player, 0.1, vision_range), 0.0, vision_range, 2.2, 0.7)
		current_suspicion = move_toward(current_suspicion, 100.0, suspicion_build_speed * closeness * delta)
		player_detected.emit(current_suspicion)
	else:
		decay_suspicion(delta)

func decay_suspicion(delta: float) -> void:
	current_suspicion = move_toward(current_suspicion, 0.0, suspicion_decay_speed * delta)
	if current_suspicion <= 0.01:
		player_lost.emit()
	else:
		player_detected.emit(current_suspicion)
