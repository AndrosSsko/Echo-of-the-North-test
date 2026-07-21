extends CharacterBody3D


#     1. CORE DATA STRUCTURES & LOCOMOTION ENUMS

enum LocomotionState { STANDARD, SPRINTING, AIR_PREP, SLIDING, STOMP_EXIT, CROUCHING }
var current_locomotion_mode: LocomotionState = LocomotionState.STANDARD

enum GadgetType { BOLA, TRAP, PEBBLE, SLIME, BOMB, LAUNCHER }
const BOLA_MAX_CHARGE_TIME: float = 1.5

# Decoupled Inventory Configuration Resource Management Deck Cards [PDF: 0.1.36]
@export var equipped_gadgets_deck: Array[GadgetResource] = []
var current_selected_gadget_index: int = 2

var current_ammo_deck_record: Dictionary = {
	"Pebble": 99,       # Synced to resource card names
	"Bola": 3,
	"Dragon Slime": 4,
	"Tripwire Trap": 5, # Unlocks item slot launching cleanly
	"Spine Bomb": 3,
	"Launcher": 4
}

# Private Spatial Constant Offsets [PDF: 0.1.36]
const SHIELD_BACKPACK_POSITION: Vector3 = Vector3(-0.4, 0.2, 0.2)
const SHIELD_BACKPACK_ROTATION: Vector3 = Vector3(0.0, 0.0, 90.0)
const FLYING_SHIELD_SCENE = preload("res://scenes/flying_shield_fx.tscn")
const DRAGON_SLIME_CANISTER_SCENE = preload("res://scenes/gadgets/dragon_slime_canister.tscn")

var current_selected_index: int = 0


#     2. DESIGNER TUNING PANEL PROPERTIES (GODOT INSPECTOR)

@export_category("Tactile Hip Menu Tuning")
@export var mesh_menu_turn_speed: float = 11.0
@export var menu_camera_zoom_fov: float = 45.0

@export_category("Viking Locomotion Tuning")
@export var sprint_speed_multiplier: float = 1.55
@export var slide_impulse_velocity: float = 18.0
@export var slide_friction_decay: float = 4.5

@export_category("Shield Surf Tuning")
@export var base_slide_friction: float = 0.55
@export var slide_steer_speed: float = 4.2
@export var minimum_slide_boost: float = 14.5

@export_category("Movement Core")
@export var movement_speed: float = 7.0
@export var crouch_speed: float = 3.2
@export var climb_speed: float = 3.0
@export var acceleration: float = 15.0
@export var rotation_speed: float = 12.0

@export_category("Action Mechanics")
@export var dodge_speed: float = 16.0
@export var dodge_duration: float = 0.35
@export var dodge_cooldown: float = 0.5
@export var throw_impulse_force: float = 14.0

@export_category("Combat Matrix")
@export var attack_duration: float = 0.25
@export var attack_cooldown: float = 0.45
@export var attack_movement_dampening: float = 0.15

@export_category("Survival Vitality")
@export var maximum_health: int = 3

@export_category("Inventions Bag")
@export var max_bola_ammo: int = 3
@export var pebble_throw_cooldown: float = 0.8

@export_category("Survival Inventory Settings")
@export var trap_ammo: int = 2
@export var slime_ammo: int = 4
@export var bomb_ammo: int = 1


#     3. RUNTIME SCENE TREE CONNECTIONS (@ONREADY)

@onready var trap_rig: Node3D = $Trap_PCAM
@onready var slime_rig: Node3D = $Slime_PCAM
@onready var pebble_rig: Node3D = $Pebble_PCAM
@onready var bomb_rig: Node3D = $Bomb_PCAM

@onready var core_capsule_collision: CollisionShape3D = $CollisionShape3D
@onready var collision_standing: CollisionShape3D = $CollisionShape3D
@onready var collision_sliding: CollisionShape3D = $CollisionShape3D
@onready var player_collision: CollisionShape3D = $CollisionShape3D
@onready var ground_snapper: RayCast3D = $FloorRay
@onready var ammo_label: Label = $"../HUD/Ammo_Container/Ammo_Tracker"

@onready var heart_icons: Array = [
	get_tree().get_first_node_in_group("HUD_Root").get_node("Health_Container/Heart_01") if get_tree().get_first_node_in_group("HUD_Root") and get_tree().get_first_node_in_group("HUD_Root").has_node("Health_Container/Heart_01") else null,
	get_tree().get_first_node_in_group("HUD_Root").get_node("Health_Container/Heart_02") if get_tree().get_first_node_in_group("HUD_Root") and get_tree().get_first_node_in_group("HUD_Root").has_node("Health_Container/Heart_02") else null,
	get_tree().get_first_node_in_group("HUD_Root").get_node("Health_Container/Heart_03") if get_tree().get_first_node_in_group("HUD_Root") and get_tree().get_first_node_in_group("HUD_Root").has_node("Health_Container/Heart_03") else null
]

@onready var hip_ammo_rig: Node3D = $EiraVisualCapsuleMesh/Hip_Ammo_Rig
@onready var melee_hitbox: Area3D = $EiraVisualCapsuleMesh/Melee_Hitbox
@onready var hitbox_collision: CollisionShape3D = $EiraVisualCapsuleMesh/Melee_Hitbox/CollisionShape3D
@onready var player_mesh: MeshInstance3D = $EiraVisualCapsuleMesh
@onready var eira_body_mesh: MeshInstance3D = $EiraVisualCapsuleMesh
@onready var bola_mesh_01: Node3D = $EiraVisualCapsuleMesh/Hip_Ammo_Rig/Bola_Mesh_01
@onready var bola_mesh_02: Node3D = $EiraVisualCapsuleMesh/Hip_Ammo_Rig/Bola_Mesh_02
@onready var bola_mesh_03: Node3D = $EiraVisualCapsuleMesh/Hip_Ammo_Rig/Bola_Mesh_03
@onready var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null

@onready var left_hip_marker: Marker3D = $EiraVisualCapsuleMesh/LeftHipMarker
@onready var waist_left_marker: Marker3D = $EiraVisualCapsuleMesh/WaistLeftMarker
@onready var waist_center_marker: Marker3D = $EiraVisualCapsuleMesh/WaistCenterMarker
@onready var waist_right_marker: Marker3D = $EiraVisualCapsuleMesh/WaistRightMarker
@onready var right_hip_marker: Marker3D = $EiraVisualCapsuleMesh/RightHipMarker

@onready var exploration_pcam: Node = $Exploration_PCAM
@onready var bola_pcam: Node = $Bola_PCAM
@onready var trap_pcam: Node = $Trap_PCAM
@onready var slime_pcam: Node = $Slime_PCAM
@onready var pebble_pcam: Node = $Pebble_PCAM
@onready var bomb_pcam: Node = $Bomb_PCAM

@onready var placeholder_hand_rig: Node3D = $EiraVisualCapsuleMesh/Placeholder_Hand_Rig
@onready var indicator_rig: Node3D = $EiraVisualCapsuleMesh/AimIndicators
@onready var gadget_manager: InventoryGadgetManager = $GadgetManagerComponent


#     4. STATE MACHINE BOOLEANS & SYSTEM WATCH CLOCKS [PDF: 0.1.38]

var original_mesh_rotation_y: float = 0.0
var is_radial_menu_open: bool = false
var can_throw_pebble: bool = true
var current_bola_ammo: int = 3
var is_bola_on_fire_cooldown: bool = false
var was_crouching_on_attack: bool = false
var weapon_wheel_hold_timer: float = 0.0
var is_tracking_wheel_hold: bool = false
var radial_menu_active: bool = false
var carried_treasure_keys_count: int = 0
var camera_target_fov: float = 70.0
var pre_menu_selected_gadget: GadgetType = GadgetType.PEBBLE
var camera_target_offset: Vector3 = Vector3.ZERO
var has_player_scrolled_during_this_menu_session: bool = false
var camera_curve_timer: float = 0.0
var menu_highlighted_gadget: GadgetType = GadgetType.PEBBLE
var did_player_click_to_confirm_selection: bool = false
var is_actively_aiming_gadget: bool = false
var gadget_aim_hold_timer: float = 0.0
var controller_joystick_debounce: bool = false
var dragged_body: Node3D = null
var is_controller_actively_aiming: bool = false
var controller_aim_direction: Vector3 = Vector3.ZERO
var is_gadget_on_cooldown: bool = false
var current_selected_gadget: GadgetType = GadgetType.PEBBLE
var base_fov: float = 70.0 
var is_player_currently_visible: bool = true
var active_highlighted_gadget: GadgetType = GadgetType.PEBBLE
var bola_charge_timer: float = 0.0
var launcher_ammo: int = 0


@export var pebble_blueprint: PackedScene
@export var dust_blueprint: PackedScene
var active_wind_zone: Area3D = null


var is_parrying: bool = false
var is_rolling: bool = false
var is_attacking: bool = false
var is_crouching: bool = false
var is_climbing: bool = false 
var can_dodge: bool = true
var can_attack: bool = true
var current_health: int = 3
var roll_direction: Vector3 = Vector3.ZERO
var roll_timer: float = 0.0
var attack_timer: float = 0.0
var distance_traveled: float = 0.0
var step_interval: float = 1.8
var locked_climb_x: float = 0.0
var is_reading_chest_lore: bool = false
var active_chest_ref: Area3D = null
var is_menu_just_opened: bool = false
var master_tactical_lob_distance: float = 8.0

#     5. ENGINE READY INITIALIZATION

func _ready() -> void:
	radial_menu_active = false
	is_radial_menu_open = false
	is_actively_aiming_gadget = false
	is_controller_actively_aiming = false
	Engine.time_scale = 1.0
	add_to_group("PlayerGroup")
	current_health = maximum_health
	
	if is_instance_valid(hitbox_collision):
		hitbox_collision.disabled = true
	melee_hitbox.area_entered.connect(_on_melee_hit_registered)
	melee_hitbox.body_entered.connect(_on_melee_hit_registered)
	current_bola_ammo = max_bola_ammo
	update_ammo_hud_display()
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera_target_fov = 70.0
	camera_target_offset = Vector3.ZERO
	if is_instance_valid(melee_hitbox):
		melee_hitbox.hide()
	update_physical_belt_mesh_visibility()
	
	if is_instance_valid(exploration_pcam):
		exploration_pcam.priority = 30
	clear_all_gadget_camera_priorities()
	
	current_selected_gadget = GadgetType.PEBBLE
	menu_highlighted_gadget = GadgetType.PEBBLE
	active_highlighted_gadget = GadgetType.PEBBLE
	if has_node("CeilingCheck"):
		$CeilingCheck.add_exception(self)
		
	var start_back = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var start_hand = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	var start_feet = get_node_or_null("FeetMarker/FeetShieldMesh")
	if start_back: start_back.visible = true
	if start_hand: start_hand.visible = false
	if start_feet: start_feet.visible = false
	current_selected_gadget_index = 2
	if is_instance_valid(gadget_manager):
		gadget_manager.initialize_manager(self)

	
	master_tactical_lob_distance = 8.0

	if is_instance_valid(indicator_rig) and indicator_rig.has_node("Wall_Trap_Pointer"):
		var trap_pointer_node = indicator_rig.get_node("Wall_Trap_Pointer")
		if is_instance_valid(trap_pointer_node):
			# Handshake her root script address down to the pointer component memory
			trap_pointer_node.set("cached_master_player_ref", self)
			print("🪤 TRAP ENGINE: Handshake secured! Direct player reference cached into indicators.")



#     6. GLOBAL PHYSICS PROCESSING LOOP (_PHYSICS_PROCESS) [PDF: 0.1.40]
func _physics_process(delta: float) -> void:
	var _adjusted_delta: float = delta * (1.0 / Engine.time_scale) if radial_menu_active else delta
	var track_anchor_node = get_node_or_null("Camera_Track_Anchor")
	if is_instance_valid(track_anchor_node):
		if not radial_menu_active:
			track_anchor_node.global_transform.basis = global_transform.basis
		else:
			track_anchor_node.global_transform.basis = Basis.IDENTITY
			
	# FIXED MOVEMENT FREEZE FLUSH: Release keyboard input blocks if the weapon wheel window drops out!
	if radial_menu_active and is_radial_menu_open:
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * _adjusted_delta) 
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * _adjusted_delta) 
		move_and_slide() 
		evaluate_radial_wheel_joystick_navigation() 
		return 
	else:
		radial_menu_active = false

	if current_locomotion_mode == LocomotionState.AIR_PREP:
		var default_engine_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= default_engine_gravity * _adjusted_delta
	elif not is_on_floor():
		var default_engine_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= default_engine_gravity * _adjusted_delta
	else:
		velocity.y = -0.1 

	if is_actively_aiming_gadget:
		bola_charge_timer += _adjusted_delta

	if not is_instance_valid(camera): 
		camera = get_viewport().get_camera_3d() if get_viewport() else null

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length() < 0.1 and current_locomotion_mode == LocomotionState.SPRINTING:
		current_locomotion_mode = LocomotionState.STANDARD

	if is_climbing:
		process_climbing_movement(input_vector, _adjusted_delta)
		move_and_slide()
		return

	var _direction: Vector3 = Vector3.ZERO 
	if is_instance_valid(camera): 
		var camera_transform: Transform3D = camera.global_transform 
		var forward_direction: Vector3 = camera_transform.basis.z 
		var right_direction: Vector3 = camera_transform.basis.x 
		forward_direction.y = 0.0 
		right_direction.y = 0.0 
		forward_direction = forward_direction.normalized() 
		right_direction = right_direction.normalized()
		_direction = (right_direction * input_vector.x) + (forward_direction * input_vector.y)

	var is_sprint_button_held: bool = Input.is_action_pressed("sprint")
	if current_locomotion_mode == LocomotionState.STANDARD or current_locomotion_mode == LocomotionState.SPRINTING or current_locomotion_mode == LocomotionState.CROUCHING:
		if is_crouching or current_locomotion_mode == LocomotionState.CROUCHING:
			current_locomotion_mode = LocomotionState.CROUCHING
		else:
			if is_sprint_button_held and input_vector.length_squared() > 0.01:
				current_locomotion_mode = LocomotionState.SPRINTING
			else:
				current_locomotion_mode = LocomotionState.STANDARD

	match current_locomotion_mode:
		LocomotionState.SLIDING:
			var horizontal_speed := Vector3(velocity.x, 0, velocity.z).length()
			camera_target_fov = remap(clampf(horizontal_speed, 0.0, 25.0), 0.0, 25.0, base_fov, 88.0)
			camera.rotation.z = lerp_angle(camera.rotation.z, input_vector.x * deg_to_rad(-2.5), 6.0 * _adjusted_delta)
		LocomotionState.SPRINTING:
			camera_target_fov = base_fov + 4.0
			camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, 8.0 * _adjusted_delta)
		_:
			camera_target_fov = base_fov
			camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, 8.0 * _adjusted_delta)
			
	if is_instance_valid(camera):
		camera.fov = lerp(camera.fov, camera_target_fov, 10.0 * _adjusted_delta)

	match current_locomotion_mode:
		LocomotionState.AIR_PREP:
			move_and_slide()
			if velocity.y <= 0.0 and is_on_floor(): 
				enter_sliding_state()
			return
		LocomotionState.SLIDING:
			if not is_on_floor() and velocity.y < -6.0:
				enter_stomp_exit_state()
				return
			process_sliding_movement(_adjusted_delta)
			return
		LocomotionState.STOMP_EXIT:
			current_locomotion_mode = LocomotionState.STANDARD
		LocomotionState.CROUCHING:
			is_crouching = true
			if current_locomotion_mode == LocomotionState.SLIDING:
				process_sliding_movement(_adjusted_delta)
			elif current_locomotion_mode == LocomotionState.AIR_PREP:
				pass
			elif is_rolling:
				process_active_roll(_adjusted_delta)
			if is_attacking:
				process_active_attack(_direction, _adjusted_delta)
			else:
				# === FIXED TRAVERSAL OVERRIDE: FREEZE LOCOMOTION WHILE CLIMBING ===
				# This stops gravity and friction vectors from dragging her down while pulling up!
				if is_climbing:
					return # Hand control over completely to our smooth procedural interpolation tween!
				process_standard_movement(_direction, _adjusted_delta)
			move_and_slide()

	if current_locomotion_mode == LocomotionState.SLIDING:
		process_sliding_movement(_adjusted_delta)
	elif current_locomotion_mode == LocomotionState.AIR_PREP:
		pass 
	elif is_rolling:
		process_active_roll(_adjusted_delta)
	elif is_attacking:
		process_active_attack(_direction, _adjusted_delta) 
	else:
		process_standard_movement(_direction, _adjusted_delta) 
	move_and_slide()

	if Input.is_action_just_pressed("dodge_roll") and can_dodge and not is_rolling:
		initiate_dodge_roll(_direction)
	elif Input.is_action_just_pressed("attack_melee") and can_attack and not is_rolling:
		initiate_melee_strike()


#     7. MODULAR ENGINE UPDATE ROUTINGS (_PROCESS) [PDF: 0.1.42]

# =============================================================================
#     7. MODULAR ENGINE UPDATE ROUTINGS & STANCE ALIGNMENTS (_PROCESS)
# =============================================================================
func _process(delta: float) -> void:
	var look_axis: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var move_axis: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var is_right_stick_actively_moving: bool = look_axis.length() > 0.20
	var is_left_stick_actively_moving: bool = move_axis.length() > 0.20
	
	# === TRAP ISOLATION SHUTTER VALVE ===
	# If she is holding the Tripwire Trap (Index 1), we completely block free aiming crosshairs!
	# This stops the right stick and mouse cursor from overriding her posture angles.
	var true_aim_state: bool = false
	if current_selected_gadget_index == 1:
		# Keep Tripwire Trap restricted to automated proximity wall snapping [PDF: 0.1.15]
		true_aim_state = false
	elif current_selected_gadget_index == 5:
		# RESTORE FREE AIM: Launcher slot index 5 fully re-awakens your 360-degree aiming crosshairs!
		if not is_radial_menu_open and not radial_menu_active:
			true_aim_state = is_actively_aiming_gadget or is_right_stick_actively_moving
	else:
		# Standard pebbles/bolas free aiming preservation track
		if not is_radial_menu_open and not radial_menu_active:
			true_aim_state = is_actively_aiming_gadget or is_right_stick_actively_moving

		# =============================================================================
		#     SLOT INDEX 5: UNIFIED RESIN LAUNCHER CROSSHAIR MASK [PDF: 0.1.20, 0.1.21]
		# =============================================================================
		if current_selected_gadget_index == 5:
			var active_card = equipped_gadgets_deck[current_selected_gadget_index]
			if is_instance_valid(active_card) and active_card.projectile_scene_file:
				
				# 1. CRUSH FORWARD LOCK: Call our sanitized 360-degree aiming direction vector!
				var verified_launch_heading: Vector3 = get_validated_aim_direction()
				
				# 2. DECOUPLED INSTANTIATION: Materialize the fluid area capsule cleanly
				var fluid_instance = active_card.projectile_scene_file.instantiate() as Node3D
				get_tree().current_scene.add_child(fluid_instance)
				
				# 3. POSITION PROJECTILE SAFELY OUTSIDE HER BODY COLLIDERS
				# Spawns the projectile 0.7 meters FORWARD to guarantee no self-collision locks!
				var spawn_launch_origin = global_position + Vector3(0.0, 0.8, 0.0) + (verified_launch_heading * 0.7)
				fluid_instance.global_position = spawn_launch_origin
				fluid_instance.set("move_direction", verified_launch_heading)
				
				# Compute charging thermal heat ratio multi-gates [PDF: 0.1.75]
				var heat_ratio_multiplier: float = clampf(bola_charge_timer / BOLA_MAX_CHARGE_TIME, 0.25, 1.0)
				fluid_instance.set("current_heat_ratio", heat_ratio_multiplier)
				
				if heat_ratio_multiplier >= 1.0:
					fluid_instance.set("flight_speed", 25.0)
					print("🔥 LAUNCHER: High-pressure boiling amber resin discharged!")
				else:
					print(" Launcher: Low-temperature fluid resin discharged.")
					
				if current_ammo_deck_record.has(active_card.display_name):
					current_ammo_deck_record[active_card.display_name] -= 1
					launcher_ammo = current_ammo_deck_record[active_card.display_name]
					
			bola_charge_timer = 0.0
			is_actively_aiming_gadget = false
			update_ammo_hud_display()
			update_physical_belt_mesh_visibility()
			return


	if has_node("Systems/AimController"):
		$Systems/AimController.process_aim_logic(true_aim_state, bola_charge_timer, delta)
		controller_aim_direction = $Systems/AimController.aim_direction
		
		if not true_aim_state and "active_input_mode_flag" in $Systems/AimController:
			$Systems/AimController.active_input_mode_flag = "MOUSE"

	if has_node("Systems/IndicatorController"):
		$Systems/IndicatorController.update_visual_indicators(true_aim_state, controller_aim_direction, bola_charge_timer, delta)

	# Continuous Proximity System Dispatcher: Wakes up the trap system dynamically if F is held
	if current_selected_gadget_index == 1 and has_node("Systems/TrapPlacementSystem"):
		if is_actively_aiming_gadget:
			$Systems/TrapPlacementSystem.start_aiming()
		else:
			$Systems/TrapPlacementSystem.stop_aiming_and_cancel()

	# Free roaming turning: Eira will ONLY adjust her body mesh direction 
	# if you are actively walking around, leaving her look angle completely untouched when stationary!
	if not true_aim_state and is_instance_valid(eira_body_mesh) and not is_radial_menu_open:
		if is_left_stick_actively_moving or move_axis.length_squared() > 0.04:
			var direction_heading: Vector3 = Vector3.ZERO
			if is_instance_valid(camera):
				var cam_basis: Basis = camera.global_transform.basis
				var right_dir: Vector3 = cam_basis.x
				var forward_dir: Vector3 = cam_basis.z
				right_dir.y = 0.0
				forward_dir.y = 0.0
				var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
				direction_heading = (right_dir.normalized() * input_vec.x + forward_dir.normalized() * input_vec.y).normalized()
			
			if direction_heading.length_squared() > 0.01:
				var look_angle: float = atan2(-direction_heading.x, -direction_heading.z)
				eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, look_angle, mesh_menu_turn_speed * delta)


#     8. VERTICAL WALL TRAVERSAL TRACTION HOOKS

func initiate_ledge_climb(wall_x_coord: float) -> void:
	is_climbing = true
	velocity = Vector3.ZERO
	locked_climb_x = wall_x_coord
	if is_crouching: toggle_crouch_state()
	rotation_degrees.y = -90.0
	print("CLIMBING: Eira grabs hold of the stone handholds.")

func process_climbing_movement(input_vector: Vector2, delta: float) -> void:
	var vertical_velocity: float = -input_vector.y * climb_speed
	var lateral_velocity: float = input_vector.x * climb_speed
	global_position.x = lerp(global_position.x, locked_climb_x + 0.35, 15.0 * delta)
	velocity.y = lerp(velocity.y, vertical_velocity, acceleration * delta)
	velocity.z = lerp(velocity.z, lateral_velocity, acceleration * delta)
	velocity.x = 0.0
	if global_position.y > 5.5 and vertical_velocity > 0.1:
		exit_ledge_climb()
		global_position.y = 5.75
		velocity = Vector3(-4.0, 2.0, 0.0)
		print("CLIMBING: Eira vaults over the top ledge lip onto the platform deck!")
		return
	if is_on_floor() and vertical_velocity < -0.1:
		exit_ledge_climb()

func exit_ledge_climb() -> void:
	is_climbing = false
	velocity = Vector3.ZERO
	print("CLIMBING: Eira releases her hold and drops to her feet.")

func set_active_wind_zone(zone: Area3D) -> void:
	active_wind_zone = zone


#     9. PARTICLE VFX GENERATION SYSTEMS [PDF: 0.1.43, 0.1.44]

func spawn_footstep_dust_cloud(forced: bool = false) -> void:
	if not forced and (is_crouching or is_climbing):
		return
	if not dust_blueprint:
		print("PLAYER VFX ERROR: 'dust_blueprint' slot is EMPTY inside Inspector!")
		return
		
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var floor_query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0.0, -1.5, 0.0))
	var floor_result: Dictionary = space_state.intersect_ray(floor_query)
	var target_dust_color: Color = Color("#e3dac9")
	if not floor_result.is_empty():
		var standing_surface: Node = floor_result["collider"]
		if "High_Platform" in standing_surface.name or "Ramp" in standing_surface.name:
			target_dust_color = Color("#5c4033")
		elif "Ancient_Archway" in standing_surface.name:
			target_dust_color = Color("#4a4d50")
			
	var dust_instance = dust_blueprint.instantiate()
	get_parent().add_child(dust_instance)
	dust_instance.global_position = global_position + Vector3(0.0, 0.05, 0.0)
	dust_instance.global_transform.basis = global_transform.basis
	
	if "emitting" in dust_instance:
		dust_instance.emitting = false 
		if dust_instance.has_method("restart"):
			dust_instance.restart() 
		dust_instance.emitting = true
		
	if "draw_pass_1" in dust_instance and is_instance_valid(dust_instance.draw_pass_1):
		var runtime_mesh = dust_instance.draw_pass_1.duplicate()
		if is_instance_valid(runtime_mesh.material):
			var runtime_material = runtime_mesh.material.duplicate()
			if "albedo_color" in runtime_material:
				runtime_material.albedo_color = target_dust_color
			runtime_mesh.material = runtime_material
			dust_instance.draw_pass_1 = runtime_mesh
	elif "mesh" in dust_instance and is_instance_valid(dust_instance.mesh):
		var runtime_mesh = dust_instance.mesh.duplicate()
		if is_instance_valid(runtime_mesh.material):
			var runtime_material = runtime_mesh.material.duplicate()
			if "albedo_color" in runtime_material:
				runtime_material.albedo_color = target_dust_color
			runtime_mesh.material = runtime_material
			dust_instance.mesh = runtime_mesh
			
	if dust_instance.has_signal("finished"):
		dust_instance.finished.connect(func(): dust_instance.queue_free())
	else:
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(dust_instance): dust_instance.queue_free())
		
	var ripple_blueprint = load("res://scenes/acoustic_ripple.tscn")
	if ripple_blueprint:
		var ripple_instance = ripple_blueprint.instantiate() as MeshInstance3D
		get_parent().add_child(ripple_instance)
		ripple_instance.global_position = global_position + Vector3(0.0, 0.02, 0.0)
		ripple_instance.scale = Vector3(0.1, 0.1, 0.1)
		var ripple_tween: Tween = create_tween()
		ripple_tween.set_parallel(true)
		ripple_tween.tween_property(ripple_instance, "scale", Vector3(6.0, 1.0, 6.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if is_instance_valid(ripple_instance.mesh) and is_instance_valid(ripple_instance.mesh.material):
			var runtime_mat = ripple_instance.mesh.material.duplicate() as StandardMaterial3D
			ripple_instance.material_override = runtime_mat
			ripple_tween.tween_property(runtime_mat, "albedo_color:a", 0.0, 0.45)
		ripple_tween.chain().tween_callback(func(): ripple_instance.queue_free())

func trigger_capture_respawn() -> void:
	current_health -= 1
	update_health_bar_display()
	if current_health <= 0:
		current_health = maximum_health
		update_health_bar_display()
	var checkpoint: Node3D = $"../Respawn_Checkpoint"
	if is_instance_valid(checkpoint):
		global_position = checkpoint.global_position
		velocity = Vector3.ZERO
	if is_crouching: toggle_crouch_state()
	if is_climbing: is_climbing = false
	var smudge: CharacterBody3D = $"../Smudge"
	if is_instance_valid(smudge):
		smudge.global_position = global_position + Vector3(-2.0, 0.0, 0.0)
		smudge.velocity = Vector3.ZERO

func update_health_bar_display() -> void:
	for i in range(maximum_health):
		if is_instance_valid(heart_icons[i]): heart_icons[i].visible = (i < current_health)


#     10. LOCOMOTION MODIFIERS & BOUNDS MANAGEMENT [PDF: 0.1.45, 0.1.46]

func toggle_crouch_state() -> void:
	var target_crouch_state: bool = not is_crouching
	if target_crouch_state:
		is_crouching = true
		current_locomotion_mode = LocomotionState.CROUCHING
		update_player_size(true)
	else:
		is_crouching = false
		current_locomotion_mode = LocomotionState.STANDARD
		update_player_size(false)

func update_player_size(crouching: bool) -> void:
	is_crouching = crouching
	if is_instance_valid(collision_standing):
		var shape_ref = collision_standing.shape as CapsuleShape3D
		if shape_ref:
			if crouching:
				shape_ref.height = 0.9
				collision_standing.position.y = -0.425
				if is_instance_valid(camera): camera.position.y = 0.65
				if has_node("FeetMarker"): $FeetMarker.position.y = -0.45
			else:
				shape_ref.height = 1.75
				collision_standing.position.y = 0.0
				if is_instance_valid(camera): camera.position.y = 1.45
				if has_node("FeetMarker"): $FeetMarker.position.y = -0.875
			velocity.y = 0.0
	if is_instance_valid(eira_body_mesh):
		if eira_body_mesh.mesh is CapsuleMesh:
			eira_body_mesh.mesh.height = 0.9 if crouching else 1.75
			eira_body_mesh.position.y = -0.225 if crouching else 0.0

func process_standard_movement(_direction: Vector3, delta: float) -> void:
	if is_on_wall():
		_direction = _direction.slide(get_wall_normal()).normalized()
	var _active_speed: float = movement_speed
	if current_locomotion_mode == LocomotionState.SPRINTING:
		_active_speed = movement_speed * sprint_speed_multiplier
	elif is_crouching or current_locomotion_mode == LocomotionState.CROUCHING:
		_active_speed = crouch_speed
		
	# FIXED MESH DIRECTION MATRIX: Only turns Eira via WASD keys if she isn't aiming! [PDF: 0.1.46]
	if _direction.length_squared() > 0.001:
		if not is_actively_aiming_gadget and not is_controller_actively_aiming and is_instance_valid(eira_body_mesh):
			var look_angle: float = atan2(-_direction.x, -_direction.z)
			eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, look_angle, mesh_menu_turn_speed * delta)
		
		# LOCOMOTION VALVE: Eira retains 100% fluid walking speed while aiming!
		velocity.x = lerp(velocity.x, _direction.x * _active_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, _direction.z * _active_speed, acceleration * delta)
	else:
		if not is_actively_aiming_gadget and not is_controller_actively_aiming and is_instance_valid(eira_body_mesh):
			eira_body_mesh.rotation.y = lerp_angle(eira_body_mesh.rotation.y, 0.0, mesh_menu_turn_speed * delta)
		velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)
		
	if radial_menu_active and is_instance_valid(eira_body_mesh) and is_instance_valid(camera):
		var camera_basis: Transform3D = camera.global_transform
		var camera_forward: Vector3 = -camera_basis.basis.z
		camera_forward.y = 0.0
		camera_forward = camera_forward.normalized()
		var target_presentation_angle: float = eira_body_mesh.global_rotation.y
		
		# Compute her flat forward direction vector cleanly safely [PDF: 0.1.47]
		var current_mesh_forward: Vector3 = -eira_body_mesh.global_transform.basis.z
		current_mesh_forward.y = 0.0
		current_mesh_forward = current_mesh_forward.normalized()
		
		if not current_mesh_forward.dot(camera_forward) > 0.0:
			target_presentation_angle = atan2(camera_forward.x, camera_forward.z) + PI
			
		match menu_highlighted_gadget:
			GadgetType.BOLA: target_presentation_angle += deg_to_rad(45.0)
			GadgetType.TRAP: target_presentation_angle += deg_to_rad(20.0)
			GadgetType.PEBBLE: target_presentation_angle += deg_to_rad(0.0)
			GadgetType.SLIME: target_presentation_angle += deg_to_rad(-20.0)
			GadgetType.BOMB: target_presentation_angle += deg_to_rad(-45.0)
		eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, target_presentation_angle, mesh_menu_turn_speed * delta)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)


#     11. COMBAT INTERCEPTOR CHASSIS MODULES [PDF: 0.1.22]

func initiate_melee_strike() -> void:
	was_crouching_on_attack = is_crouching
	is_attacking = true
	can_attack = false
	can_dodge = false
	attack_timer = attack_duration
	hitbox_collision.disabled = false
	if is_crouching: toggle_crouch_state()

func process_active_attack(_direction: Vector3, delta: float) -> void:
	attack_timer -= delta
	var dampened_velocity: Vector3 = _direction * (movement_speed * attack_movement_dampening)
	velocity.x = lerp(velocity.x, dampened_velocity.x, acceleration * delta)
	velocity.z = lerp(velocity.z, dampened_velocity.z, acceleration * delta)
	if attack_timer <= 0.0: 
		is_attacking = false 
		can_dodge = true 
		if is_instance_valid(hitbox_collision): hitbox_collision.set_deferred("disabled", true) 
		get_tree().create_timer(attack_cooldown).timeout.connect(func(): can_attack = true)

func _on_melee_hit_registered(collider: Node) -> void:
	if collider == self or collider.name == "Smudge": return
	if collider.is_in_group("EnemyGroup") and "current_phase" in collider:
		var current_suspicion = collider.current_suspicion_value if "current_suspicion_value" in collider else 0.0
		var guard_phase = collider.current_phase
		if current_suspicion < 10.0 or guard_phase == collider.PatrolPhase.BOLA_STRUGGLE or guard_phase == collider.PatrolPhase.INVESTIGATING:
			if collider.has_method("execute_stealth_stun"):
				collider.execute_stealth_stun(-global_transform.basis.z.normalized())
			grant_salvage_bonus()
			return
		else:
			if collider.has_method("take_damage"):
				collider.take_damage(1, -global_transform.basis.z.normalized())
	elif collider.has_method("take_damage"):
		collider.take_damage(1, -global_transform.basis.z.normalized())

func initiate_dodge_roll(_direction: Vector3) -> void:
	is_rolling = true
	can_dodge = false
	can_attack = false
	if _direction.length_squared() > 0.01:
		roll_direction = _direction.normalized()
	else:
		roll_direction = -eira_body_mesh.global_transform.basis.z.normalized() if is_instance_valid(eira_body_mesh) else -global_transform.basis.z.normalized()
	roll_timer = dodge_duration
	if is_instance_valid(eira_body_mesh):
		eira_body_mesh.global_rotation.y = atan2(-roll_direction.x, -roll_direction.z)

func process_active_roll(delta: float) -> void:
	roll_timer -= delta
	velocity.x = roll_direction.x * dodge_speed
	velocity.z = roll_direction.z * dodge_speed
	
	if roll_timer <= 0.0:
		is_rolling = false
		velocity = Vector3.ZERO
		
		# FIXED COMBAT FLOW: Restore her ability to attack immediately upon exiting a roll!
		can_attack = true 
		
		# Keep her dodge on its standard designer category cooldown clock
		get_tree().create_timer(dodge_cooldown).timeout.connect(func(): 
			can_dodge = true
		)

func execute_shield_parry() -> void:
	var space_state = get_world_3d().direct_space_state
	var parry_blast_sphere = PhysicsShapeQueryParameters3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 3.0
	parry_blast_sphere.shape_rid = sphere_shape.get_rid()
	parry_blast_sphere.transform = global_transform
	var intersections = space_state.intersect_shape(parry_blast_sphere)
	for hit in intersections:
		var obstacle_body = hit["collider"]
		if is_instance_valid(obstacle_body) and obstacle_body.is_in_group("EnemyGroup"):
			if obstacle_body.has_method("execute_disarm_parry_drop"): obstacle_body.execute_disarm_parry_drop()
	is_parrying = true
	can_attack = false
	can_dodge = false
	if is_crouching: toggle_crouch_state()
	var parry_tween = create_tween()
	parry_tween.tween_property(player_mesh, "position:z", -0.4, 0.1)
	parry_tween.tween_property(player_mesh, "position:z", 0.0, 0.15)
	get_tree().create_timer(0.35).timeout.connect(func():
		is_parrying = false
		can_attack = true
		can_dodge = true
	)

func start_gadget_cooldown(time: float) -> void:
	is_gadget_on_cooldown = true
	get_tree().create_timer(time).timeout.connect(func(): is_gadget_on_cooldown = false)


#     12. DYNAMIC HUD AMMO DISPATCH TRACKERS [PDF: 0.1.20]

func update_ammo_hud_display() -> void:
	if equipped_gadgets_deck.is_empty() or current_selected_gadget_index >= equipped_gadgets_deck.size(): return
	var active_card = equipped_gadgets_deck[current_selected_gadget_index]
	if not is_instance_valid(active_card): return
	if is_instance_valid(ammo_label):
		match active_card.type:
			0: ammo_label.text = active_card.display_name + ": INF"
			1: ammo_label.text = active_card.display_name + ": " + str(current_bola_ammo) + " / " + str(max_bola_ammo)
			2: ammo_label.text = active_card.display_name + ": " + str(slime_ammo) + " / 4"
			_: ammo_label.text = active_card.display_name + ": Locked"
	update_physical_belt_mesh_visibility()

func update_physical_belt_mesh_visibility() -> void:
	#     UNIFIED BOLA MESH VISIBILITY TRACKING
	# Fetch our true live ammo count straight from our master data record dictionary
	var _bola_ammo_count: int = 0
	if current_ammo_deck_record.has("Bola"):
		_bola_ammo_count = current_ammo_deck_record.get("Bola", 0)

	# FIXED VISIBILITY MATRIX: Uses current_selected_gadget_index to prevent index drops!
	# Index 2 represents your Pebble resource card slot cleanly
	var _is_pebble_equipped: bool = (current_selected_gadget_index == 2)
	var _should_render_bolas: bool = (_bola_ammo_count > 0) and not _is_pebble_equipped


	if is_instance_valid(bola_mesh_01): bola_mesh_01.visible = _should_render_bolas and (_bola_ammo_count >= 1)
	if is_instance_valid(bola_mesh_02): bola_mesh_02.visible = _should_render_bolas and (_bola_ammo_count >= 2)
	if is_instance_valid(bola_mesh_03): bola_mesh_03.visible = _should_render_bolas and (_bola_ammo_count >= 3)
		
	# Process your other belt invention meshes cleanly
	if is_instance_valid(trap_rig): trap_rig.visible = (trap_ammo > 0)
	if is_instance_valid(slime_rig): slime_rig.visible = (slime_ammo > 0)
	if is_instance_valid(pebble_rig): pebble_rig.visible = true
	if is_instance_valid(bomb_rig): bomb_rig.visible = (bomb_ammo > 0)
	
	var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")
	
	if current_locomotion_mode == LocomotionState.SLIDING or current_locomotion_mode == LocomotionState.AIR_PREP:
		if back_mesh: back_mesh.visible = false
		if hand_mesh: hand_mesh.visible = false
		if feet_mesh: feet_mesh.visible = true
	else:
		if back_mesh: back_mesh.visible = true
		if feet_mesh: feet_mesh.visible = false
		if hand_mesh: hand_mesh.visible = is_parrying

func clear_all_gadget_camera_priorities() -> void:
	if is_instance_valid(exploration_pcam): exploration_pcam.priority = 30
	if is_instance_valid(bola_pcam): bola_pcam.priority = 0
	if is_instance_valid(trap_pcam): trap_pcam.priority = 0
	if is_instance_valid(slime_pcam): slime_pcam.priority = 0
	if is_instance_valid(pebble_pcam): pebble_pcam.priority = 0
	if is_instance_valid(bomb_pcam): bomb_pcam.priority = 0

func morph_camera_track_finish_line(target_marker: Marker3D) -> void:
	if not is_instance_valid(target_marker) or not is_instance_valid(placeholder_hand_rig): return
	var arm_cleanup = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	arm_cleanup.tween_property(placeholder_hand_rig, "position", target_marker.position, 0.12)

func trigger_dedicated_pouch_camera_swap() -> void:
	var bola_cam = get_node_or_null("Bola_PCAM")
	var pebble_cam = get_node_or_null("Pebble_PCAM")
	var slime_cam = get_node_or_null("Slime_PCAM")
	if is_instance_valid(bola_cam): bola_cam.priority = 0
	if is_instance_valid(pebble_cam): pebble_cam.priority = 0
	if is_instance_valid(slime_cam): slime_cam.priority = 0
	match current_selected_gadget_index:
		0: if is_instance_valid(bola_cam): bola_cam.priority = 25
		1: if is_instance_valid(pebble_cam): pebble_cam.priority = 25
		2: if is_instance_valid(slime_cam): slime_cam.priority = 25


#     13. UNHANDLED INPUT TARGET LOCK ENGINES (_UNHANDLED_INPUT) [PDF: 0.1.21]

func _unhandled_input(event: InputEvent) -> void:
	
	if event.is_action_pressed("combat_counter_button") and not radial_menu_active:
		execute_shield_counter_intercept()
		get_viewport().set_input_as_handled()
		return
		
	# 2. THE MELEE STRIKE GAGE: Triggers standard thumps or silent shadow grapples
	elif event.is_action_pressed("attack_melee") and not radial_menu_active:
		execute_dynamic_melee_strike_pipeline()
		get_viewport().set_input_as_handled()
		return
	
	
	# PATH A: Press F to engage her tactical wind ribbon indicators or standalone placements! [PDF: 0.1.13]
	if event.is_action_pressed("use_gadget") and not radial_menu_active:
		is_actively_aiming_gadget = true
		bola_charge_timer = 0.0
		
		# ISOLATED PLACEMENT DISPATCH: Index 1 targets your Tripwire Trap resource deck card slot!
		if current_selected_gadget_index == 1 and has_node("Systems/TrapPlacementSystem"):
			# Safety check: Only execute deployment if she actually has items left inside her inventory!
			if current_ammo_deck_record.get("Tripwire Trap", 0) > 0:
				$Systems/TrapPlacementSystem.execute_final_deployment()
			else:
				$Systems/TrapPlacementSystem.stop_aiming_and_cancel()
				
			bola_charge_timer = 0.0
			update_physical_belt_mesh_visibility()
			return
		
	# PATH B: Release F to safely fire the gadget payload under strict isolated gates! [PDF: 0.1.34]
	elif event.is_action_released("use_gadget") and is_actively_aiming_gadget:
		
		# === FIXED GADGET FIRE PIPELINE: DELAY RE-ROTATION OVERWRITES ===
		# We clear her aiming state indicators, but do NOT force controller_aim_direction 
		# back to a flat forward reset vector until the active slot code finishes discharging!
		is_actively_aiming_gadget = false
		
		var aim_node = get_node_or_null("Systems/AimController")
		if is_instance_valid(aim_node):
			aim_node.active_input_mode_flag = "MOUSE"
			
		# =============================================================================
		#     SLOT INDEX 1: TRIPWIRE TRAP PLACEMENT INTERCEPT
		# =============================================================================
		if current_selected_gadget_index == 1 and has_node("Systems/TrapPlacementSystem"):
			$Systems/TrapPlacementSystem.execute_final_deployment()
			bola_charge_timer = 0.0
			is_controller_actively_aiming = false
			controller_aim_direction = -global_transform.basis.z.normalized()
			update_physical_belt_mesh_visibility()
			return
			
		# =============================================================================
		#     SLOT INDEX 5: UNIFIED RESIN LAUNCHER ENGINE
		# =============================================================================
		if current_selected_gadget_index == 5:
			var active_card = equipped_gadgets_deck[current_selected_gadget_index]
			if is_instance_valid(active_card) and active_card.projectile_scene_file:
				
				# Call our sanitized 360-degree aiming direction look vector!
				var verified_launch_heading: Vector3 = get_validated_aim_direction()
				
				var fluid_instance = active_card.projectile_scene_file.instantiate() as Node3D
				get_tree().current_scene.add_child(fluid_instance)
				
				# Position outside self capsule to block self-collision locks [PDF: 0.1.17]
				var spawn_launch_origin = global_position + Vector3(0.0, 0.8, 0.0) + (verified_launch_heading * 0.7)
				fluid_instance.global_position = spawn_launch_origin
				fluid_instance.set("move_direction", verified_launch_heading)
				
				var heat_ratio_multiplier: float = clampf(bola_charge_timer / BOLA_MAX_CHARGE_TIME, 0.25, 1.0)
				fluid_instance.set("current_heat_ratio", heat_ratio_multiplier)
				
				if heat_ratio_multiplier >= 1.0:
					fluid_instance.set("flight_speed", 25.0)
					print("🔥 LAUNCHER: High-pressure boiling amber resin discharged!")
				else:
					print(" Launcher: Low-temperature fluid resin discharged.")
					
				if current_ammo_deck_record.has(active_card.display_name):
					current_ammo_deck_record[active_card.display_name] -= 1
					launcher_ammo = current_ammo_deck_record[active_card.display_name]
			
			# Flush weapon parameters safely AFTER the projectile has finished its flight setup
			bola_charge_timer = 0.0
			is_controller_actively_aiming = false
			controller_aim_direction = -global_transform.basis.z.normalized()
			update_ammo_hud_display()
			update_physical_belt_mesh_visibility()
			return
		
	# Mouse wheel scrolling trackers run unblocked
	if is_radial_menu_open and radial_menu_active and event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_backpack_gadget(-1) # Scrolls UP towards Bola (0) and stops rigidly!
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_backpack_gadget(1)  # Scrolls DOWN towards Launcher (5) and stops rigidly!
			get_viewport().set_input_as_handled()


#     14. UNIFIED DIRECT INPUT HANDLERS (_INPUT) [PDF: 0.1.22]

func _input(event: InputEvent) -> void:
	# Check both mouse click triggers and gamepad weapon attack triggers symmetrically
	var is_attack_triggered: bool = event.is_action_pressed("attack_melee") or (event is InputEventJoypadButton and event.is_action_pressed("attack_melee"))
	
	if is_attack_triggered:
		if event.is_echo(): return
		if radial_menu_active or is_radial_menu_open: return
		
		# === THE AIM CANCEL SHUTTER GATE ===
		# Tapping attack while holding down aim will reset her stance, clear the flags,
		# and hide pointers instantly instead of swinging her sword!
		if is_actively_aiming_gadget or is_controller_actively_aiming:
			is_actively_aiming_gadget = false
			is_controller_actively_aiming = false
			
			# Clear out our isolated standalone trap placement nodes instantly!
			if has_node("Systems/TrapPlacementSystem"):
				$Systems/TrapPlacementSystem.stop_aiming_and_cancel()
				
			if is_instance_valid(indicator_rig):
				var lob_visual_node = indicator_rig.get_node_or_null("Lob_Line_Pointer/Line_Visual")
				var flat_visual_node = indicator_rig.get_node_or_null("Aim_Line_Pointer/Line_Visual")
				if is_instance_valid(lob_visual_node): lob_visual_node.visible = false
				if is_instance_valid(flat_visual_node): flat_visual_node.visible = false
			get_viewport().set_input_as_handled()
			return 
			
		# Standard combat execution path (runs only if pointers were already hidden)
		if is_crouching and current_locomotion_mode != LocomotionState.SPRINTING:
			var target_guard: Node3D = null
			var guards = get_tree().get_nodes_in_group("EnemyGroup")
			for guard in guards:
				if is_instance_valid(guard) and "takedown_label_3d" in guard and guard.takedown_label_3d.visible:
					target_guard = guard
					break
			if is_instance_valid(target_guard) and target_guard.has_method("execute_stealth_stun"):
				target_guard.execute_stealth_stun(controller_aim_direction if is_controller_actively_aiming else -global_transform.basis.z.normalized())
				return
		if can_attack and not is_rolling: initiate_melee_strike()

	if event.is_action_pressed("sprint"):
		if event.is_echo(): return
		if current_locomotion_mode == LocomotionState.SLIDING or current_locomotion_mode == LocomotionState.AIR_PREP or current_locomotion_mode == LocomotionState.STOMP_EXIT: return
		if current_locomotion_mode == LocomotionState.SPRINTING:
			current_locomotion_mode = LocomotionState.STANDARD
		else:
			if not is_crouching and not is_climbing and not is_rolling: current_locomotion_mode = LocomotionState.SPRINTING

	if event.is_action_pressed("stealth_crouch"):
		if event.is_echo(): return
		if not is_rolling and not is_attacking and not is_climbing:
			match current_locomotion_mode:
				LocomotionState.SPRINTING:
					velocity.y = 5.2
					enter_air_prep_state()
				LocomotionState.SLIDING:
					execute_slide_cancel()
				_:
					toggle_crouch_state()

	if event.is_action_pressed("interact") and not radial_menu_active:
		# Check if she is standing near a valid resin climbing ledge structure first!
		var active_structures = get_tree().get_nodes_in_group("ResinStructure")
		var handled_climb_action: bool = false
		
		for structure in active_structures:
			if is_instance_valid(structure) and structure.get("is_player_inside_climb_zone") == true:
				if structure.has_method("execute_climb_mantle_dispatch"):
					structure.execute_climb_mantle_dispatch()
					handled_climb_action = true
					break

		if handled_climb_action:
			get_viewport().set_input_as_handled()
			return

		# Symmetrical fallback: Runs her standard dead guard item looting code if not climbing! [PDF: 0.1.41]
		handle_drag_interaction()
		var space_state = get_world_3d().direct_space_state
		var loot_query = PhysicsShapeQueryParameters3D.new()
		var search_sphere = SphereShape3D.new()
		search_sphere.radius = 2.0
		loot_query.shape_rid = search_sphere.get_rid()
		loot_query.transform = global_transform
		loot_query.exclude = [self.get_rid()]
		var contact_points = space_state.intersect_shape(loot_query)
		for hit in contact_points:
			var body_node = hit["collider"]
			if is_instance_valid(body_node) and body_node.is_in_group("EnemyGroup"):
				if "is_currently_lootable" in body_node and body_node.is_currently_lootable:
					body_node.is_currently_lootable = false
					body_node.has_already_been_looted = true
					var _items_found_text: String = ""
					if "bola_ammo_to_award" in body_node and current_bola_ammo < max_bola_ammo:
						current_bola_ammo = clamped_addition_value(current_bola_ammo, body_node.bola_ammo_to_award, max_bola_ammo)
						_items_found_text += " +1 Bola Trap"
					if "matches_to_award" in body_node and "current_matches" in self:
						self.current_matches += body_node.matches_to_award
						_items_found_text += " +1 Campfire Match"
					update_ammo_hud_display()
					if is_instance_valid(ammo_label):
						var punch = create_tween()
						ammo_label.scale = Vector2(1.3, 1.3)
						punch.tween_property(ammo_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC)
					if "alert_label" in body_node and is_instance_valid(body_node.alert_label):
						body_node.alert_label.text = "EMPTY"
						body_node.alert_label.modulate = Color("#888888")
					break

	if event.is_action_pressed("shield_parry"):
		if event.is_echo(): return
		if radial_menu_active or is_radial_menu_open: return
		
		# BYPASS VALVE: If she is aiming, allow her triggers to pass raw 
		# float axis depth data down without breaking the event thread!
		if is_actively_aiming_gadget or is_controller_actively_aiming:
			if event is InputEventJoypadMotion or event.is_action("shield_parry"):
				return # Let the raw analog data slide down to your distance modifiers safely!
				
		if not is_rolling and not is_attacking and not is_climbing: 
			execute_shield_parry()

	if event.is_action_pressed("swap_gadget"):
		if event.is_echo(): return
		
		# FIXED INVENTORY ACTION VALVE: Block gadget selection swaps if she is actively aiming!
		if is_actively_aiming_gadget or is_controller_actively_aiming:
			print("🎒 INVENTORY SYSTEM: Weapon swapping blocked while holding aim targets!")
			return
			
		if not is_rolling and not is_climbing and current_locomotion_mode != LocomotionState.SLIDING:
			is_radial_menu_open = true
			radial_menu_active = true
			original_mesh_rotation_y = global_rotation.y
			Engine.time_scale = 0.15
			if is_instance_valid(placeholder_hand_rig): placeholder_hand_rig.visible = true
			if is_instance_valid(eira_body_mesh) and is_instance_valid(camera):
				var camera_basis: Transform3D = camera.global_transform
				var camera_forward: Vector3 = -camera_basis.basis.z
				camera_forward.y = 0.0
				camera_forward = camera_forward.normalized()
				var current_mesh_forward_vec: Vector3 = -eira_body_mesh.global_transform.basis.z
				current_mesh_forward_vec.y = 0.0
				current_mesh_forward_vec = current_mesh_forward_vec.normalized()
				var is_back_already_exposed: bool = current_mesh_forward_vec.dot(camera_forward) > 0.3
				var target_angle: float = atan2(camera_forward.x, camera_forward.z) + PI
				if is_back_already_exposed: target_angle = eira_body_mesh.global_rotation.y
				var entrance_twist = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				entrance_twist.tween_property(eira_body_mesh, "global_rotation:y", target_angle, 0.45)
				manage_virtual_camera_priorities(current_selected_gadget)


	if event.is_action_released("swap_gadget"):
		if is_radial_menu_open:
			current_selected_gadget = menu_highlighted_gadget
			is_radial_menu_open = false
			radial_menu_active = false
			Engine.time_scale = 1.0
			clear_all_gadget_camera_priorities()
			update_physical_belt_mesh_visibility()
			if is_instance_valid(eira_body_mesh):
				var mesh_reset = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				mesh_reset.tween_property(eira_body_mesh, "rotation:y", 0.0, 0.22)
				mesh_reset.tween_callback(func():
					if is_instance_valid(placeholder_hand_rig): placeholder_hand_rig.visible = false
				)

func clamped_addition_value(current: int, incoming: int, limit: int) -> int: return min(current + incoming, limit) as int
func add_treasure_key_to_inventory() -> void: carried_treasure_keys_count += 1

func evaluate_radial_wheel_joystick_navigation() -> void:
	if not radial_menu_active: return
	var look_vector_x: float = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	if abs(look_vector_x) > 0.6:
		if not controller_joystick_debounce:
			controller_joystick_debounce = true
			cycle_backpack_gadget(1 if look_vector_x > 0 else -1)
			manage_virtual_camera_priorities(menu_highlighted_gadget)
	else:
		controller_joystick_debounce = false

func grant_salvage_bonus() -> void:
	if current_bola_ammo < max_bola_ammo: current_bola_ammo += 1

func handle_drag_interaction() -> void:
	if is_instance_valid(dragged_body):
		dragged_body.reparent(get_tree().root)
		dragged_body.velocity = Vector3.ZERO
		dragged_body = null
	else:
		for body in get_tree().get_nodes_in_group("EnemyGroup"):
			if body.global_position.distance_to(global_position) < 2.0:
				if "current_phase" in body and body.current_phase == 2:
					dragged_body = body
					dragged_body.reparent(self)
					dragged_body.position = Vector3(0, 0, -1.5)
					dragged_body.add_to_group("UnconsciousEnemy")
					break

func _on_cascade_sensor_body_entered(body: Node) -> void:
	if body.is_in_group("EnemyGroup") and body != self:
		if body.has_method("execute_cascade_stumble_fall"): body.execute_cascade_stumble_fall()

func process_sliding_movement(delta: float) -> void:
	var dynamic_friction: float = base_slide_friction + 0.85
	var slope_angle: float = 0.0
	var slope_down_direction: Vector3 = Vector3.DOWN
	if is_instance_valid(ground_snapper) and ground_snapper.is_colliding():
		var floor_normal: Vector3 = ground_snapper.get_collision_normal()
		slope_down_direction = Vector3.DOWN.slide(floor_normal).normalized()
		slope_angle = Vector3.UP.angle_to(floor_normal)
	var forward_heading := -global_transform.basis.z
	if forward_heading.dot(slope_down_direction) < 0.0:
		if slope_angle > 0.05: dynamic_friction += (slope_angle * 18.0)
	else:
		if slope_angle > 0.05: velocity += slope_down_direction * slope_angle * 24.0 * delta
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.01 and is_instance_valid(camera):
		var cam_basis: Transform3D = camera.global_transform
		var right_dir: Vector3 = cam_basis.basis.x
		var forward_dir: Vector3 = -cam_basis.basis.z
		right_dir.y = 0.0
		forward_dir.y = 0.0
		var target_steering: Vector3 = (right_dir.normalized() * input_vector.x) - (forward_dir.normalized() * input_vector.y)
		if target_steering.length() > 0.01:
			var current_speed := velocity.length()
			velocity = velocity.lerp(target_steering.normalized() * current_speed, slide_steer_speed * delta)
	if is_instance_valid(eira_body_mesh):
		var look_angle: float = atan2(-velocity.x, -velocity.z)
		eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, look_angle, 8.0 * delta)
	velocity.x = move_toward(velocity.x, 0.0, dynamic_friction * slide_friction_decay * delta)
	velocity.z = move_toward(velocity.z, 0.0, dynamic_friction * slide_friction_decay * delta)
	move_and_slide()
	if Vector3(velocity.x, 0, velocity.z).length() < 3.8: enter_stomp_exit_state()
	
func enter_air_prep_state() -> void:
	current_locomotion_mode = LocomotionState.AIR_PREP
	velocity.y = 5.2
	update_physical_belt_mesh_visibility()

func enter_sliding_state() -> void:
	current_locomotion_mode = LocomotionState.SLIDING
	is_crouching = false
	update_player_size(true)
	
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# FIXED SLIDE MOMENTUM: Baseline direction uses her current physical movement vector!
	var launch_direction: Vector3 = velocity.normalized()
	if launch_direction.length_squared() < 0.01:
		launch_direction = -global_transform.basis.z.normalized()
		
	# If keys are held, let steering vectors alter her launch corridor cleanly
	if input_vector.length_squared() > 0.01 and is_instance_valid(camera):
		var cam_basis: Transform3D = camera.global_transform
		var right_dir: Vector3 = cam_basis.basis.x
		var forward_dir: Vector3 = -cam_basis.basis.z
		right_dir.y = 0.0
		forward_dir.y = 0.0
		var target_launch: Vector3 = (right_dir.normalized() * input_vector.x) - (forward_dir.normalized() * input_vector.y)
		if target_launch.length_squared() > 0.01: 
			launch_direction = target_launch.normalized()
			
	# Preserve and boost active momentum vectors cleanly across world ramp tile matrices
	var horizontal_boost_speed: float = max(velocity.length() * 1.1, minimum_slide_boost)
	velocity.x = launch_direction.x * horizontal_boost_speed
	velocity.z = launch_direction.z * horizontal_boost_speed
	velocity.y = 0.0
	
	spawn_footstep_dust_cloud(true)
	update_physical_belt_mesh_visibility()

func enter_stomp_exit_state() -> void:
	current_locomotion_mode = LocomotionState.STOMP_EXIT
	is_crouching = false
	update_player_size(false)
	velocity.y = 6.2
	var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")
	var flying_shield_fx := FLYING_SHIELD_SCENE.instantiate()
	get_tree().current_scene.add_child(flying_shield_fx)
	if feet_mesh: flying_shield_fx.launch(feet_mesh.global_position + Vector3(0, 0.4, 0.2), self, velocity * 0.35)
	get_tree().create_timer(0.45).timeout.connect(func(): if is_instance_valid(back_mesh) and current_locomotion_mode != LocomotionState.SLIDING: back_mesh.visible = true)
	current_locomotion_mode = LocomotionState.STANDARD
	update_physical_belt_mesh_visibility()

func execute_slide_cancel() -> void:
	var is_ceiling_blocked: bool = false
	if has_node("CeilingCheck") and $CeilingCheck.is_colliding(): is_ceiling_blocked = true
	if not is_ceiling_blocked:
		update_player_size(false)
		is_crouching = false
		current_locomotion_mode = LocomotionState.STANDARD
		velocity.y = 0.0
		var true_max_sprint_speed: float = movement_speed * sprint_speed_multiplier
		var horizontal_vel = Vector3(velocity.x, 0.0, velocity.z)
		if horizontal_vel.length() > true_max_sprint_speed:
			var constrained_vel = horizontal_vel.normalized() * true_max_sprint_speed
			velocity.x = constrained_vel.x
			velocity.z = constrained_vel.z
	else:
		is_crouching = true
		current_locomotion_mode = LocomotionState.CROUCHING
		velocity.y = 0.0
	update_physical_belt_mesh_visibility()


#     15. VIRTUAL PCAM CAMERA PRIORITY CONTROLLERS [PDF: 0.1.44]

func cycle_backpack_gadget(direction: int) -> void:
	var _total_available_slots: int = 5 # Total number of gadget items on her belt
	var total_slots_count: int = equipped_gadgets_deck.size()
	if total_slots_count <= 0: return
	
	# HARD CLAMP BOUNDARY CHECK: Calculates the exact next slot step
	var next_intended_index: int = current_selected_gadget_index + direction
	
	# STRICT VISUAL ROADBLOCK GATES: If you reach the absolute edge, block all further scrolling!
	if next_intended_index < 0 or next_intended_index >= total_slots_count:
		print("🎒 INVENTORY BLOCKED: Reached the absolute end of the belt slot array line!")
		return
		
	# Verify that the targeted slot contains a valid filled item data card
	if not is_instance_valid(equipped_gadgets_deck[next_intended_index]):
		return

	# Lock the index position down permanently
	current_selected_gadget_index = next_intended_index
	current_selected_index = next_intended_index
	
	var active_card: GadgetResource = equipped_gadgets_deck[next_intended_index]
	if is_instance_valid(active_card):
		current_selected_gadget = next_intended_index as GadgetType
		menu_highlighted_gadget = next_intended_index as GadgetType
		active_highlighted_gadget = next_intended_index as GadgetType
		
		# Telemetry Logger
		print("🎒 INVENTORY POSITION -> Index Slot: [", next_intended_index, "] | Weapon Equipped: '", active_card.display_name, "'")
			
	update_ammo_hud_display()
	update_physical_belt_mesh_visibility()
	manage_virtual_camera_priorities(menu_highlighted_gadget)


func manage_virtual_camera_priorities(target_gadget: GadgetType) -> void:
	if not is_radial_menu_open:
		if is_instance_valid(exploration_pcam): exploration_pcam.priority = 30
		return
	if is_instance_valid(exploration_pcam): exploration_pcam.priority = 0
	
	# Sleep all utility cameras
	if is_instance_valid(bola_pcam): bola_pcam.priority = 0
	if is_instance_valid(trap_pcam): trap_pcam.priority = 0
	if is_instance_valid(pebble_pcam): pebble_pcam.priority = 0
	if is_instance_valid(slime_pcam): slime_pcam.priority = 0
	if is_instance_valid(bomb_pcam): bomb_pcam.priority = 0
	
	# Wake up the virtual camera slot matching her scroll selection
	match target_gadget:
		GadgetType.BOLA:
			if is_instance_valid(bola_pcam): bola_pcam.priority = 25
			morph_camera_track_finish_line(left_hip_marker)

		GadgetType.PEBBLE:
			if is_instance_valid(pebble_pcam): pebble_pcam.priority = 25
			morph_camera_track_finish_line(waist_center_marker)
		GadgetType.SLIME:
			if is_instance_valid(slime_pcam): slime_pcam.priority = 25
			morph_camera_track_finish_line(waist_right_marker)
		GadgetType.BOMB:
			if is_instance_valid(bomb_pcam): bomb_pcam.priority = 25
			morph_camera_track_finish_line(right_hip_marker)
		GadgetType.LAUNCHER:
			if is_instance_valid(exploration_pcam): exploration_pcam.priority = 30
		GadgetType.TRAP:
			if is_instance_valid(trap_pcam): trap_pcam.priority = 25
			morph_camera_track_finish_line(waist_left_marker)
			
			# Hides the throw ribbons and forces the Wall Preview to wake up!
			if is_instance_valid(indicator_rig):
				var lob_pointer = indicator_rig.get_node_or_null("Lob_Line_Pointer/Line_Visual")
				var wall_trap_pointer = indicator_rig.get_node_or_null("Wall_Trap_Pointer")
				
				if is_instance_valid(lob_pointer): lob_pointer.visible = false
				if is_instance_valid(wall_trap_pointer):
					wall_trap_pointer.visible = is_actively_aiming_gadget
					# Safety fall-through clear: If she isn't aiming, force previews to pack away instantly
					if not is_actively_aiming_gadget and wall_trap_pointer.has_method("_hide_all_holographic_previews"):
						wall_trap_pointer._hide_all_holographic_previews()


func _deploy_physical_wall_harpoon_trap(pos_a: Vector3, pos_b: Vector3) -> void:
	var active_card = equipped_gadgets_deck[current_selected_gadget_index]
	if not is_instance_valid(active_card) or not active_card.projectile_scene_file: return
	
	# Instantiate the physical mechanical trap replica asset into the scene root tree
	var trap_instance = active_card.projectile_scene_file.instantiate() as Node3D
	get_tree().current_scene.add_child(trap_instance)
	
	# Dispatch coordinates straight down into your reworked tripwire_trap.gd script!
	if trap_instance.has_method("initialize_tripwire"):
		trap_instance.initialize_tripwire(pos_a, pos_b)
		
	# Subtract 1 trap card item token from her inventions pouch record dictionary [PDF: 0.1.26]
	if current_ammo_deck_record.has(active_card.display_name):
		current_ammo_deck_record[active_card.display_name] -= 1
		trap_ammo = current_ammo_deck_record[active_card.display_name]
		
	# Turn off the placement preview holograms instantly on fire frame
	if is_instance_valid(indicator_rig):
		var wall_trap_pointer = indicator_rig.get_node_or_null("Wall_Trap_Pointer")
		if is_instance_valid(wall_trap_pointer): wall_trap_pointer.visible = false
	
	print("TRAP COUPLING: Mechanical structural harpoon case successfully mounted into game world map!")

func execute_dynamic_melee_strike_pipeline() -> void:
	var overworld_enemies = get_tree().get_nodes_in_group("EnemyGroup")
	var target_guard: CharacterBody3D = null
	var shortest_reach: float = 2.4 
	
	for guard in overworld_enemies:
		if is_instance_valid(guard) and "current_phase" in guard:
			if guard.current_phase == guard.PatrolPhase.STUNNED: continue
			var dist: float = global_position.distance_to(guard.global_position)
			if dist < shortest_reach:
				shortest_reach = dist
				target_guard = guard

	if not is_instance_valid(target_guard): return
	var push_vector: Vector3 = -global_transform.basis.z.normalized()

	var current_suspicion: float = 0.0
	if target_guard.has_node("VisionSensor3D"):
		current_suspicion = target_guard.get_node("VisionSensor3D").current_suspicion

	var is_sneaking: bool = get("is_crouching") if "is_crouching" in self else false
	
	if is_sneaking and current_suspicion < 15.0:
		var takedown_label = target_guard.get_node_or_null("Takedown_Label") as Label3D
		if is_instance_valid(takedown_label) and "DANGER" in takedown_label.text:
			print("⚠️ STEALTH TAKEDOWN LOCKED: You are currently being watched by an ally guard!")
			target_guard.take_damage(1, push_vector) 
			return
			
		print("🥷 SILENT TAKEDOWN SUCCESS: Eira silent-grapples the guard out cold!")
		target_guard.execute_stealth_stun(push_vector)
		return
	else:
		print(" Combat Impact: Smashing shield mesh forward to strip posture stability!")
		
		# FIXED COMBAT CRASH: Wrapped the main combat strike inside our safe verification method
		if target_guard.has_method("take_damage"):
			target_guard.take_damage(1, push_vector)
		else:
			print(" TARGET PIPELINE ERROR: Guard mesh lacks a valid take_damage() method!")

func execute_shield_counter_intercept() -> void:
	var overworld_enemies = get_tree().get_nodes_in_group("EnemyGroup")
	var push_vector: Vector3 = -global_transform.basis.z.normalized()
	
	for guard in overworld_enemies:
		# Check if this specific guard node is currently in an active attack windup state!
		if is_instance_valid(guard) and guard.get("is_vulnerable_to_counter") == true:
			print("🛡️ COUNTER SUCCESS: Eira catches the blade hilt on her shield face and counters!")
			
			# Close his vulnerability window, halt his swing threat, and strip 2 hidden Posture points!
			guard.is_vulnerable_to_counter = false
			
			if guard.has_method("take_damage"):
				guard.take_damage(2, push_vector)
			
			# Spawn a quick smoke dust particle cloud over his mesh [PDF: 0.1.18]
			if guard.has_method("spawn_procedural_takedown_fx_cloud"):
				guard.spawn_procedural_takedown_fx_cloud()
				
			# Reset your tool launcher cooldown frames instantly as a Freeflow reward!
			is_gadget_on_cooldown = false
			return
	print("❌ COUNTER MISSED: Tapped counter button outside of a guard's strike window.")


# =============================================================================
#     13. PROCEDURAL TRAVERSAL CLIMB TELEPORTATION MATRIX [PDF: 0.1.23]
# =============================================================================
func execute_procedural_ledge_pull(target_landing_global_pos: Vector3) -> void:
	# Enforce a hard state lock to protect her from gravity and physics slips [PDF: 0.1.72]
	is_climbing = true
	velocity = Vector3.ZERO
	
	# Smoothly glide her capsule up and over the ledge curve using a high-performance Tween!
	var climb_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	climb_tween.tween_property(self, "global_position", target_landing_global_pos, 0.42)
	
	# Clean up and safely restore normal walking freedom upon arrival at the top deck
	climb_tween.chain().tween_callback(func():
		is_climbing = false
		velocity = Vector3.ZERO
		print("🥷 LOCOMOTION: Ledge mantle completed. Standard walking states restored.")
	)


# =============================================================================
#     🧭 UNIFIED AIM DIRECTION SANITIZER MATRIX [PDF: 0.1.74, 0.1.75]
# =============================================================================
func get_validated_aim_direction() -> Vector3:
	var final_target_direction: Vector3 = Vector3.ZERO
	
	# Look up the live cursor telemetry from your master crosshair component node
	var aim_node = get_node_or_null("Systems/AimController")
	if is_instance_valid(aim_node):
		final_target_direction = aim_node.aim_direction
		
	# If mouse tracking is inactive or empty, immediately fall back to your gamepad joystick vectors!
	if final_target_direction.length_squared() < 0.01:
		final_target_direction = controller_aim_direction
		
	# Emergency fallback: If both are dead, use her visual torso's front-facing axis heading
	if final_target_direction.length_squared() < 0.01 and is_instance_valid(eira_body_mesh):
		final_target_direction = -eira_body_mesh.global_transform.basis.z.normalized()
		
	# HARD LIMIT: Flatten the Y axis completely to prevent projectiles from firing deep into the floor!
	final_target_direction.y = 0.0
	
	if final_target_direction.length_squared() < 0.01:
		final_target_direction = -global_transform.basis.z.normalized()
		
	return final_target_direction.normalized()
