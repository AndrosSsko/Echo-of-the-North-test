extends CharacterBody3D


enum LocomotionState { STANDARD, SPRINTING, SLIDING }
var current_locomotion_mode: LocomotionState = LocomotionState.STANDARD

@export_category("Viking Locomotion Tuning")
@export var sprint_speed_multiplier: float = 1.55
@export var slide_impulse_velocity: float = 18.0
@export var slide_friction_decay: float = 4.5

var slide_duration_timer: float = 0.0


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

# --- PRIVATE SYSTEM REFERENCES ---

@onready var core_capsule_collision: CollisionShape3D = $Collision_Standing
@onready var collision_standing: CollisionShape3D = $Collision_Standing
@onready var collision_sliding: CollisionShape3D = $Collision_Sliding
@export var camera: Camera3D
@onready var melee_hitbox: Area3D = $Melee_Hitbox
@onready var hitbox_collision: CollisionShape3D = $Melee_Hitbox/CollisionShape3D
@onready var player_collision: CollisionShape3D = $Collision_Standing
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
@onready var aim_line_visual: Node3D = $Aim_Line_Pointer
@onready var ground_snapper: RayCast3D = $GroundSnapper
@onready var ammo_label: Label = $"../HUD/Ammo_Container/Ammo_Tracker"
@onready var radial_wheel_panel: Panel = $"../HUD/Radial_Wheel_UI"
@onready var radial_title_label: RichTextLabel = $"../HUD/Radial_Wheel_UI/Selection_Title_Text"
@onready var heart_icons: Array = [
	$"../HUD/Health_Container/Heart_01",
	$"../HUD/Health_Container/Heart_02",
	$"../HUD/Health_Container/Heart_03"
]
@onready var shield_skate_rig: Node3D = $Shield_Skate_Rig
@export_category("Inventions Bag")
@export var max_bola_ammo: int = 3
@export var pebble_throw_cooldown: float = 0.8
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
# Unified non-lethal gadget inventory selector machine
enum GadgetType { PEBBLE, BOLA }
var current_selected_gadget: GadgetType = GadgetType.PEBBLE # Starts with Pebble equipped!

var is_player_currently_visible: bool = true

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

func _physics_process(delta: float) -> void:
	if not is_instance_valid(camera):
		var cameras = get_tree().get_nodes_in_group("MainCamera")
		if cameras.size() > 0:
			camera = cameras[0] as Camera3D

			print("PLAYER ENGINE: Found MainCamera! Trajectory systems fully synchronized.")
		return # Skip this physics frame tick until the camera is completely ready!
	
	# --- CAMERA ENGINE ---
	if is_instance_valid(camera):
		camera.fov = lerp(camera.fov, camera_target_fov, 10.0 * delta)
		var p0: Vector3 = Vector3(0.0, 4.5, 6.0)
		var p2: Vector3 = Vector3(0.5, 1.3, 2.5) + camera_target_offset
		var p1: Vector3 = Vector3(3.6, 5.2, 5.5)
		
		if radial_menu_active:
			camera_curve_timer = move_toward(camera_curve_timer, 1.0, 3.5 * delta)
		else:
			camera_curve_timer = move_toward(camera_curve_timer, 0.0, 4.5 * delta)
			
		var t: float = camera_curve_timer
		var curved_bezier_position: Vector3 = (1.0 - t)*(1.0 - t)*p0 + 2.0*(1.0 - t)*t*p1 + t*t*p2
		camera.position = curved_bezier_position

# --- STATES & MOVEMENT ---
	if radial_menu_active:
		velocity = Vector3.ZERO
		move_and_slide()
		evaluate_radial_wheel_joystick_navigation()
		return
	
	# === SHIELD-SURF / SLIDE STATE MACHINE (FIXED GROUND ANCHORS) ===
	if current_locomotion_mode == LocomotionState.SLIDING:
		# --- DYNAMIC SLIDE-CANCEL DODGE INTERCEPTOR ---
		# Catches your spacebar or controller clicks mid-slide, un-freezing your agility instantly!
		if Input.is_action_just_pressed("dodge_roll"):
			var roll_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			var roll_dir: Vector3 = Vector3.ZERO
			
			if roll_input.length_squared() > 0.01 and is_instance_valid(camera):
				# A. USER DIR PATH: If the stick is pushed, roll toward the requested angle input
				var cam_basis: Transform3D = camera.global_transform
				roll_dir = (cam_basis.basis.x * roll_input.x + -cam_basis.basis.z * roll_input.y)
				roll_dir.y = 0.0
				roll_dir = roll_dir.normalized()
			else:
				# B. MOMENTUM TRAJECTORY PATHWAY: If hands are off the stick, 
				# roll FORWARD along her active sliding velocity vector heading!
				roll_dir = velocity.normalized()
				roll_dir.y = 0.0
			
			initiate_dodge_roll(roll_dir)
			return # Break out of the slide loop frame immediately!

		slide_duration_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, slide_friction_decay * delta)
		velocity.z = move_toward(velocity.z, 0.0, slide_friction_decay * delta)
		
		# --- THE FIXED GROUND ANCHOR ENGINE ---
		# Replaced your conflicting GroundSnapper lerp loops entirely!
		# This cleanly forces her downward vectors onto native gravity tracks, keeping her flat.
		if not is_on_floor():
			velocity.y += get_gravity().y * delta
		else:
			velocity.y = 0.0
			
		# --- CAMERA SURF TILT ---
		if is_instance_valid(camera):
			camera.rotation.z = lerp_angle(camera.rotation.z, deg_to_rad(3.5), 8.0 * delta)
			
		# --- EXIT TRAJECTORY CHECK ---
		if slide_duration_timer <= 0.0 or velocity.length_squared() < 4.0:
			exit_viking_slide_state()
			
		move_and_slide()
		return # Safe breakout block remains running cleanly for normal slide frames

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# --- SPRINT AUTO-CANCEL ---
	# If player stops moving, force sprint off
	if input_vector.length() < 0.1 and current_locomotion_mode == LocomotionState.SPRINTING:
		current_locomotion_mode = LocomotionState.STANDARD
	
	if is_climbing:
		process_climbing_movement(input_vector, delta)
		move_and_slide()
		return
		
	var camera_transform: Transform3D = camera.global_transform
	var forward_direction: Vector3 = camera_transform.basis.z
	var right_direction: Vector3 = camera_transform.basis.x
	forward_direction.y = 0.0
	right_direction.y = 0.0
	forward_direction = forward_direction.normalized()
	right_direction = right_direction.normalized()
	
	var target_direction: Vector3 = (right_direction * input_vector.x) + (forward_direction * input_vector.y)

	# 2. EVALUATE SPRINT INTERCEPT MAP TRIGGERS
	var is_sprint_button_held: bool = Input.is_action_pressed("sprint")
	if is_sprint_button_held and velocity.length_squared() > 0.1 and not is_crouching:
		current_locomotion_mode = LocomotionState.SPRINTING
	else:
		current_locomotion_mode = LocomotionState.STANDARD


	# --- AIM INPUT DETECTION ---
	if is_instance_valid(camera):
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, 8.0 * delta)

	# --- AIM INPUT DETECTION ---
	var aim_vector: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	is_controller_actively_aiming = aim_vector.length_squared() > 0.15
	
	if is_controller_actively_aiming:
		var cam_basis: Transform3D = camera.global_transform
		controller_aim_direction = (cam_basis.basis.x * aim_vector.x + cam_basis.basis.z * aim_vector.y)
		controller_aim_direction.y = 0.0
		controller_aim_direction = controller_aim_direction.normalized()
	else:
		controller_aim_direction = Vector3.ZERO

	# --- MOTION CALCULATIONS ---
	if is_rolling:
		process_active_roll(delta)
	elif is_attacking:
		process_active_attack(target_direction, delta)
	else:
		process_standard_movement(target_direction, delta)
		
	if Input.is_action_just_pressed("dodge_roll") and can_dodge and not is_rolling:
		initiate_dodge_roll(target_direction)
	elif Input.is_action_just_pressed("attack_melee") and can_attack and not is_rolling:
		initiate_melee_strike()
			
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0
		
	move_and_slide()

# --- NEW: VISUAL UPDATE LOOP ---
func _process(_delta: float) -> void:
	update_aim_line_visual()

func update_aim_line_visual() -> void:
	if not is_instance_valid(aim_line_visual): return
	if not is_instance_valid(camera): return # ADD THIS LINE
	
	# Determine if we should be aiming
	var should_aim = is_actively_aiming_gadget or is_controller_actively_aiming
	aim_line_visual.visible = should_aim

	if should_aim:
		var target_rot_y: float = 0.0
		
		if is_controller_actively_aiming:
			target_rot_y = atan2(-controller_aim_direction.x, -controller_aim_direction.z)
		else:
			# Raycast to ground plane for mouse aiming
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_normal = camera.project_ray_normal(mouse_pos)
			var plane = Plane(Vector3.UP, global_position.y)
			var target_point = plane.intersects_ray(ray_origin, ray_normal)
			
			if target_point:
				var dir = (target_point - global_position).normalized()
				target_rot_y = atan2(-dir.x, -dir.z)
		
		# Smoothly rotate the pointer (The RemoteTransform3D handles the position!)
		rotation.y = lerp_angle(rotation.y, target_rot_y, 0.5)

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
	# Simply flip the current state and pass it to the helper
	update_player_size(!is_crouching)

func update_player_size(crouching: bool) -> void:
	is_crouching = crouching
	
	# THE DEFINITIVE COLLISION NODE SWITCH:
	# Toggling pre-compiled nodes whose centers are identically aligned (Y: 0.0)
	# completely eliminates the frame-1 position shifts that cause floor-falling bugs!
	if is_instance_valid(collision_standing) and is_instance_valid(collision_sliding):
		collision_standing.disabled = crouching
		collision_sliding.disabled = not crouching
		
	# Smoothly scale her 3D visual mesh model so she looks low-profile
	var target_height: float = 0.9 if crouching else 1.8
	var target_pos_y: float = 0.0 # Origin stays locked on the ground level!
	
	if is_instance_valid(player_mesh) and player_mesh.mesh is CapsuleMesh:
		player_mesh.mesh.height = target_height
		player_mesh.position.y = target_pos_y
		


func process_standard_movement(target_direction: Vector3, delta: float) -> void:
	if is_on_wall(): target_direction = target_direction.slide(get_wall_normal()).normalized()
	
	# 3. APPLY SPEED MULTIPLIERS BASED ON THE RUNTIME STATE
	var active_movement_speed: float = movement_speed
	if current_locomotion_mode == LocomotionState.SPRINTING:
		active_movement_speed *= sprint_speed_multiplier
	elif is_crouching:
		active_movement_speed *= 0.5 # Crouch speed penalty
		
	var target_velocity_xz: Vector3 = target_direction * active_movement_speed
	
	# Use velocity.lerp for smoother, controlled acceleration
	velocity.x = lerp(velocity.x, target_velocity_xz.x, acceleration * delta)
	velocity.z = lerp(velocity.z, target_velocity_xz.z, acceleration * delta)
	
	if target_direction.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-target_direction.x, -target_direction.z), rotation_speed * delta)

func initiate_melee_strike() -> void:
	was_crouching_on_attack = is_crouching
	is_attacking = true
	can_attack = false
	can_dodge = false
	attack_timer = attack_duration
	hitbox_collision.disabled = false
	if is_crouching:
		toggle_crouch_state()

func process_active_attack(target_direction: Vector3, delta: float) -> void:
	attack_timer -= delta
	var dampened_velocity: Vector3 = target_direction * (movement_speed * attack_movement_dampening)
	velocity.x = lerp(velocity.x, dampened_velocity.x, acceleration * delta)
	velocity.z = lerp(velocity.z, dampened_velocity.z, acceleration * delta)
	
	if attack_timer <= 0.0:
		is_attacking = false
		can_dodge = true
		if is_instance_valid(hitbox_collision):
			hitbox_collision.set_deferred("disabled", true)
		print("COMBAT SYSTEM: Axe strike animation concluded. Turning off weapon shapes.")
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

func initiate_dodge_roll(target_direction: Vector3) -> void:
	# If she is currently sliding on her shield, close down the slide state 
	# and recall her shield board back to her shoulder BEFORE processing the roll
	if current_locomotion_mode == LocomotionState.SLIDING:
		exit_viking_slide_state()
		print("TACTICAL FLOW: Shield slide canceled directly into an agile roll!")

	is_rolling = true
	can_dodge = false
	roll_timer = dodge_duration
	
	# Force stand up if crouching
	if is_crouching:
		update_player_size(false)
		
	if target_direction.length_squared() < 0.001:
		roll_direction = -global_transform.basis.z.normalized()
	else:
		roll_direction = target_direction.normalized()
		
	velocity.x = roll_direction.x * dodge_speed
	velocity.z = roll_direction.z * dodge_speed
	rotation.y = atan2(-roll_direction.x, -roll_direction.z)
	spawn_footstep_dust_cloud()

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

func execute_unified_gadget_fire() -> void:
	if is_gadget_on_cooldown: return
	
	# 1. CALCULATE AIM DIRECTION
	var target_facing_vector: Vector3 = -global_transform.basis.z.normalized()
	
	# Mouse Aiming Logic (with camera safety check)
	if Input.get_connected_joypads().size() == 0:
		if is_instance_valid(camera):
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
			var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + (ray_normal * 100.0))
			query.exclude = [self.get_rid()]
			var result = space_state.intersect_ray(query)
			
			if not result.is_empty():
				var dir_to_mouse: Vector3 = (result["position"] - global_position)
				dir_to_mouse.y = 0.0
				if dir_to_mouse.length_squared() > 0.1:
					target_facing_vector = dir_to_mouse.normalized()
					rotation.y = atan2(-target_facing_vector.x, -target_facing_vector.z)
	else:
		if controller_aim_direction.length_squared() > 0.1:
			target_facing_vector = controller_aim_direction
			rotation.y = atan2(-target_facing_vector.x, -target_facing_vector.z)

	# 2. EXECUTE GADGET BASED ON CALCULATED DIRECTION
	match current_selected_gadget:
		GadgetType.PEBBLE:
			# Use the global cooldown system instead of the unreliable 'can_throw_pebble' flag
			if is_gadget_on_cooldown: return
			
			can_throw_pebble = false
			print("PEBBLE DISPATCH: Throwing distraction pebble!")
			
			var pebble_instance = pebble_blueprint.instantiate() as RigidBody3D
			pebble_instance.position = global_position + Vector3(0.0, 0.8, 0.0) + (target_facing_vector * 0.6)
			get_parent().add_child(pebble_instance)
			pebble_instance.add_collision_exception_with(self)
			
			var throw_vector: Vector3 = (target_facing_vector + Vector3(0.0, 0.35, 0.0)).normalized()
			if is_instance_valid(active_wind_zone):
				var combined_wind_vector: Vector3 = (throw_vector + active_wind_zone.wind_direction.normalized()).normalized()
				pebble_instance.apply_central_impulse(combined_wind_vector * (throw_impulse_force + active_wind_zone.wind_velocity_boost))
			else:
				pebble_instance.apply_central_impulse(throw_vector * throw_impulse_force)
				
			# Use the unified cooldown function defined earlier in your script
			start_gadget_cooldown(pebble_throw_cooldown)
			
		GadgetType.BOLA:
			if current_bola_ammo <= 0: return
				
			var bola_instance = bola_blueprint.instantiate()
			# Spawn with a forward offset so it doesn't collide with the player
			bola_instance.position = global_position + Vector3(0.0, 0.8, 0.0) + (target_facing_vector * 0.6)
			
	
			get_parent().add_child(bola_instance)
			
			if bola_instance.has_method("initialize_bola_flight"):
				bola_instance.initialize_bola_flight(target_facing_vector)
				
			current_bola_ammo -= 1
			update_ammo_hud_display()
			start_gadget_cooldown(1.0)

func start_gadget_cooldown(time: float) -> void:
	is_gadget_on_cooldown = true
	get_tree().create_timer(time).timeout.connect(func(): is_gadget_on_cooldown = false)

func update_ammo_hud_display() -> void:
	if is_instance_valid(ammo_label):
		if current_selected_gadget == GadgetType.PEBBLE:
			ammo_label.text = "Pebbles: INF"
		else:
			ammo_label.text = "Bolas: " + str(current_bola_ammo) + " / " + str(max_bola_ammo)


func _input(event: InputEvent) -> void:
	
	if event.is_echo(): return

# === UNIFIED IN-GAME SPRINT-SLIDE & WALK-CROUCH INTERCEPTOR AXIS ===
# SPRINT TOGGLE
	if event.is_action_pressed("sprint"):
		if current_locomotion_mode == LocomotionState.SPRINTING:
			current_locomotion_mode = LocomotionState.STANDARD
		else:
			current_locomotion_mode = LocomotionState.SPRINTING
	
	if event.is_action_pressed("stealth_crouch"):
		if event.is_echo(): return
		
		if not is_rolling and not is_attacking and not is_climbing:
			# DYNAMIC SLIDE CANCEL INTERCEPT: 
			# If they tap crouch a SECOND time while sliding, execute an instant manual cancel
			if current_locomotion_mode == LocomotionState.SLIDING:
				exit_viking_slide_state()
				return # Break early to avoid double size triggers
				
			# SPRINT TRIGGER BRANCH: If running, enter slide mode
			elif current_locomotion_mode == LocomotionState.SPRINTING:
				enter_viking_slide_state()
				
			# IDLE TRAVERSAL BRANCH: Standard crouch toggle
			else:
				toggle_crouch_state()
	
	if event.is_echo(): return
	
	
	# --- BODY DRAG & SALVAGE ---

	if event.is_action_pressed("interact") and not radial_menu_active:
		# [Body Drag Logic remains unchanged...]
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
				# DUCK TYPING DISCOVERY: Check if the guard has our active loot flags!
				if "is_currently_lootable" in body_node and body_node.is_currently_lootable:
					
					# 1. ENFORCE THE SINGLE-LOOT SECURITY SHUTTER LOCK
					body_node.is_currently_lootable = false
					body_node.has_already_been_looted = true
					
					# 2. EXTRACT INVENTORY RESOURCE PAYOUTS
					var items_found_text: String = ""
					if "bola_ammo_to_award" in body_node and current_bola_ammo < max_bola_ammo:
						current_bola_ammo = clamped_addition_value(current_bola_ammo, body_node.bola_ammo_to_award, max_bola_ammo)
						items_found_text += " +1 Bola Trap"
						
					if "matches_to_award" in body_node and "current_matches" in self:
						self.current_matches += body_node.matches_to_award
						items_found_text += " +1 Campfire Match"
						
					print("LOOT PROGRESS: Extracted parts:", items_found_text)
					
					# 3. REFRESH AUDIO LABELS AND HUD INTERFACE TEXT PLACEMENTS
					update_ammo_hud_display()
					
					# Play an elastic cartoon jump animation on her HUD text bar to celebrate!
					if is_instance_valid(ammo_label):
						var _punch = create_tween()
					if is_instance_valid(ammo_label):
						var punch = create_tween()
						# Change Vector3 directly to Vector2 to match screen layout scales!
						ammo_label.scale = Vector2(1.3, 1.3)
						punch.tween_property(ammo_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC)
						body_node.alert_label.text = "✖ EMPTY ✖"
						body_node.alert_label.modulate = Color("#888888") # Dull gray color skin
						
					break # Exit immediately to process exactly one guard body at a time!
		handle_drag_interaction()

	# --- GADGET USE ---
	if event.is_action_pressed("use_gadget"):
		if not is_rolling and not is_attacking and not is_gadget_on_cooldown:
			is_actively_aiming_gadget = true
			get_tree().create_timer(0.25).timeout.connect(func(): is_bola_on_fire_cooldown = false)
		else:
			if not is_rolling and not is_attacking and not is_bola_on_fire_cooldown:
				is_actively_aiming_gadget = true

	elif event.is_action_released("use_gadget"):
		if is_actively_aiming_gadget:
			is_actively_aiming_gadget = false
			execute_unified_gadget_fire()
			
			is_bola_on_fire_cooldown = true
			get_tree().create_timer(0.25).timeout.connect(func(): is_bola_on_fire_cooldown = false)

# --- PARRY ---
	if event.is_action_pressed("shield_parry"):
		if not is_rolling and not is_attacking and not is_climbing:
			execute_shield_parry()

# --- SWAP WEAPON ---
	if event.is_action_pressed("swap_weapon"):
		execute_open_radial_menu()
	elif event.is_action_released("swap_weapon"):
		if radial_menu_active:
			execute_close_radial_menu()
	
	# MOUSE WHEEL SELECTION (Only works when menu is active)
	if radial_menu_active:
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cycle_backpack_gadget(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cycle_backpack_gadget(1)

func clamped_addition_value(current: int, incoming: int, limit: int) -> int:
	return min(current + incoming, limit) as int

func execute_open_radial_menu() -> void:
	if radial_menu_active: return
	
	radial_menu_active = true
	if is_instance_valid(radial_wheel_panel):
		radial_wheel_panel.visible = true
	
	pre_menu_selected_gadget = current_selected_gadget
	menu_highlighted_gadget = current_selected_gadget
	
	camera_curve_timer = 0.0
	camera_target_fov = 28.0
	has_player_scrolled_during_this_menu_session = false
	
	update_backpack_camera_focus_coordinates()
	print("GEAR BAG: Winding up camera arc into toolbelt view.")

func execute_close_radial_menu() -> void:
	if not radial_menu_active: return
	
	current_selected_gadget = menu_highlighted_gadget
	
	radial_menu_active = false
	if is_instance_valid(radial_wheel_panel):
		radial_wheel_panel.visible = false
	
	camera_target_fov = 70.0
	camera_target_offset = Vector3.ZERO
	update_ammo_hud_display()
	print("GEAR BAG: Equipped selected gadget. Closed toolbelt view.")

func cycle_backpack_gadget(direction: int) -> void:
	var total_gadgets = GadgetType.values().size()
	var current_index = menu_highlighted_gadget as int
	current_index = (current_index + direction + total_gadgets) % total_gadgets
	menu_highlighted_gadget = current_index as GadgetType
	has_player_scrolled_during_this_menu_session = true
	
	# Cleaned up scales to protect camera pivot logic calculations
	update_backpack_camera_focus_coordinates()

func update_backpack_camera_focus_coordinates() -> void:
	if menu_highlighted_gadget == GadgetType.PEBBLE:
		camera_target_offset = Vector3(-0.48, 0.05, -0.05)
		if is_instance_valid(radial_title_label):
			radial_title_label.text = "[b][color=#ff7f24]🪨 [ PEBBLES ] 🪨[/color][/b]\n\nUnclipped noise stone pouch"
	else:
		camera_target_offset = Vector3(0.48, -0.05, 0.05)
		if is_instance_valid(radial_title_label):
			radial_title_label.text = "[b][color=#4ca64c]🪢 [ BOLA TRAPS ] 🪢[/color][/b]\n\nUnbuckled weighted capture cords"
		
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
	else:
		controller_joystick_debounce = false # Resets when stick returns to center
		
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

func enter_viking_slide_state() -> void:
	if current_locomotion_mode == LocomotionState.SLIDING: return
	
	current_locomotion_mode = LocomotionState.SLIDING
	slide_duration_timer = 1.2 # Baseline slide length limit threshold
	
	# Blast her forward with your established slide impulse velocity parameters
	var slide_dir: Vector3 = -global_transform.basis.z.normalized()
	if velocity.length_squared() > 0.1:
		slide_dir = velocity.normalized()
	velocity.x = slide_dir.x * slide_impulse_velocity
	velocity.z = slide_dir.z * slide_impulse_velocity
	
	# Position the physical shield mesh flat under her soles BEFORE toggling shapes
	if is_instance_valid(shield_skate_rig):
		var active_tween = get_tree().create_tween().set_parallel(true)
		# Lowering the shield mesh to match her -0.45 local ground center!
		active_tween.tween_property(shield_skate_rig, "position", Vector3(0.0, -0.45, 0.0), 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		active_tween.tween_property(shield_skate_rig, "rotation_degrees", Vector3(0.0, 0.0, 0.0), 0.1)
		
	# Toggle shape nodes and visual mesh sizes safely
	update_player_size(true)
	
	# --- THE COMPENSATOR GATEWAYS ---
	# Offsets the difference between the 0.0 standing origin and your -0.45 sliding center.
	# This completely stops the physics engine from launching her capsule into the sky!
	if is_on_floor():
		global_position.y -= 0.45
		
	if has_method("spawn_footstep_dust_cloud"):
		spawn_footstep_dust_cloud(true)
		
	print("LOCOMOTION: Shield dropped to surf stance! Ground origin locked.")

func exit_viking_slide_state() -> void:
	if current_locomotion_mode != LocomotionState.SLIDING: return
	
	current_locomotion_mode = LocomotionState.STANDARD
	slide_duration_timer = 0.0
	
	# Instantly snap her shield board right back onto her shoulder visual socket
	if is_instance_valid(shield_skate_rig):
		var active_tween = get_tree().create_tween().set_parallel(true)
		active_tween.tween_property(shield_skate_rig, "position", Vector3(-0.4, 0.2, 0.2), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		active_tween.tween_property(shield_skate_rig, "rotation_degrees", Vector3(0.0, 0.0, 90.0), 0.12)
		
	# Restore normal standing 1.8m capsule shape nodes
	update_player_size(false)
	
	# Symmetrically push her world coordinates up to balance the center mass shift
	if is_on_floor():
		global_position.y += 0.45
		
	if is_instance_valid(camera):
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, 12.0 * get_process_delta_time())
		
	print("LOCOMOTION: Slide concluded. Posture profiles synchronized.")
