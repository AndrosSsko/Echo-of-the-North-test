extends Node3D
class_name InventoryGadgetManager

# === GLOBAL ABSTRACTION PROPERTIES ===
var current_ammo_deck_record: Dictionary = {
	"Pebble": 99,         
	"Bola": 3,           
	"Dragon Slime": 4,    
	"Trip Wire": 0,       
	"Spine Bomb": 0,      
	"Launcher": 0         
}

var bola_charge_timer: float = 0.0
const BOLA_MAX_CHARGE_TIME: float = 1.5 
var is_gadget_on_cooldown: bool = false

# Component links that we will hook up from the parent player node
var player: CharacterBody3D = null
var camera: Camera3D = null
var indicator_rig: Node3D = null

func initialize_manager(parent_player: CharacterBody3D) -> void:
	player = parent_player
	camera = get_viewport().get_camera_3d() if get_viewport() else null
	indicator_rig = player.get_node_or_null("EiraVisualCapsuleMesh/AimIndicators")

func process_aiming_logic(delta: float, is_aiming: bool, current_slot_index: int, deck: Array) -> void:
	if not is_aiming or deck.is_empty() or current_slot_index >= deck.size():
		bola_charge_timer = 0.0
		return
		
	var active_card = deck[current_slot_index]
	if not is_instance_valid(active_card) or not is_instance_valid(indicator_rig) or not is_instance_valid(player): return
	
	if active_card.display_name == "Bola":
		bola_charge_timer += delta
		var charge_ratio: float = clampf(bola_charge_timer / BOLA_MAX_CHARGE_TIME, 0.0, 1.0)
		var flat_pointer = indicator_rig.get_node_or_null("Aim_Line_Pointer")
		
		if is_instance_valid(flat_pointer) and flat_pointer.visible:
			var blender_mesh = flat_pointer.get_node_or_null("Line_Visual") as Node3D
			if is_instance_valid(blender_mesh):
				var base_range: float = 2.5
				var max_charge_range: float = 15.0
				var max_laser_range: float = lerpf(base_range, max_charge_range, charge_ratio)
				var width_grow: float = lerpf(0.5, 1.3, charge_ratio)
				
				# Get active tracking direction from the player's primary transform orientation
				var aim_dir = -player.global_transform.basis.z.normalized()
				if player.get("is_controller_actively_aiming") and player.get("controller_aim_direction").length_squared() > 0.01:
					aim_dir = player.controller_aim_direction.normalized()
				
				# Mirror the physical raycast constraints inside component ticks
				var space_state = player.get_world_3d().direct_space_state
				var laser_start = player.global_position + Vector3(0.0, 0.8, 0.0)
				var laser_end = laser_start + aim_dir * max_laser_range
				
				var ray_param = PhysicsRayQueryParameters3D.create(laser_start, laser_end)
				ray_param.exclude = [player.get_rid()]
				var ray_result = space_state.intersect_ray(ray_param)
				
				var actual_laser_length = max_laser_range
				if not ray_result.is_empty():
					actual_laser_length = laser_start.distance_to(ray_result["position"])
				
				# Drive transform metrics cleanly
				blender_mesh.scale.y = actual_laser_length
				blender_mesh.scale.x = width_grow
				blender_mesh.scale.z = width_grow
				
				var dynamic_spin_speed: float = lerpf(1.5, 7.0, charge_ratio)
				blender_mesh.rotate_z(dynamic_spin_speed * delta)
				
				blender_mesh.global_position = laser_start + (aim_dir * (actual_laser_length / 2.0))
				
				var target_basis = Basis()
				target_basis.z = aim_dir
				target_basis.x = Vector3.UP.cross(target_basis.z).normalized()
				target_basis.y = target_basis.z.cross(target_basis.x).normalized()
				blender_mesh.global_transform.basis = target_basis

func execute_fire(current_slot_index: int, deck: Array) -> void:
	if is_gadget_on_cooldown or deck.is_empty() or current_slot_index >= deck.size(): return
	var active_card = deck[current_slot_index]
	if not is_instance_valid(active_card) or not is_instance_valid(active_card.projectile_scene_file): return
	
	if current_ammo_deck_record.has(active_card.display_name) and current_ammo_deck_record[active_card.display_name] <= 0:
		print("GADGET ENGINE: Out of ammunition for ", active_card.display_name)
		return

	is_gadget_on_cooldown = true
	get_tree().create_timer(0.4).timeout.connect(func(): is_gadget_on_cooldown = false)

	var charge_ratio: float = clampf(bola_charge_timer / BOLA_MAX_CHARGE_TIME, 0.0, 1.0)
	
	var throw_direction: Vector3 = -player.global_transform.basis.z.normalized()
	if player.get("is_controller_actively_aiming") and player.get("controller_aim_direction").length_squared() > 0.01:
		throw_direction = player.controller_aim_direction.normalized()
	elif is_instance_valid(camera):
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
		var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)
		var ground_plane = Plane(Vector3.UP, player.global_position.y)
		var target_mouse_world_point = ground_plane.intersects_ray(ray_origin, ray_normal)
		if target_mouse_world_point:
			var distance_vector: Vector3 = target_mouse_world_point - player.global_position
			distance_vector.y = 0.0
			if distance_vector.length() > 0.1:
				throw_direction = distance_vector.normalized()

	throw_direction.y = 0.0
	throw_direction = throw_direction.normalized()
	
	# === FIXED PEBBLE OVERTHROW DISTANCE BUG ===
	# Pebbles should throw at a constant, realistic velocity impulse. 
	# Only the Bola reads your variable wind charge timings!
	var dynamic_speed_impulse: float = active_card.throw_impulse
	if active_card.display_name == "Bola":
		dynamic_speed_impulse = active_card.throw_impulse * lerpf(0.7, 1.6, charge_ratio)

	var object_instance = active_card.projectile_scene_file.instantiate()
	get_tree().current_scene.add_child(object_instance)
	object_instance.global_position = player.global_position + Vector3(0.0, 0.8, 0.0) + (throw_direction * 0.6)
	
	if object_instance.has_method("add_collision_exception_with"):
		object_instance.add_collision_exception_with(player)

	if active_card.project_parabolic_lob_arc:
		# Balanced parabolic calculation matrix prevents crazy sky launches
		var _gravity_accel: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		var raw_launch_velocity: Vector3 = (throw_direction + Vector3(0.0, 0.40, 0.0)).normalized() * dynamic_speed_impulse
		if object_instance.has_method("apply_central_impulse"):
			object_instance.apply_central_impulse(raw_launch_velocity)
	else:
		if object_instance.has_method("initialize_bola_flight"):
			object_instance.initialize_bola_flight(throw_direction, dynamic_speed_impulse)
		if "charge_level" in object_instance:
			object_instance.charge_level = charge_ratio

	current_ammo_deck_record[active_card.display_name] -= 1
	bola_charge_timer = 0.0
	player.update_physical_belt_mesh_visibility()
	player.update_ammo_hud_display()
