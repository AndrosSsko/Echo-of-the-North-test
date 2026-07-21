extends CharacterBody3D


enum LocomotionState { STANDARD, SPRINTING, AIR_PREP, SLIDING, STOMP_EXIT, CROUCHING }
var current_locomotion_mode: LocomotionState = LocomotionState.STANDARD
enum GadgetType { BOLA, TRAP, PEBBLE, SLIME, BOMB }

const BOLA_MAX_CHARGE_TIME: float = 1.5

@export var equipped_gadgets_deck: Array[GadgetResource] = []
var current_selected_gadget_index: int = 2

var current_ammo_deck_record: Dictionary = {
	"Pebble": 99,         # High baseline throw count for pebbles
	"Bola": 3,           # Maps directly to your 3 belt meshes
	"Dragon Slime": 4,    # Maps to your grease canister capacity check lines
	"Trip Wire": 0,       # Initialized to zero until you unlock the item scene
	"Spine Bomb": 0,      # Initialized to zero until you craft the asset card
	"Launcher": 0         # Initialized to zero until you build the trigger rig
}

const SHIELD_BACKPACK_POSITION: Vector3 = Vector3(-0.4, 0.2, 0.2)
const SHIELD_BACKPACK_ROTATION: Vector3 = Vector3(0.0, 0.0, 90.0)
const FLYING_SHIELD_SCENE = preload("res://scenes/flying_shield_fx.tscn")
const DRAGON_SLIME_CANISTER_SCENE = preload("res://scenes/dragon_slime_canister.tscn")



var current_selected_index: int = 0

@export_category("Tactile Hip Menu Tuning")
@export var mesh_menu_turn_speed: float = 11.0    # Turning friction speed when presenting hip
@export var menu_camera_zoom_fov: float = 45.0    # Focused Field of View for close-up inspection


@export_category("Viking Locomotion Tuning")
@export var sprint_speed_multiplier: float = 1.55
@export var slide_impulse_velocity: float = 18.0
@export var slide_friction_decay: float = 4.5

# --- New Shield Surf Parameters ---
@export_category("Shield Surf Tuning")
@export var base_slide_friction: float = 0.55
@export var slide_steer_speed: float = 4.2
@export var minimum_slide_boost: float = 14.5

# --- ARCHITECTURAL CONFIGURATION MATRIX ---
@export_category("Movement Core")
@export var movement_speed: float = 7.0
@export var crouch_speed: float = 3.2
@export var climb_speed: float = 3.0         # Cautious vertical climbing speed
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

# === 2. MULTI-PART RIG CONTAINER GROUP POINTERS ===
@onready var trap_rig: Node3D = $Trap_PCAM
@onready var slime_rig: Node3D = $Slime_PCAM
@onready var pebble_rig: Node3D = $Pebble_PCAM
@onready var bomb_rig: Node3D = $Bomb_PCAM

# === 3. ADVANCED INVENTORY AMMUNITION RESERVES ===
@export_category("Survival Inventory Settings")
@export var trap_ammo: int = 2
@export var slime_ammo: int = 4
@export var bomb_ammo: int = 1

# --- PRIVATE SYSTEM REFERENCES ---
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
# Tracking properties for twin-stick thumbstick aiming
var controller_aim_direction: Vector3 = Vector3.ZERO
var is_gadget_on_cooldown: bool = false
var current_selected_gadget: GadgetType = GadgetType.PEBBLE # Starts with Pebble equipped!
var base_fov: float = 70.0 
var is_player_currently_visible: bool = true
var active_highlighted_gadget: GadgetType = GadgetType.PEBBLE
var bola_charge_timer: float = 0.0


# Path tracking pointers aligned to your clean scenes directory folders
@export var pebble_blueprint: PackedScene
@export var dust_blueprint: PackedScene
var active_wind_zone: Area3D = null

# Master State Machine Flags
var is_rolling: bool = false
var is_attacking: bool = false
var is_crouching: bool = false
var is_climbing: bool = false          # Vertical wall traversal flag
var can_dodge: bool = true
var can_attack: bool = true

# Physics tracking loops parameters
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
	
	# Allow Eira to always process her inputs even when the 3D world physics is frozen!
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	camera_target_fov = 70.0
	camera_target_offset = Vector3.ZERO

	if is_instance_valid(melee_hitbox):
		melee_hitbox.hide() # Hides melee visualization until you attack
		
	

	update_physical_belt_mesh_visibility()

	# 1. Force the overworld exploration camera to win dominance at boot
	if is_instance_valid(exploration_pcam):
		exploration_pcam.priority = 30
		
	# 2. Force all close-up utility cameras to stay completely asleep (0)
	clear_all_gadget_camera_priorities()
	
	# 3. Synchronize your starting indices so code and UI match perfectly
	current_selected_gadget = GadgetType.PEBBLE
	menu_highlighted_gadget = GadgetType.PEBBLE
	active_highlighted_gadget = GadgetType.PEBBLE

	if has_node("CeilingCheck"):
		$CeilingCheck.add_exception(self) # Forces the ceiling raycast to ignore Eira!

	var start_back = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var start_hand = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	var start_feet = get_node_or_null("FeetMarker/FeetShieldMesh")
	
	if start_back: start_back.visible = true  # Back shield starts fully visible
	if start_hand: start_hand.visible = true  # Hand shield starts fully visible
	if start_feet: start_feet.visible = false # Feet surfboard mesh stays completely hidden until sliding

	current_selected_gadget_index = 2
	
	if is_instance_valid(gadget_manager):
		gadget_manager.initialize_manager(self)


func _physics_process(delta: float) -> void:
	# 1. TIME BUBBLE RECOVERY SYSTEM: Scales Eira's internal clock ticks inside slow-motion
	var _adjusted_delta: float = delta * (1.0 / Engine.time_scale) if radial_menu_active else delta
	
	var track_anchor_node = get_node_or_null("Camera_Track_Anchor")
	if is_instance_valid(track_anchor_node):
		if not radial_menu_active:
			track_anchor_node.global_transform.basis = global_transform.basis
		else:
			track_anchor_node.global_transform.basis = Basis.IDENTITY
			
	# 2. RADIAL SELECTION MENU REFRESH LOOP
	if radial_menu_active and is_radial_menu_open:
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * _adjusted_delta) 
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * _adjusted_delta) 
		move_and_slide() 
		evaluate_radial_wheel_joystick_navigation() 
		return 
	else:
		# Safety fallback flush: If the visual wheel isn't open, break the lock!
		radial_menu_active = false
		
	# 3. NATIVE ENVIRONMENTAL GRAVITY VECTOR COMPENSATOR
	if current_locomotion_mode == LocomotionState.AIR_PREP:
		var default_engine_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= default_engine_gravity * _adjusted_delta
	elif not is_on_floor():
		var default_engine_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= default_engine_gravity * _adjusted_delta
	else:
		velocity.y = -0.1 
		
	# Continuous weapon spin-up accumulator loops
	if is_actively_aiming_gadget:
		bola_charge_timer += _adjusted_delta
		
	# 4. CAMERA ACQUISITION SAFETY RAIL
	if not is_instance_valid(camera): 
		camera = get_viewport().get_camera_3d() if get_viewport() else null
		
	# 5. INPUT DIRECTION CAPTURE ENGINE
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Sprint Auto-Cancel Filter: Drop out of run state if keys are released
	if input_vector.length() < 0.1 and current_locomotion_mode == LocomotionState.SPRINTING:
		current_locomotion_mode = LocomotionState.STANDARD
		
	# 6. VERTICAL CLIMBING INTERCEPT MODULE
	if is_climbing:
		process_climbing_movement(input_vector, _adjusted_delta)
		move_and_slide()
		return
		
	# 7. ORIENTATION INTERACTION ALIGNMENT MATRIX
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
		
	# 8. SPRINT DEPLOY INTERCEPT MATRIX
	var is_sprint_button_held: bool = Input.is_action_pressed("sprint")
	if current_locomotion_mode == LocomotionState.STANDARD or current_locomotion_mode == LocomotionState.SPRINTING or current_locomotion_mode == LocomotionState.CROUCHING:
		if is_crouching or current_locomotion_mode == LocomotionState.CROUCHING:
			current_locomotion_mode = LocomotionState.CROUCHING
		else:
			if is_sprint_button_held and input_vector.length_squared() > 0.01:
				current_locomotion_mode = LocomotionState.SPRINTING
			else:
				current_locomotion_mode = LocomotionState.STANDARD
				
	# 9. CAMERA ENGINE FOV DYNAMICS
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
		
	# 10. ACTIVE LOCOMOTION STATE MACHINE HAND OFF
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
			
	# 11. ACTIVE SYSTEM MOTION DISPATCHER
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
	

	# 12. HOTKEY TRIGGER DETECTORS
	if Input.is_action_just_pressed("dodge_roll") and can_dodge and not is_rolling:
		initiate_dodge_roll(_direction)
	elif Input.is_action_just_pressed("attack_melee") and can_attack and not is_rolling:
		initiate_melee_strike()


func _process(delta: float) -> void:
	# Keep our modular aim calculation engine continuously updated
	if has_node("Systems/AimController"):
		$Systems/AimController.process_aim_logic(is_actively_aiming_gadget, bola_charge_timer, delta)
		var current_aim_dir = $Systems/AimController.aim_direction
		
		# Pass calculation results down to drive the mesh visibilities and scales seamlessly
		if has_node("Systems/IndicatorController"):
			$Systems/IndicatorController.update_visual_indicators(is_actively_aiming_gadget, current_aim_dir, bola_charge_timer, delta)


# --- VERTICAL WALL TRAVERSAL ENGINE ---
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

# --- UTILITY LEVEL REACTION HOOKS ---
func set_active_wind_zone(zone: Area3D) -> void:
	active_wind_zone = zone

func spawn_footstep_dust_cloud(forced: bool = false) -> void:
	# 1. Direct State Guard Rails
	if not forced and (is_crouching or is_climbing):
		return
		
	# CRITICAL CHECK: Prints a clear error in your Godot Output window if the slot is empty
	if not dust_blueprint:
		print("⚠️ PLAYER VFX ERROR: 'dust_blueprint' slot is EMPTY in the Inspector! Please drag your particle scene into it.")
		return

	# 2. Track World Floor Surface Surfaces via Raycast
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

	# 3. Instantiate Scene to World Node Hierarchy
	var dust_instance = dust_blueprint.instantiate()
	get_parent().add_child(dust_instance)
	dust_instance.global_position = global_position + Vector3(0.0, 0.05, 0.0)
	dust_instance.global_transform.basis = global_transform.basis
	
	# 4. FIXED: Duck-typing configuration to handle BOTH CPU & GPU particles seamlessly
	if "emitting" in dust_instance:
		dust_instance.emitting = false # Kill pre-fire cycles
		if dust_instance.has_method("restart"):
			dust_instance.restart() # Forces GPU engines to re-evaluate life cycles
		dust_instance.emitting = true
		
	# 5. FIXED: Type-Agnostic Safe Color Injection
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

	# 6. Lifecycle Management Safe House
	if dust_instance.has_signal("finished"):
		dust_instance.finished.connect(func(): dust_instance.queue_free())
	else:
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(dust_instance): dust_instance.queue_free())
	
	# 7. Acoustic Interaction Ripple 
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

var bola_blueprint = preload("res://scenes/stealth_bola.tscn")

func execute_pebble_throw() -> void:
	print("Eira throws a spinning weighted Bola gadget forward!")
	var bola_instance = bola_blueprint.instantiate()
	bola_instance.position = global_position + Vector3(0.0, 0.8, 0.0)
	get_parent().add_child(bola_instance)
	var forward_vector: Vector3 = -global_transform.basis.z.normalized()
	if bola_instance.has_method("initialize_bola_flight"):
		bola_instance.initialize_bola_flight(forward_vector)

func toggle_crouch_state() -> void:
	var target_crouch_state: bool = not is_crouching
	
	if target_crouch_state:
		# Enter Stealth Crouch parameters cleanly
		is_crouching = true
		current_locomotion_mode = LocomotionState.CROUCHING
		update_player_size(true)
	else:
		# FIXED: Completely wipes out the crouch state, returning full normal walking velocity!
		is_crouching = false
		current_locomotion_mode = LocomotionState.STANDARD
		update_player_size(false)
		
	print("TRACTION UPDATE: Stance changed. Active Crouch Flag = ", is_crouching, " | Locomotion Mode = ", current_locomotion_mode)

func update_player_size(crouching: bool) -> void:
	is_crouching = crouching
	
	# Fetch our standing collision node reference safely
	if is_instance_valid(collision_standing):
		var shape_ref = collision_standing.shape as CapsuleShape3D
		if shape_ref:
			if crouching:
				# 1. COMPRESS BOUNDS: Drop height to 0.9m for the crouch tuck
				shape_ref.height = 0.9
				
				# SHIFT COLLIDER UP: Keeps the bottom of the capsule perfectly flush with the ground!
				collision_standing.position.y = -0.425
				
				if is_instance_valid(camera): 
					camera.position.y = 0.65
				if has_node("FeetMarker"): 
					$FeetMarker.position.y = -0.45
			else:
				# 2. STANDARD PROFILE: Expand back to Eira's true 1.75m standing height
				shape_ref.height = 1.75
				
				# RESET COLLIDER POSITION: Snap physics center right back to middle mass
				collision_standing.position.y = 0.0
				
				if is_instance_valid(camera): 
					camera.position.y = 1.45
				if has_node("FeetMarker"): 
					$FeetMarker.position.y = -0.875
					
			velocity.y = 0.0 # Clean out stale vertical velocity stacks

	# --- FIXED VISUAL MESH DISTORTIONS ---
	if is_instance_valid(eira_body_mesh):
		if eira_body_mesh.mesh is CapsuleMesh:
			eira_body_mesh.mesh.height = 0.9 if crouching else 1.75
		eira_body_mesh.position.y = -0.225 if crouching else 0.0

func process_standard_movement(_direction: Vector3, delta: float) -> void:
	# 1. Slide along walls naturally if colliding to prevent clipping freezes
	if is_on_wall():
		_direction = _direction.slide(get_wall_normal()).normalized()

	# 2. Establish her true baseline traction speed parameters
	var _active_speed: float = movement_speed
	
	if current_locomotion_mode == LocomotionState.SPRINTING:
		_active_speed = movement_speed * sprint_speed_multiplier
	elif is_crouching or current_locomotion_mode == LocomotionState.CROUCHING:
		_active_speed = crouch_speed

	# 3. THE TRACTION INJECTION MATRIX
	if _direction.length_squared() > 0.001:
		if not is_actively_aiming_gadget and not is_controller_actively_aiming and is_instance_valid(eira_body_mesh):
			var look_angle: float = atan2(-_direction.x, -_direction.z)
			eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, look_angle, mesh_menu_turn_speed * delta)
		
		# Rotate her visual mesh model to face her walking direction naturally
		if not radial_menu_active and is_instance_valid(eira_body_mesh):
			var look_angle: float = atan2(-_direction.x, -_direction.z)
			eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, look_angle, mesh_menu_turn_speed * delta)
	else:
		# 4. CRISP ENVIRONMENT BRAKING CONTROL
		# Smooth deceleration brings her to a clean halt when inputs are empty
		velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)


	if radial_menu_active and is_instance_valid(eira_body_mesh) and is_instance_valid(camera):
		var camera_basis: Transform3D = camera.global_transform
		var camera_forward: Vector3 = -camera_basis.basis.z
		camera_forward.y = 0.0
		camera_forward = camera_forward.normalized()
		
		# Compute her flat forward direction vector cleanly
		var current_mesh_forward: Vector3 = -eira_body_mesh.global_transform.basis.z
		current_mesh_forward.y = 0.0
		current_mesh_forward = current_mesh_forward.normalized()
		
		var is_back_already_exposed: bool = current_mesh_forward.dot(camera_forward) > 0.0
		var target_presentation_angle: float = eira_body_mesh.global_rotation.y
		
		if not is_back_already_exposed:
			# Only calculate the screen back flip angle if her chest is blocking the lens!
			target_presentation_angle = atan2(camera_forward.x, camera_forward.z) + PI
		
		# GADGET TWIST OFFSETS: Symmetrical exposure alignment values
		match menu_highlighted_gadget:
			GadgetType.BOLA:   target_presentation_angle += deg_to_rad(45.0)
			GadgetType.TRAP:   target_presentation_angle += deg_to_rad(20.0)
			GadgetType.PEBBLE: target_presentation_angle += deg_to_rad(0.0)
			GadgetType.SLIME:  target_presentation_angle += deg_to_rad(-20.0)
			GadgetType.BOMB:   target_presentation_angle += deg_to_rad(-45.0)
		
		# Fluidly interpolate her visible visual skeleton using un-slowed delta pacing
		eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, target_presentation_angle, mesh_menu_turn_speed * delta)
		
		# Bring her horizontal physics body capsule speeds to a safe halt while browsing tool bags
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)

	if has_node("Aim_Line_Pointer") and $Aim_Line_Pointer.visible and not radial_menu_active and current_locomotion_mode != LocomotionState.SLIDING and current_locomotion_mode != LocomotionState.AIR_PREP:
		if is_instance_valid(eira_body_mesh) and is_instance_valid(camera):
			var target_aim_point: Vector3 = $Aim_Line_Pointer.global_position
			
			# 2. GENERATE THE FACING VECTOR: Find the horizontal line from her center to the target
			var look_vector: Vector3 = (target_aim_point - global_position).normalized()
			look_vector.y = 0.0 # Maintain perfectly flat horizon stability
			
			if look_vector.length_squared() > 0.01:
				# Calculate the precise angle needed to face your crosshair perfectly
				var desired_aim_angle: float = atan2(-look_vector.x, -look_vector.z)
				
				# 3. COMPEL EXTENT ROTATION: Force her skeleton and capsule to face the line!
				eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, desired_aim_angle, 14.0 * delta)
				global_rotation.y = lerp_angle(global_rotation.y, desired_aim_angle, 14.0 * delta)
				
				# 4. FIXED STRAFE TRACTION: If keys are held, overwrite normal mesh running angles 
				# to let her jog sideways/backward while keeping her shoulders pointed at the target!
				if _direction.length_squared() > 0.01:
					# This smoothly blends her capsule velocity along your WASD choices 
					# without letting her body break its aim lock to spin around
					var strafe_speed_multiplier: float = 0.85 # Slight tactical speed dampening while aiming
					velocity.x = lerp(velocity.x, _direction.x * (movement_speed * strafe_speed_multiplier), 12.0 * delta)
					velocity.z = lerp(velocity.z, _direction.z * (movement_speed * strafe_speed_multiplier), 12.0 * delta)


func initiate_melee_strike() -> void:
	was_crouching_on_attack = is_crouching
	is_attacking = true
	can_attack = false
	can_dodge = false
	attack_timer = attack_duration
	hitbox_collision.disabled = false
	if is_crouching:
		toggle_crouch_state()

func process_active_attack(_direction: Vector3, delta: float) -> void:
	attack_timer -= delta
	
	# Cleaned variable tracking names to clear engine bottlenecks instantly!
	var dampened_velocity: Vector3 = _direction * (movement_speed * attack_movement_dampening)
	
	velocity.x = lerp(velocity.x, dampened_velocity.x, acceleration * delta)
	velocity.z = lerp(velocity.z, dampened_velocity.z, acceleration * delta)
	
	if attack_timer <= 0.0: 
		is_attacking = false 
		can_dodge = true 
		if is_instance_valid(hitbox_collision): 
			hitbox_collision.set_deferred("disabled", true) 
		print("COMBAT SYSTEM: Axe strike animation concluded. Turning off weapon shapes.") 
		get_tree().create_timer(attack_cooldown).timeout.connect(func(): can_attack = true)
		get_tree().create_timer(attack_cooldown).timeout.connect(func():
			can_attack = true
		)

func _on_melee_hit_registered(collider: Node) -> void:
	if collider == self or collider.name == "Smudge":
		return
		
	# DUCK TYPING ENGAGED: Check if we are striking an intelligent guard clone
	if collider.is_in_group("EnemyGroup") and "current_phase" in collider:
		var current_suspicion = collider.current_suspicion_value if "current_suspicion_value" in collider else 0.0
		var guard_phase = collider.current_phase
		
		# --- CORE Blue-Print OVERRIDE Matrix ---
		# GHOST PATH: If undetected OR if the guard is currently tied up struggling in a Bola,
		# strike him exactly ONCE to trigger an instant cartoon knockout visual!
		if current_suspicion < 10.0 or guard_phase == collider.PatrolPhase.BOLA_STRUGGLE or guard_phase == collider.PatrolPhase.INVESTIGATING:
			print("STEALTH CRUNCH: Silent 1-hit takedown confirmed from the shadows!")
			if collider.has_method("execute_stealth_stun"):
				var push_direction: Vector3 = -global_transform.basis.z.normalized()
				collider.execute_stealth_stun(push_direction)
				grant_salvage_bonus()
			return
			
		# COMBAT PATH: If the enemy already has an active detection bar alert or is panicking,
		#Thump/Posture meter armor engages, forcing you to break his stance first!
		else:
			print("COMBAT BRAWL: Enemy guard is alert! Engaging Thump/Posture meter checks.")
			if collider.has_method("take_damage"):
				var push_direction: Vector3 = -global_transform.basis.z.normalized()
				if collider.get_method_argument_count("take_damage") >= 2:
					collider.take_damage(1, push_direction)
				else:
					collider.take_damage(1)
					
	# --- ENVIRONMENTAL FALLBACK PATHWAY ---
	# Handles hit connections against breakable walls or pottery props seamlessly
	elif collider.has_method("take_damage"):
		if collider.get_method_argument_count("take_damage") >= 2:
			collider.take_damage(1, -global_transform.basis.z.normalized())
		else:
			collider.take_damage(1)

func initiate_dodge_roll(_direction: Vector3) -> void:
	is_rolling = true
	can_dodge = false
	can_attack = false
	
	# === FIXED LOCOMOTION COMPASS ALIGNMENT: Un-flips vertical downward rolls! ===
	if _direction.length_squared() > 0.01:
		roll_direction = _direction.normalized()
	else:
		# If no keys were held, default the roll direction to her current visual forward heading vector
		if is_instance_valid(eira_body_mesh):
			roll_direction = -eira_body_mesh.global_transform.basis.z.normalized()
		else:
			roll_direction = -global_transform.basis.z.normalized()
			
	roll_timer = dodge_duration
	
	# Instantly snap her physical skeleton model to face her true roll heading direction vector
	if is_instance_valid(eira_body_mesh):
		var roll_look_angle: float = atan2(-roll_direction.x, -roll_direction.z)
		eira_body_mesh.global_rotation.y = roll_look_angle
		

func process_active_roll(delta: float) -> void:
	roll_timer -= delta
	velocity.x = roll_direction.x * dodge_speed
	velocity.z = roll_direction.z * dodge_speed
	if roll_timer <= 0.0:
		is_rolling = false
		velocity = Vector3.ZERO
		get_tree().create_timer(dodge_cooldown).timeout.connect(func(): can_dodge = true)

var is_parrying: bool = false

func execute_shield_parry() -> void:
	print("SHIELD SYSTEM: Deflection registered cleanly! Radiating parry pulse wave.")
	
	# Actively scan her surrounding 3D space radius coordinates for the attacking guard
	var space_state = get_world_3d().direct_space_state
	var parry_blast_sphere = PhysicsShapeQueryParameters3D.new()
	
	# Build an expanding 3-meter sphere blast to catch any nearby weapon hands
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 3.0
	parry_blast_sphere.shape_rid = sphere_shape.get_rid()
	parry_blast_sphere.transform = global_transform
	
	var intersections = space_state.intersect_shape(parry_blast_sphere)
	for hit in intersections:
		var obstacle_body = hit["collider"]
		if is_instance_valid(obstacle_body) and obstacle_body.is_in_group("EnemyGroup"):
			if obstacle_body.has_method("execute_disarm_parry_drop"):
				# LAUNCH DISARM ATTACK SIGNAL DIRECTLY DOWN TO HIS BRAIN!
				obstacle_body.execute_disarm_parry_drop()
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
		print("PARRY OVER: Defensive shield lowered.")
	)
	
var pebble_blueprint_file = preload("res://scenes/stealth_pebble.tscn")


func start_gadget_cooldown(time: float) -> void:
	is_gadget_on_cooldown = true
	get_tree().create_timer(time).timeout.connect(func(): is_gadget_on_cooldown = false)

func update_ammo_hud_display() -> void:
	if equipped_gadgets_deck.is_empty() or current_selected_gadget_index >= equipped_gadgets_deck.size():
		return
	var active_card = equipped_gadgets_deck[current_selected_gadget_index]
	if not is_instance_valid(active_card): return
	
	# 1. Update your digital UI trackers contextually off resource card configurations
	if is_instance_valid(ammo_label):
		match active_card.type:
			0: ammo_label.text = active_card.display_name + ": INF"
			1: ammo_label.text = active_card.display_name + ": " + str(current_bola_ammo) + " / " + str(max_bola_ammo)
			2: ammo_label.text = active_card.display_name + ": " + str(slime_ammo) + " / 4"
			_: ammo_label.text = active_card.display_name + ": Locked"
			
	update_physical_belt_mesh_visibility()
			
	# === 2. THE CHUNKY PHYSICAL GEAR AMMO ENFORCER ===
	# Dynamically reveals or hides the 3D rope bundles hanging off Eira's belt mesh!
	if is_instance_valid(hip_ammo_rig):
		
		# If pebbles are selected, hide all hip ropes to clean her active profiles
		if current_selected_gadget == GadgetType.PEBBLE:
			if is_instance_valid(bola_mesh_01): bola_mesh_01.visible = false
			if is_instance_valid(bola_mesh_02): bola_mesh_02.visible = false
			if is_instance_valid(bola_mesh_03): bola_mesh_03.visible = false
		else:
			# Turn them On or Off based directly on her actual current available ammo integers!
			if is_instance_valid(bola_mesh_01): bola_mesh_01.visible = (current_bola_ammo >= 1)
			if is_instance_valid(bola_mesh_02): bola_mesh_02.visible = (current_bola_ammo >= 2)
			if is_instance_valid(bola_mesh_03): bola_mesh_03.visible = (current_bola_ammo >= 3)
			
	# === 2. THE PHYSICAL VIKING AMMO RIG ENFORCER (GODOT 4.7+) ===
	# Dynamically reveals or hides the 3D rope models hanging off Eira's belt mesh!
	if is_instance_valid(hip_ammo_rig):
		# Fetch her individual coiled rope meshes inside the rig folder group [docs.godotengine.org]
		var bola_01 = hip_ammo_rig.get_node_or_null("Bola_Mesh_01")
		var bola_02 = hip_ammo_rig.get_node_or_null("Bola_Mesh_02")
		var bola_03 = hip_ammo_rig.get_node_or_null("Bola_Mesh_03")
		
		# If pebbles are selected, hide all hip ropes to clean her combat profiles
		if current_selected_gadget == GadgetType.PEBBLE:
			if is_instance_valid(bola_01): bola_01.visible = false
			if is_instance_valid(bola_02): bola_02.visible = false
			if is_instance_valid(bola_03): bola_03.visible = false
		else:
			# Drive visibilities based directly on her current integer counts!
			if is_instance_valid(bola_01): bola_01.visible = (current_bola_ammo >= 1)
			if is_instance_valid(bola_02): bola_02.visible = (current_bola_ammo >= 2)
			if is_instance_valid(bola_03): bola_03.visible = (current_bola_ammo >= 3)
			
	if is_instance_valid(ammo_label):
		if current_selected_gadget == GadgetType.PEBBLE:
			ammo_label.text = "Pebbles: INF"
		else:
			ammo_label.text = "Bolas: " + str(current_bola_ammo) + " / " + str(max_bola_ammo)
			
	# === COLD HARDBOUND VISIBILITY LOOP ===
	# Completely stripped the pebble hiding code! 
	# Your gorgeous 3D rope assets stay visible based purely on actual available ammo counts.
	if is_instance_valid(bola_mesh_01): bola_mesh_01.visible = (current_bola_ammo >= 1)
	if is_instance_valid(bola_mesh_02): bola_mesh_02.visible = (current_bola_ammo >= 2)
	if is_instance_valid(bola_mesh_03): bola_mesh_03.visible = (current_bola_ammo >= 3)


func _unhandled_input(event: InputEvent) -> void:
	# PATH A: Press F to activate aiming state parameters cleanly
	if event.is_action_pressed("use_gadget") and not radial_menu_active:
		is_actively_aiming_gadget = true
		bola_charge_timer = 0.0
		
	# PATH B: Release F to safely trigger launcher and wipe visual indicators
	elif event.is_action_released("use_gadget") and is_actively_aiming_gadget:
		is_actively_aiming_gadget = false
		
		if not equipped_gadgets_deck.is_empty() and current_selected_gadget_index < equipped_gadgets_deck.size():
			var active_card = equipped_gadgets_deck[current_selected_gadget_index]
			var ratio = clampf(bola_charge_timer / BOLA_MAX_CHARGE_TIME, 0.0, 1.0)
			
			if has_node("Systems/ProjectileLauncher") and current_ammo_deck_record[active_card.display_name] > 0:
				$Systems/ProjectileLauncher.fire_selected_gadget(active_card, self, ratio, indicator_rig)
				current_ammo_deck_record[active_card.display_name] -= 1
				
		if is_instance_valid(indicator_rig) and indicator_rig.has_node("Aim_Line_Pointer/Line_Visual"):
			indicator_rig.get_node("Aim_Line_Pointer/Line_Visual").scale = Vector3.ONE
			
		bola_charge_timer = 0.0
		update_ammo_hud_display()



func _input(event: InputEvent) -> void:
		# Mouse Scroll Wheel Selector Hook
	if radial_menu_active and event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_backpack_gadget(-1) # Moves left instantly
			manage_virtual_camera_priorities(menu_highlighted_gadget)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_backpack_gadget(1)  # Moves right instantly
			manage_virtual_camera_priorities(menu_highlighted_gadget)
			get_viewport().set_input_as_handled()
	
	# === 1. MELEE ATTACK CONTEXTUAL REDIRECTOR (UPDATED CHASSIS MAP) ===
	if event.is_action_pressed("attack_melee"):
		if event.is_echo(): return
		
		# THE ABSOLUTE PLAYER-SIDE HARD LOCK: 
		# Only allow a stealth execution intercept if Eira is actively crouching or sliding!
		if is_crouching and current_locomotion_mode != LocomotionState.SPRINTING:
			var target_guard: Node3D = null
			var guards = get_tree().get_nodes_in_group("EnemyGroup")
			
			for guard in guards:
				if is_instance_valid(guard) and "takedown_label_3d" in guard:
					# Check if the guard's prompt label node is actively visible right now
					if guard.takedown_label_3d and guard.takedown_label_3d.visible:
						target_guard = guard
						break
						
			if is_instance_valid(target_guard) and "takedown_label_3d" in target_guard:
				if "DANGER" in target_guard.takedown_label_3d.text:
					print("STEALTH BLOCKED: Guard is actively watched. Initiating open brawl!")
					# Let the code fall through normally below to fire your regular melee strike!
				else:
					print("STEALTH CRUNCH: Symmetrical check passed! Executing 1-hit knockout.")
					if target_guard.has_method("execute_stealth_stun"):
						var push_vector: Vector3 = -global_transform.basis.z.normalized()
						target_guard.execute_stealth_stun(push_vector)
					return # 👈 Exit early! This blocks her standard tool swinging animation layers.
					
		# FALLBACK: Execute a normal axe swing if standing or if the stealth strike is blocked
		if can_attack and not is_rolling:
			initiate_melee_strike()

	# === 2. SPRINT TOGGLE CONTROL (ISOLATED RUN SYSTEM) ===
	if event.is_action_pressed("sprint"):
		if event.is_echo(): return
		
		# If sliding, completely block Shift from doing anything! This prevents accidental cancel inputs.
		if current_locomotion_mode == LocomotionState.SLIDING or current_locomotion_mode == LocomotionState.AIR_PREP or current_locomotion_mode == LocomotionState.STOMP_EXIT:
			return
			
		# Standard locomotion state engine shifts
		if current_locomotion_mode == LocomotionState.SPRINTING:
			current_locomotion_mode = LocomotionState.STANDARD
		else:
			if not is_crouching and not is_climbing and not is_rolling:
				current_locomotion_mode = LocomotionState.SPRINTING


# === 3. UNIFIED SPRINT-SLIDE & WALK-CROUCH INTERCEPTOR AXIS ===
	if event.is_action_pressed("stealth_crouch"):
		if event.is_echo(): return
		if not is_rolling and not is_attacking and not is_climbing:
			
			match current_locomotion_mode:
				LocomotionState.SPRINTING:
				# Forcefully project her up into the air on frame one!
					velocity.y = 5.2 
					enter_air_prep_state()
				LocomotionState.SLIDING:
					execute_slide_cancel()
				_:
					toggle_crouch_state()

	# === 4. BODY DRAG & ENVIRONMENT SALVAGE ===
	if event.is_action_pressed("interact") and not radial_menu_active:
		handle_drag_interaction()
		
		# Proactively query a localized 3D sphere radius check to locate down guards
		var space_state = get_world_3d().direct_space_state
		var loot_query = PhysicsShapeQueryParameters3D.new()
		var search_sphere = SphereShape3D.new()
		search_sphere.radius = 2.0 # 2-meter physical arm search range footprint
		loot_query.shape_rid = search_sphere.get_rid()
		loot_query.transform = global_transform
		loot_query.exclude = [self.get_rid()]
		
		var contact_points = space_state.intersect_shape(loot_query)
		for hit in contact_points:
			var body_node = hit["collider"]
			if is_instance_valid(body_node) and body_node.is_in_group("EnemyGroup"):
				if "is_currently_lootable" in body_node and body_node.is_currently_lootable:
					# Enforce the single-loot security shutter lock
					body_node.is_currently_lootable = false
					body_node.has_already_been_looted = true
					
					# Extract inventory resource payouts
					var items_found_text: String = ""
					if "bola_ammo_to_award" in body_node and current_bola_ammo < max_bola_ammo:
						current_bola_ammo = clamped_addition_value(current_bola_ammo, body_node.bola_ammo_to_award, max_bola_ammo)
						items_found_text += " +1 Bola Trap"
					if "matches_to_award" in body_node and "current_matches" in self:
						self.current_matches += body_node.matches_to_award
						items_found_text += " +1 Campfire Match"
					print("LOOT PROGRESS: Extracted parts: ", items_found_text)
					
					# Refresh display trackers
					update_ammo_hud_display()
					if is_instance_valid(ammo_label):
						var punch = create_tween()
						ammo_label.scale = Vector2(1.3, 1.3)
						punch.tween_property(ammo_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC)
					if "alert_label" in body_node and is_instance_valid(body_node.alert_label):
						body_node.alert_label.text = "✖ EMPTY ✖"
						body_node.alert_label.modulate = Color("#888888")
					break



	# === 6. PASSIVE BACKPACK SHIELD PARRY ===
	if event.is_action_pressed("shield_parry"):
		if event.is_echo(): return
		if not is_rolling and not is_attacking and not is_climbing:
			execute_shield_parry()

# === 7. WEAPON WHEEL SWAP MENU ===
	if event.is_action_pressed("swap_gadget"):
		if event.is_echo(): return
		if not is_rolling and not is_climbing and current_locomotion_mode != LocomotionState.SLIDING:
			is_radial_menu_open = true
			radial_menu_active = true
			original_mesh_rotation_y = global_rotation.y 
			Engine.time_scale = 0.15 
			
			# Ensure the placeholder arm model wakes up and becomes visible instantly!
			if is_instance_valid(placeholder_hand_rig):
				placeholder_hand_rig.visible = true
			
			# === CONTEXT-AWARE BACK-TURN PRESENTATION ENGINES ===
			if is_instance_valid(eira_body_mesh) and is_instance_valid(camera):
				var camera_basis: Transform3D = camera.global_transform
				var camera_forward: Vector3 = -camera_basis.basis.z
				camera_forward.y = 0.0
				camera_forward = camera_forward.normalized()
				
				# Determine her exact active global heading facing direction angle
				var current_mesh_forward: Vector3 = -eira_body_mesh.global_transform.basis.z
				current_mesh_forward.y = 0.0
				current_mesh_forward = current_mesh_forward.normalized()
				
				# Calculate the dot product to see if she is already facing away from the camera view window!
				# A dot product value greater than 0.3 means her back is already pointing toward the screen lens mesh
				var is_back_already_exposed: bool = current_mesh_forward.dot(camera_forward) > 0.3
				
				# Baseline target angle faces her back straight at your screen normal vectors
				var target_angle: float = atan2(camera_forward.x, camera_forward.z) + PI
				
				if is_back_already_exposed:
					# If her gear pouches are already perfectly visible, maintain her posture heading!
					target_angle = eira_body_mesh.global_rotation.y
				
				# FIXED SLOW-MOTION TUNING: Padded transition glide speed (Feels heavy and deliberate!)
				var entrance_twist = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				# Removing Engine.time_scale from the calculation divider forces the tween to blend at normal human speed!
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
			
			# === SYNCHRONIZED RETRACTION EXIT TWEEN ===
			if is_instance_valid(eira_body_mesh):
				var mesh_reset = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				# Blends her body back to her normal running direction over 0.22 seconds
				mesh_reset.tween_property(eira_body_mesh, "rotation:y", 0.0, 0.22)
				
				# THE PERFECT RETRACTOR FUNCTION HOOK:
				# This callback fires the exact microsecond her body finishes straightening out,
				# hiding the neon hand indicator node cleanly when you return to standard overworld exploration!
				mesh_reset.tween_callback(func():
					if is_instance_valid(placeholder_hand_rig):
						placeholder_hand_rig.visible = false
						print("INVENTORY ENGINE: Selection concluded. Arm rig hidden.")
				)



func clamped_addition_value(current: int, incoming: int, limit: int) -> int:
	return min(current + incoming, limit) as int


		
func add_treasure_key_to_inventory() -> void:
	carried_treasure_keys_count += 1
	print("PLAYER BAG: Treasure keys carried: ", carried_treasure_keys_count)
	
func evaluate_radial_wheel_joystick_navigation() -> void:
	if not radial_menu_active: return
	
	# Read the Right Joystick via your existing "look" action inputs
	var look_vector_x: float = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	
	if abs(look_vector_x) > 0.6:
		if not controller_joystick_debounce:
			controller_joystick_debounce = true
			var direction: int = 1 if look_vector_x > 0 else -1
			
			cycle_backpack_gadget(direction)
			manage_virtual_camera_priorities(menu_highlighted_gadget)
	else:
		controller_joystick_debounce = false # Resets when stick returns to center # Resets when stick returns to center
		
func grant_salvage_bonus() -> void:
	if current_bola_ammo < max_bola_ammo:
		current_bola_ammo += 1
		
		# 1. Visual Popup
		var label = Label3D.new()
		label.text = "+1 BOLA"
		add_child(label)
		label.global_position = global_position + Vector3(0, 2.0, 0)
		
		# 2. Tween (Animation)
		var tween = create_tween()
		tween.tween_property(label, "position:y", 3.0, 0.5)
		tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
		tween.tween_callback(label.queue_free)
		
		# 3. Audio (Ensure you have a sound file path)
		var audio = AudioStreamPlayer3D.new()
		audio.stream = load("res://assets/sounds/metal_clink.wav")
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)


func handle_drag_interaction() -> void:
	if is_instance_valid(dragged_body):
		# DROP
		dragged_body.reparent(get_tree().root)
		dragged_body.velocity = Vector3.ZERO
		dragged_body = null
	else:
		# SEARCH AND DRAG
		for body in get_tree().get_nodes_in_group("EnemyGroup"):
			if body.global_position.distance_to(global_position) < 2.0:
				# We assume 2 is your STUNNED enum/constant
				if "current_phase" in body and body.current_phase == 2:
					dragged_body = body
					dragged_body.reparent(self) # Follows player
					dragged_body.position = Vector3(0, 0, -1.5) # Behind player
					# IMPORTANT: Add body to a specific group so AI sees it
					dragged_body.add_to_group("UnconsciousEnemy")
					break
					
func _on_cascade_sensor_body_entered(body: Node) -> void:
	# HIGH-UTILITY SAFE CHECK: Scans scene groups, ignoring internal node name variations!
	if body.is_in_group("EnemyGroup") and body != self:
		if body.has_method("execute_cascade_stumble_fall"):
			body.execute_cascade_stumble_fall()

func process_sliding_movement(delta: float) -> void:
	var dynamic_friction: float = base_slide_friction + 0.85
	var slope_angle: float = 0.0
	var slope_down_direction: Vector3 = Vector3.ZERO
	
	if is_instance_valid(ground_snapper) and ground_snapper.is_colliding():
		var floor_normal: Vector3 = ground_snapper.get_collision_normal()
		slope_down_direction = Vector3.DOWN.slide(floor_normal).normalized()
		slope_angle = Vector3.UP.angle_to(floor_normal)
		
		var forward_heading := -global_transform.basis.z
		var moving_uphill: bool = forward_heading.dot(slope_down_direction) < 0.0
		
		if slope_angle > 0.05:
			if moving_uphill:
				dynamic_friction += (slope_angle * 18.0)
			else:
				velocity += slope_down_direction * slope_angle * 24.0 * delta
				velocity -= floor_normal * 4.0

	# === FIXED CAMERA DIRECTION OVERHAUL (MATCHES process_standard_movement) ===
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.01 and is_instance_valid(camera):
		var cam_basis: Transform3D = camera.global_transform
		var right_dir: Vector3 = cam_basis.basis.x
		var forward_dir: Vector3 = -cam_basis.basis.z # FIXED VERTICAL INVERSION MATCH
		
		right_dir.y = 0.0
		forward_dir.y = 0.0
		right_dir = right_dir.normalized()
		forward_dir = forward_dir.normalized()
		
		var target_steering: Vector3 = (right_dir * input_vector.x) - (forward_dir * input_vector.y)
		
		if target_steering.length() > 0.01:
			var current_speed := velocity.length()
			velocity = velocity.lerp(target_steering.normalized() * current_speed, slide_steer_speed * delta)
			
			if is_instance_valid(eira_body_mesh):
				var look_angle: float = atan2(-velocity.x, -velocity.z)
				eira_body_mesh.global_rotation.y = lerp_angle(eira_body_mesh.global_rotation.y, look_angle, 8.0 * delta)

	velocity.x = move_toward(velocity.x, 0.0, dynamic_friction * slide_friction_decay * delta)
	velocity.z = move_toward(velocity.z, 0.0, dynamic_friction * slide_friction_decay * delta)
	move_and_slide()
	
	if Vector3(velocity.x, 0, velocity.z).length() < 3.8:
		enter_stomp_exit_state()


func enter_air_prep_state() -> void:
	current_locomotion_mode = LocomotionState.AIR_PREP
	velocity.y = 5.2 
	
	var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	if back_mesh: back_mesh.visible = false
	if hand_mesh: hand_mesh.visible = false
	
	update_physical_belt_mesh_visibility()

func enter_sliding_state() -> void:
	current_locomotion_mode = LocomotionState.SLIDING
	is_crouching = false
	update_player_size(true)
	
	var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")
	
	if back_mesh: back_mesh.visible = false
	if hand_mesh: hand_mesh.visible = false
	if feet_mesh: feet_mesh.visible = true
	
	# === FIXED CAMERA-RELATIVE IMPULSE INITIALIZATION BOOST ===
	# We dynamically calculate your input directions right at the frame split second you launch the slide!
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var launch_direction := -global_transform.basis.z # Default fallback heading
	
	if input_vector.length_squared() > 0.01 and is_instance_valid(camera):
		var cam_basis: Transform3D = camera.global_transform
		var right_dir: Vector3 = cam_basis.basis.x
		var forward_dir: Vector3 = -cam_basis.basis.z
		right_dir.y = 0.0
		forward_dir.y = 0.0
		var target_launch: Vector3 = (right_dir.normalized() * input_vector.x) - (forward_dir.normalized() * input_vector.y)
		if target_launch.length_squared() > 0.01:
			launch_direction = target_launch.normalized()
			
	# Inject the speed boost vector directly along your true active heading vector
	velocity.x = launch_direction.x * minimum_slide_boost
	velocity.z = launch_direction.z * minimum_slide_boost
	velocity.y = 0.0
			
	spawn_footstep_dust_cloud(true)

func enter_stomp_exit_state() -> void:
	current_locomotion_mode = LocomotionState.STOMP_EXIT
	is_crouching = false
	update_player_size(false)
	
	velocity.y = 6.2 
	
	var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")
	
	if feet_mesh: feet_mesh.visible = false
	if hand_mesh: hand_mesh.visible = false
	
	var flying_shield_fx := FLYING_SHIELD_SCENE.instantiate()
	get_tree().current_scene.add_child(flying_shield_fx)
	
	if feet_mesh and back_mesh:
		var safe_launch_position = feet_mesh.global_position + Vector3(0.0, 0.4, 0.2)
		flying_shield_fx.scale = Vector3(1.0, 1.0, 1.0)
		flying_shield_fx.launch(safe_launch_position, self, velocity * 0.35)
		
		get_tree().create_timer(0.45).timeout.connect(func():
			if is_instance_valid(back_mesh) and current_locomotion_mode != LocomotionState.SLIDING:
				back_mesh.visible = true
		)
		
	current_locomotion_mode = LocomotionState.STANDARD


func execute_slide_cancel() -> void:
	var is_ceiling_blocked: bool = false
	var ceiling_node = get_node_or_null("CeilingCheck")
	if ceiling_node and ceiling_node.is_colliding():
		is_ceiling_blocked = true
		
	if not is_ceiling_blocked:
		update_player_size(false)
		is_crouching = false
		current_locomotion_mode = LocomotionState.STANDARD
		
		var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
		var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
		var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")
		
		if feet_mesh: feet_mesh.visible = false
		if hand_mesh: hand_mesh.visible = false
		if back_mesh: back_mesh.visible = true
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
		var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
		var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
		var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")
		
		if feet_mesh: feet_mesh.visible = false
		if hand_mesh: hand_mesh.visible = false
		if back_mesh: back_mesh.visible = true
		velocity.y = 0.0

func cycle_backpack_gadget(direction: int) -> void:
	var target_index: int = current_selected_gadget_index + direction
	
	# Clamp our absolute inventory boundaries tightly between index 0 and 4
	if target_index < 0 or target_index > 4:
		print("INVENTORY MOTOR: Hit terminal belt boundary wall.")
		return
		
	# === AAA INTERCEPT MATRIX: SKIP EMPTY SLOTS AUTOMATICALLY ===
	# If you scroll into an unbuilt gadget slot, keep moving in that direction 
	# until we land safely back onto a valid, active .tres resource card!
	while target_index >= 0 and target_index <= 4 and (target_index >= equipped_gadgets_deck.size() or not is_instance_valid(equipped_gadgets_deck[target_index])):
		target_index += direction
		
	# Boundary check fallback if skipping pushes Eira past her pouch limits
	if target_index < 0 or target_index > 4 or target_index >= equipped_gadgets_deck.size() or not is_instance_valid(equipped_gadgets_deck[target_index]):
		print("INVENTORY MOTOR: Cannot scroll further, no valid gadgets equipped in this direction.")
		return
		
	# Apply our verified, non-null slot coordinate selection safely
	current_selected_gadget_index = target_index
	print("INVENTORY MOTOR: Active selection slot index changed to: ", current_selected_gadget_index)
	

	
	
	# Convert our current active enum selection state straight into an index integer
	var _current_index: int = int(menu_highlighted_gadget)

	
	# === THE NO-LOOP GATED ENTRY SYSTEM ===
	# If scrolling moves the cursor past the far left (0) or far right (4),
	# intercept the event and exit immediately without altering any variables!
	if target_index < 0 or target_index > 4:
		# Flash a console note for visual debugging confirmation
		print("INVENTORY ENGINE: Hit a terminal boundary wall! Use opposite input direction.")
		return
		
	# Apply your newly verified index slot safely since it sits inside the safe zone bounds
	menu_highlighted_gadget = target_index as GadgetType
	active_highlighted_gadget = menu_highlighted_gadget # Keep system trackers mirrored
	
	# Dynamically wake up your virtual camera nodes based on the new scroll choice
	manage_virtual_camera_priorities(menu_highlighted_gadget)
	


func manage_virtual_camera_priorities(target_gadget: GadgetType) -> void:
	if not is_radial_menu_open:
		if is_instance_valid(exploration_pcam): exploration_pcam.priority = 30
		return

	if is_instance_valid(exploration_pcam): exploration_pcam.priority = 0
		
	# Reset baselines
	if is_instance_valid(bola_pcam): bola_pcam.priority = 0
	if is_instance_valid(trap_pcam): trap_pcam.priority = 0
	if is_instance_valid(pebble_pcam): pebble_pcam.priority = 0
	if is_instance_valid(slime_pcam): slime_pcam.priority = 0
	if is_instance_valid(bomb_pcam): bomb_pcam.priority = 0
	
	# Wake up the precise camera node corresponding to your new layout structure!
	match target_gadget:
		GadgetType.BOLA:
			if is_instance_valid(bola_pcam): bola_pcam.priority = 25
			morph_camera_track_finish_line(left_hip_marker) # === INJECT THE PLACEMENT TRIGGERS! ===
		GadgetType.TRAP:
			if is_instance_valid(trap_pcam): trap_pcam.priority = 25
			morph_camera_track_finish_line(waist_left_marker)
		GadgetType.PEBBLE:
			if is_instance_valid(pebble_pcam): pebble_pcam.priority = 25
			morph_camera_track_finish_line(waist_center_marker)
		GadgetType.SLIME:
			if is_instance_valid(slime_pcam): slime_pcam.priority = 25
			morph_camera_track_finish_line(waist_right_marker)
		GadgetType.BOMB:
			if is_instance_valid(bomb_pcam): bomb_pcam.priority = 25
			morph_camera_track_finish_line(right_hip_marker)
	
func update_physical_belt_mesh_visibility() -> void:
	# 1. STEPPED BOLA REMOVALS: Displays individual rope bundles based on true ammo counts
	if is_instance_valid(bola_mesh_01): bola_mesh_01.visible = (current_bola_ammo >= 1)
	if is_instance_valid(bola_mesh_02): bola_mesh_02.visible = (current_bola_ammo >= 2)
	if is_instance_valid(bola_mesh_03): bola_mesh_03.visible = (current_bola_ammo >= 3)
	
	# 2. MULTI-PART RIG CONTAINER TOGGLES: Pouch meshes vanish when completely empty
	if is_instance_valid(trap_rig): trap_rig.visible = (trap_ammo > 0)
	if is_instance_valid(slime_rig): slime_rig.visible = (slime_ammo > 0)
	if is_instance_valid(pebble_rig): pebble_rig.visible = true # Infinite pebbles stay on always
	if is_instance_valid(bomb_rig): bomb_rig.visible = (bomb_ammo > 0)

	# 3. SURF & PARRIES SHIELD VISIBILITY CONTROL MATRIX
	var back_mesh = get_node_or_null("EiraVisualCapsuleMesh/BackShieldMesh")
	var hand_mesh = get_node_or_null("EiraVisualCapsuleMesh/HandShieldMesh")
	var feet_mesh = get_node_or_null("FeetMarker/FeetShieldMesh")

	# CHECK ACTIVE CONDITIONS: Are we surfing or preparing a mid-air drop?
	if current_locomotion_mode == LocomotionState.SLIDING or current_locomotion_mode == LocomotionState.AIR_PREP:
		if back_mesh: back_mesh.visible = false
		if hand_mesh: hand_mesh.visible = false
		if feet_mesh: feet_mesh.visible = true # Feet surfboard becomes the only visible shield mesh
	else:
		# STANDARD EXPLORATION LAYOUT: Reset parameters back to standard overworld idling
		if back_mesh: back_mesh.visible = true
		if feet_mesh: feet_mesh.visible = false
		
		# PARRY DECOUPLE GATE: Hand shield is strictly hidden unless actively blocking/parrying
		if hand_mesh: 
			hand_mesh.visible = is_parrying

func clear_all_gadget_camera_priorities() -> void:
	# 1. Force your Overworld gameplay camera back up to full control tier on exit
	if is_instance_valid(exploration_pcam):
		exploration_pcam.priority = 30
		
	# Instantly drop priority weights down to zero
	if is_instance_valid(bola_pcam): bola_pcam.priority = 0
	if is_instance_valid(trap_pcam): trap_pcam.priority = 0
	if is_instance_valid(slime_pcam): slime_pcam.priority = 0
	if is_instance_valid(pebble_pcam): pebble_pcam.priority = 0
	if is_instance_valid(bomb_pcam): bomb_pcam.priority = 0


func morph_camera_track_finish_line(target_marker: Marker3D) -> void:
	if not is_instance_valid(target_marker) or not is_instance_valid(placeholder_hand_rig): 
		return
		
	# TACTILE HAND TRANSITION MOTOR
	var arm_cleanup = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# FIXED COORDINATES: Pulls the local offset parameters to track her bones natively!
	arm_cleanup.tween_property(
		placeholder_hand_rig, 
		"position", 
		target_marker.position, 
		0.12
	)


func trigger_dedicated_pouch_camera_swap() -> void:
	# 1. Fetch your pre-built Virtual Camera nodes directly from your scene tree
	var bola_cam = get_node_or_null("Bola_PCAM") # Change paths if they live inside a folder node!
	var pebble_cam = get_node_or_null("Pebble_PCAM")
	var slime_cam = get_node_or_null("Slime_PCAM")
	
	# Reset all camera priorities back down to 0 so they don't fight for dominance
	if is_instance_valid(bola_cam): bola_cam.priority = 0
	if is_instance_valid(pebble_cam): pebble_cam.priority = 0
	if is_instance_valid(slime_cam): slime_cam.priority = 0
	
	# 2. Wake up the specific camera matching our current left-to-right selection index!
	match current_selected_gadget_index:
		0: # Slot 0: Bola (Left Hip)
			if is_instance_valid(bola_cam): bola_cam.priority = 25
		1: # Slot 1: Pebble (Waist Center)
			if is_instance_valid(pebble_cam): pebble_cam.priority = 25
		2: # Slot 2: Dragon Slime (Right Hip)
			if is_instance_valid(slime_cam): slime_cam.priority = 25
