extends Node3D

signal aim_updated(direction: Vector3)

@export var player_reference: CharacterBody3D
@export var eira_body_mesh: MeshInstance3D

var aim_direction: Vector3 = Vector3.FORWARD
var target_rotation_y: float = 0.0

# SECURE HARDWARE SEPARATION CACHE PROPERTIES
var last_mouse_position: Vector2 = Vector2.ZERO
var active_input_mode_flag: String = "MOUSE" 

func _input(event: InputEvent) -> void:
	# CATCH HARDWARE SWAPS INSTANTLY: Forcefully isolate device tracks [PDF: 0.1.60]
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var current_mouse_pos: Vector2 = get_viewport().get_mouse_position()
		if current_mouse_pos.distance_squared_to(last_mouse_position) > 1.5:
			active_input_mode_flag = "MOUSE"
			last_mouse_position = current_mouse_pos
	elif event is InputEventJoypadButton:
		active_input_mode_flag = "GAMEPAD"
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.15:
		active_input_mode_flag = "GAMEPAD"

func process_aim_logic(is_aiming: bool, _charge_timer: float, delta: float) -> void:
	if not is_instance_valid(player_reference): return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return

	# 1. READ RAW HARDWARE SIGNAL CHANNELS BY EDITOR ACTION STRINGS [PDF: 0.1.26]
	var look_axis: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	
	var left_trigger_pressure: float = Input.get_action_strength("shield_parry")
	var right_trigger_pressure: float = Input.get_action_strength("extend_range")
	
	# Industry-standard 20% hardware deadzone filters mask rest variance noise [PDF: 0.1.26]
	var is_right_stick_moving: bool = look_axis.length() > 0.20
	var is_trigger_partially_squeezed: bool = (left_trigger_pressure > 0.15) or (right_trigger_pressure > 0.15)
	
	var current_mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var has_mouse_physically_moved: bool = current_mouse_pos.distance_squared_to(last_mouse_position) > 1.5

	# 2. DEVICE MASTER INPUT MODE LOG LOCK
	if is_right_stick_moving or is_trigger_partially_squeezed:
		active_input_mode_flag = "GAMEPAD"
	elif has_mouse_physically_moved or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		active_input_mode_flag = "MOUSE"
		last_mouse_position = current_mouse_pos
		
	# FIXED HANDSHAKE DECAY: Symmetrically clear her master focus back to mouse if pad is completely idle
	if not is_aiming and not is_right_stick_moving and not is_trigger_partially_squeezed:
		active_input_mode_flag = "MOUSE"
		player_reference.is_controller_actively_aiming = false

	# 3. ROUTE COMPONENT COORDINATES SEPARATELY BASED ON Focus DEVICE [PDF: 0.1.26]
	if active_input_mode_flag == "GAMEPAD":
		player_reference.is_controller_actively_aiming = true
		
		# THE STYLIZED TRIGGER DISTANCE MODIFIER ENGINE: Squeezing RT extends path, LT shrinks it! [PDF: 0.1.27]
		if is_aiming and is_trigger_partially_squeezed:
			var trigger_scaling_velocity: float = 14.0
			var distance_delta_offset: float = (right_trigger_pressure - left_trigger_pressure) * trigger_scaling_velocity * delta
			player_reference.master_tactical_lob_distance = clampf(
				player_reference.master_tactical_lob_distance + distance_delta_offset, 
				1.5, 
				14.0
			)
		
		# Right stick handles horizontal 360-degree look rotation exclusively, ignoring vertical drift! [PDF: 0.1.27]
		if is_right_stick_moving:
			var cam_basis: Basis = camera.global_transform.basis
			var right_dir: Vector3 = cam_basis.x
			var forward_dir: Vector3 = cam_basis.z
			right_dir.y = 0.0
			forward_dir.y = 0.0
			
			var target_aim_vector = (right_dir.normalized() * look_axis.x + forward_dir.normalized() * look_axis.y).normalized()
			if target_aim_vector.length_squared() > 0.01:
				aim_direction = target_aim_vector
				player_reference.controller_aim_direction = aim_direction
	else:
		player_reference.is_controller_actively_aiming = false
		
		var ray_origin: Vector3 = camera.project_ray_origin(current_mouse_pos)
		var ray_normal: Vector3 = camera.project_ray_normal(current_mouse_pos)
		var ray_end = ray_origin + (ray_normal * 100.0)
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.exclude = [player_reference.get_rid()]
		
		var result = space_state.intersect_ray(query)
		if not result.is_empty():
			var hit_pos: Vector3 = result["position"]
			var diff: Vector3 = hit_pos - player_reference.global_position
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				aim_direction = diff.normalized()

	# 4. FIXED MESH Posture ORIENTATION BASIS TRANSFORMS [PDF: 0.1.27, 0.1.28]
	if is_aiming:
		if aim_direction.length_squared() > 0.01:
			target_rotation_y = atan2(-aim_direction.x, -aim_direction.z)
			player_reference.rotation.y = lerp_angle(player_reference.rotation.y, target_rotation_y, 14.0 * delta)
			
			if is_instance_valid(eira_body_mesh):
				# Generate a clean, orthogonal orientation matrix to flip her face forward!
				var secure_basis = Basis()
				secure_basis.z = -aim_direction.normalized() 
				secure_basis.x = Vector3.UP.cross(secure_basis.z).normalized()
				secure_basis.y = secure_basis.z.cross(secure_basis.x).normalized()
				
				var normalized_target_basis: Basis = secure_basis.orthonormalized()
				var normalized_current_basis: Basis = eira_body_mesh.global_transform.basis.orthonormalized()
				
				eira_body_mesh.global_transform.basis = normalized_current_basis.slerp(normalized_target_basis, 14.0 * delta)
			
	aim_updated.emit(aim_direction)
