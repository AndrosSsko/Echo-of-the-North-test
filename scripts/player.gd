extends CharacterBody3D


enum LocomotionState { STANDARD, SPRINTING, SLIDING }
var current_locomotion_mode: LocomotionState = LocomotionState.STANDARD

@export_category("Viking Locomotion Tuning")
@export var sprint_speed_multiplier: float = 1.55
@export var slide_impulse_velocity: float = 18.0
@export var slide_friction_decay: float = 4.5
@export var slope_boost_multiplier: float = 2.2   # How strongly downhill slopes accelerate the slide
@export var max_slide_speed: float = 26.0          # Speed cap so steep hills don't launch her into orbit
@export var bowling_strike_force: float = 14.0     # Horizontal knockback applied to smaller guards
@export var bowling_strike_upward_force: float = 6.0 # Extra "comedic pop" launch height on impact

var slide_duration_timer: float = 0.0
@onready var core_capsule_collision: CollisionShape3D = $CollisionShape3D

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

@export var camera: Camera3D
@onready var melee_hitbox: Area3D = $Melee_Hitbox
@onready var hitbox_collision: CollisionShape3D = $Melee_Hitbox/CollisionShape3D
@onready var player_collision: CollisionShape3D = $CollisionShape3D
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
@onready var aim_line_visual: Node3D = $Aim_Line_Pointer
@onready var ground_snapper: RayCast3D = $GroundSnapper
@onready var shield_rig: Node3D = $VikingShieldRig
@onready var shield_carry_pose: Node3D = $ShieldCarryPose
@onready var shield_surf_pose: Node3D = $ShieldSurfPose
@onready var ammo_label: Label = $"../HUD/Ammo_Container/Ammo_Tracker"
@onready var radial_wheel_panel: Panel = $"../HUD/Radial_Wheel_UI"
@onready var radial_title_label: RichTextLabel = $"../HUD/Radial_Wheel_UI/Selection_Title_Text"
@onready var heart_icons: Array = [
	$"../HUD/Health_Container/Heart_01",
	$"../HUD/Health_Container/Heart_02",
	$"../HUD/Health_Container/Heart_03"
]

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
	
	# === SHIELD-SURF / SLIDE STATE MACHINE ===
	if current_locomotion_mode == LocomotionState.SLIDING:
		slide_duration_timer -= delta

		# 1. KINETIC FRICTION (natural drag that brings her back up to a walk on flat ground)
		velocity.x = move_toward(velocity.x, 0.0, slide_friction_decay * delta)
		velocity.z = move_toward(velocity.z, 0.0, slide_friction_decay * delta)

		# 2. SLOPE MOMENTUM (physics-based acceleration on hills/ramps/ruins)
		if is_on_floor():
			var floor_normal: Vector3 = get_floor_normal()
			var gravity_vector: Vector3 = Vector3.DOWN * get_gravity().length()
			# The component of gravity that runs ALONG the slope surface (not into it)
			var slope_tangent_accel: Vector3 = gravity_vector - floor_normal * gravity_vector.dot(floor_normal)
			velocity += slope_tangent_accel * slope_boost_multiplier * delta

			# Cap horizontal speed so steep hills don't launch her into orbit
			var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
			if horizontal_velocity.length() > max_slide_speed:
				horizontal_velocity = horizontal_velocity.normalized() * max_slide_speed
				velocity.x = horizontal_velocity.x
				velocity.z = horizontal_velocity.z

			# On a real slope, keep the slide alive instead of letting the timer cut it short
			if floor_normal.y < 0.85:
				slide_duration_timer = max(slide_duration_timer, 0.3)

		# 3. GROUND SNAPPING (The Shield-Surf Architecture)
		if ground_snapper.is_colliding():
			var snap_target_y = ground_snapper.get_collision_point().y
			global_position.y = lerp(global_position.y, snap_target_y, 20.0 * delta)

		# 4. CAMERA TILT
		if is_instance_valid(camera):
			camera.rotation.z = lerp_angle(camera.rotation.z, deg_to_rad(3.5), 8.0 * delta)

		move_and_slide()

		# 5. CARTOON BOWLING STRIKE — check what we just plowed into this frame
		for i in get_slide_collision_count():
			var collision: KinematicCollision3D = get_slide_collision(i)
			var collider: Node = collision.get_collider()
			if is_instance_valid(collider) and collider.is_in_group("EnemyGroup"):
				_resolve_bowling_strike(collider, collision)
				return # Bowling strike already handles the state transition this frame

		# 6. EXIT CONDITIONS
		if slide_duration_timer <= 0.0 or velocity.length_squared() < 4.0:
			exit_viking_slide_state()

		return # Prevents standard movement from overriding the slide

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
	var target_height: float = 1.2 if is_crouching else 1.8
	var target_pos_y: float = target_height / 2.0 # Keep origin at center of the new capsule
	
	if is_instance_valid(core_capsule_collision):
		core_capsule_collision.shape.height = target_height
		core_capsule_collision.position.y = target_pos_y
		
	if is_instance_valid(player_mesh):
		if player_mesh.mesh is CapsuleMesh:
			player_mesh.mesh.height = target_height
		player_mesh.position.y = target_pos_y
	
	# After resizing, force a micro-adjustment if we are on the floor 
	# to prevent clipping or floating.
	if is_on_floor():
		# Move up slightly to prevent sinking into geometry during crouch
		global_position.y += 0.05

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
	is_rolling = true
	can_dodge = false
	roll_timer = dodge_duration
	
	# Force stand up if dodging
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
			
			# NOTE: The bola is an Area3D, not a PhysicsBody3D, so it has no
			# add_collision_exception_with() method — that call always crashed here.
			# stealth_bola.gd already protects against hitting the player itself:
			# its CollisionShape3D stays disabled for the first 0.1s after spawn,
			# and _on_obstacle_intersected() explicitly ignores "Player"/"Smudge"/PlayerGroup.
			
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
		if not is_rolling and not is_attacking and not is_climbing:
			# If sprinting, trigger the slide, else just toggle crouch
			if current_locomotion_mode == LocomotionState.SPRINTING:
				enter_viking_slide_state()
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

func _resolve_bowling_strike(guard: Node, collision: KinematicCollision3D) -> void:
	# Knock the guard away from the direction Eira hit him from
	var knock_direction: Vector3 = -collision.get_normal()
	knock_direction.y = 0.0
	if knock_direction.length_squared() < 0.001:
		knock_direction = -global_transform.basis.z
	knock_direction = knock_direction.normalized()

	# Preferred path: let the guard's own script decide how to ragdoll/react.
	# Add a matching `execute_bowling_knockdown(direction, force, upward_force)` to your guard script.
	if guard.has_method("execute_bowling_knockdown"):
		guard.execute_bowling_knockdown(knock_direction, bowling_strike_force, bowling_strike_upward_force)
	elif guard is RigidBody3D:
		guard.apply_central_impulse(knock_direction * bowling_strike_force + Vector3.UP * bowling_strike_upward_force)
	else:
		print("BOWLING STRIKE: '", guard.name, "' has no execute_bowling_knockdown() method and isn't a RigidBody3D — add one to react to slide hits.")

	grant_salvage_bonus()
	print("LOCOMOTION: Guard bowled clean off his feet!")

	# Eira pops straight back up into a full sprint without losing her stride
	exit_viking_slide_state()
	current_locomotion_mode = LocomotionState.SPRINTING
	var sprint_target_speed: float = movement_speed * sprint_speed_multiplier
	var carried_speed: float = max(Vector3(velocity.x, 0.0, velocity.z).length(), sprint_target_speed)
	var forward: Vector3 = -global_transform.basis.z.normalized()
	velocity.x = forward.x * carried_speed
	velocity.z = forward.z * carried_speed
	move_and_slide()

func _drop_shield_to_surf_pose() -> void:
	# The "unclip and slam it down" moment — called the instant she starts sliding.
	# Reads the ShieldSurfPose marker's transform, so you tune this by dragging
	# the marker in the editor instead of editing numbers here.
	if not is_instance_valid(shield_rig) or not is_instance_valid(shield_surf_pose): return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shield_rig, "global_position", shield_surf_pose.global_position, 0.1)
	tween.tween_property(shield_rig, "global_rotation", shield_surf_pose.global_rotation, 0.1)

func _raise_shield_to_carried_pose() -> void:
	# Re-straps the shield to her arm as she pops back up out of the slide,
	# using the ShieldCarryPose marker's transform.
	if not is_instance_valid(shield_rig) or not is_instance_valid(shield_carry_pose): return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shield_rig, "global_position", shield_carry_pose.global_position, 0.2)
	tween.tween_property(shield_rig, "global_rotation", shield_carry_pose.global_rotation, 0.2)

func enter_viking_slide_state() -> void:
	if current_locomotion_mode == LocomotionState.SLIDING: return 
	
	current_locomotion_mode = LocomotionState.SLIDING
	slide_duration_timer = 1.2
	
	# Use current velocity or forward vector
	var slide_dir: Vector3 = -global_transform.basis.z.normalized()
	if velocity.length_squared() > 0.1:
		slide_dir = velocity.normalized()
	
	velocity.x = slide_dir.x * slide_impulse_velocity
	velocity.z = slide_dir.z * slide_impulse_velocity
	
	update_player_size(true) # Crouch
	_drop_shield_to_surf_pose() # Unclip the shield and slam it down as a makeshift board
	spawn_footstep_dust_cloud(true)
	print("LOCOMOTION: Eira enters Shield-Surf.")

func exit_viking_slide_state() -> void:
	current_locomotion_mode = LocomotionState.STANDARD
	update_player_size(false) # Stand up
	_raise_shield_to_carried_pose() # Strap the shield back onto her arm
	
	if is_instance_valid(camera):
		var tween = create_tween()
		tween.tween_property(camera, "rotation:z", 0.0, 0.2)
