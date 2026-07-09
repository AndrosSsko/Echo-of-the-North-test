extends CharacterBody3D

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
@onready var camera: Camera3D = $"../Camera_Pivot/Camera3D"
@onready var melee_hitbox: Area3D = $Melee_Hitbox
@onready var hitbox_collision: CollisionShape3D = $Melee_Hitbox/CollisionShape3D
@onready var player_collision: CollisionShape3D = $CollisionShape3D
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
@onready var aim_line_visual: Node3D = $Aim_Line_Pointer
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


# Tracking properties for twin-stick thumbstick aiming
var controller_aim_direction: Vector3 = Vector3.ZERO

# Unified non-lethal gadget inventory selector machine
enum GadgetType { PEBBLE, BOLA }
var current_selected_gadget: GadgetType = GadgetType.PEBBLE # Starts with Pebble equipped!

# Path tracking pointers aligned to your clean scenes directory folders
var pebble_blueprint = preload("res://scenes/stealth_pebble.tscn")
var dust_blueprint = preload("res://scenes/footstep_dust.tscn")
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
	# --- QUADRATIC BÉZIER "BASEBALL PITCH" CAMERA ENGINE ---
	if is_instance_valid(camera):
		camera.fov = lerp(camera.fov, camera_target_fov, 10.0 * delta)
		
		# Define our 3 canon points for the Bézier curve equation matrix
		var p0: Vector3 = Vector3(0.0, 4.5, 6.0) # Start position (Wide gameplay camera)
		var p2: Vector3 = Vector3(0.5, 1.3, 2.5) + camera_target_offset 
		var p1: Vector3 = Vector3(3.6, 5.2, 5.5)
		
		if radial_menu_active:
			camera_curve_timer = move_toward(camera_curve_timer, 1.0, 3.5 * delta)
		else:
			camera_curve_timer = move_toward(camera_curve_timer, 0.0, 4.5 * delta)
			
		var t: float = camera_curve_timer
		var curved_bezier_position: Vector3 = (1.0 - t)*(1.0 - t)*p0 + 2.0*(1.0 - t)*t*p1 + t*t*p2
		camera.position = curved_bezier_position

	# FIXED RADIAL BREAKUP GATES: If the menu is open, freeze her completely
	if radial_menu_active:
		velocity = Vector3.ZERO # 👈 CRITICAL FIX: Lock positional drift completely while looking at hips
		move_and_slide()
		evaluate_radial_wheel_joystick_navigation()
		return
	
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# MASTER CLIMBING INTERRUPT STATE CHECK
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
	
	# --- MASTER MECHANICS INPUT CAPTURES ---
	if Input.is_action_just_pressed("stealth_crouch") and not is_rolling:
		toggle_crouch_state()

	# READ WEAPON-READY STATES
	var is_holding_aim_modifier: bool = Input.is_action_pressed("shield_parry")
	var aim_vector: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var is_player_actively_aiming: bool = false
	
	if aim_vector.length_squared() > 0.1:
		is_player_actively_aiming = true
		var cam_basis: Transform3D = camera.global_transform
		var cam_right: Vector3 = cam_basis.basis.x
		var cam_forward: Vector3 = cam_basis.basis.z
		cam_right.y = 0.0
		cam_forward.y = 0.0
		controller_aim_direction = (cam_right * aim_vector.x) + (cam_forward * aim_vector.y)
		controller_aim_direction = controller_aim_direction.normalized()
	else:
		controller_aim_direction = Vector3.ZERO
		if is_holding_aim_modifier and Input.get_connected_joypads().size() == 0:
			is_player_actively_aiming = true

	# DYNAMIC VISUAL AIMING LINE TOGGLE
	if is_instance_valid(aim_line_visual):
		aim_line_visual.visible = is_player_actively_aiming
		
		if controller_aim_direction.length_squared() > 0.1:
			aim_line_visual.global_rotation.y = atan2(-controller_aim_direction.x, -controller_aim_direction.z)
		elif is_player_actively_aiming:
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
			var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + (ray_normal * 100.0))
			var result = space_state.intersect_ray(query)
			if not result.is_empty():
				var dir_to_mouse: Vector3 = result["position"] - global_position
				dir_to_mouse.y = 0.0
				if dir_to_mouse.length_squared() > 0.1:
					aim_line_visual.global_rotation.y = atan2(-dir_to_mouse.normalized().x, -dir_to_mouse.normalized().z)

	# UNIFIED GADGET TRIGGER SLOT WITH COOLDOWN PROTECTION
	if Input.is_action_just_pressed("use_gadget") and not is_rolling and not is_attacking and not is_bola_on_fire_cooldown:
		is_bola_on_fire_cooldown = true
		execute_unified_gadget_fire()
		get_tree().create_timer(0.25).timeout.connect(func():
			is_bola_on_fire_cooldown = false
		)
		
	# DEFENSIVE SHIELD PARRY TRIGGER LISTENER
	if Input.is_action_just_pressed("shield_parry") and not is_player_actively_aiming and not is_rolling and not is_attacking and not is_climbing:
		execute_shield_parry()
		
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
		
	# Distance Odometer step particle tracker
	if is_on_floor() and input_vector.length_squared() > 0.01:
		distance_traveled += movement_speed * delta
		if distance_traveled >= step_interval:
			distance_traveled = 0.0
			spawn_footstep_dust_cloud()
			
	if not is_on_floor(): 
		velocity.y += get_gravity().y * delta
	else: 
		velocity.y = 0.0
		
	move_and_slide()

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

func spawn_footstep_dust_cloud() -> void:
	if is_crouching or is_climbing: return
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

	var dust_instance = dust_blueprint.instantiate() as GPUParticles3D
	dust_instance.position = global_position + Vector3(0.0, 0.05, 0.0)
	get_parent().add_child(dust_instance)
	dust_instance.emitting = true
	dust_instance.global_transform.basis = global_transform.basis
	
	if is_instance_valid(dust_instance.draw_pass_1):
		var runtime_mesh: SphereMesh = dust_instance.draw_pass_1.duplicate()
		var baseline_material = runtime_mesh.material as StandardMaterial3D
		if is_instance_valid(baseline_material):
			var runtime_material: StandardMaterial3D = baseline_material.duplicate()
			runtime_material.albedo_color = target_dust_color
			runtime_mesh.material = runtime_material
		dust_instance.draw_pass_1 = runtime_mesh
	
	dust_instance.finished.connect(func(): dust_instance.queue_free())
	
	var ripple_blueprint = load("res://scenes/acoustic_ripple.tscn")
	if ripple_blueprint:
		var ripple_instance = ripple_blueprint.instantiate() as MeshInstance3D
		ripple_instance.position = global_position + Vector3(0.0, 0.02, 0.0)
		get_parent().add_child(ripple_instance)
		ripple_instance.scale = Vector3(0.1, 0.1, 0.1)
		
		var ripple_tween: Tween = create_tween()
		ripple_tween.set_parallel(true)
		ripple_tween.tween_property(ripple_instance, "scale", Vector3(6.0, 1.0, 6.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		if is_instance_valid(ripple_instance.mesh.material):
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
	is_crouching = not is_crouching
	var capsule_shape = player_collision.shape as CapsuleShape3D
	var capsule_mesh = player_mesh.mesh as CapsuleMesh
	if is_crouching:
		capsule_shape.height = 1.0
		capsule_mesh.height = 1.0
		player_mesh.position.y = -0.5
		player_collision.position.y = -0.5
	else:
		capsule_shape.height = 2.0
		capsule_mesh.height = 2.0
		player_mesh.position.y = 0.0
		player_collision.position.y = 0.0

func process_standard_movement(target_direction: Vector3, delta: float) -> void:
	if is_on_wall(): target_direction = target_direction.slide(get_wall_normal()).normalized()
	var current_target_speed: float = crouch_speed if is_crouching else movement_speed
	var target_velocity_xz: Vector3 = target_direction * current_target_speed
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
	if collider.has_method("take_damage"):
		var hunter_backward_vector: Vector3 = collider.global_transform.basis.z.normalized()
		var direction_to_player: Vector3 = (global_position - collider.global_position).normalized()
		hunter_backward_vector.y = 0.0
		direction_to_player.y = 0.0
		var rear_zone_score: float = hunter_backward_vector.dot(direction_to_player)
		
		if rear_zone_score > 0.15 and was_crouching_on_attack:
			print("STEALTH COMBAT CORE: Takedown confirmed from behind! Executing knockout.")
			var push_direction: Vector3 = -global_transform.basis.z.normalized()
			collider.take_damage(1, push_direction)
		else:
			print("COMBAT ENGINE: Frontal strike connected with target: ", collider.name)
			if collider.is_in_group("EnemyGroup"):
				var forward_push: Vector3 = -global_transform.basis.z.normalized()
				collider.take_damage(1, forward_push)
			else:
				collider.take_damage(1)

func initiate_dodge_roll(target_direction: Vector3) -> void:
	is_rolling = true
	can_dodge = false
	roll_timer = dodge_duration
	
	if is_crouching:
		is_crouching = false
		(player_collision.shape as CapsuleShape3D).height = 2.0
		(player_mesh.mesh as CapsuleMesh).height = 2.0
		player_mesh.position.y = 0.0
		player_collision.position.y = 0.0
		
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
	var target_facing_vector: Vector3 = -global_transform.basis.z.normalized()
	
	if Input.get_connected_joypads().size() == 0:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
		var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + (ray_normal * 100.0))
		query.exclude = [self.get_rid()]
		var result = space_state.intersect_ray(query)
		
		if not result.is_empty():
			var floor_hit_point: Vector3 = result["position"]
			var dir_to_mouse: Vector3 = floor_hit_point - global_position
			dir_to_mouse.y = 0.0
			if dir_to_mouse.length_squared() > 0.1:
				target_facing_vector = dir_to_mouse.normalized()
				rotation.y = atan2(-target_facing_vector.x, -target_facing_vector.z)
	else:
		if controller_aim_direction.length_squared() > 0.1:
			target_facing_vector = controller_aim_direction
			rotation.y = atan2(-target_facing_vector.x, -target_facing_vector.z)

	match current_selected_gadget:
		GadgetType.PEBBLE:
			if not can_throw_pebble: return
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
				
			get_tree().create_timer(pebble_throw_cooldown).timeout.connect(func():
				can_throw_pebble = true
			)
			return
			
		GadgetType.BOLA:
			if current_bola_ammo <= 0:
				print("GADGET INVENTORY: Pouch empty! Restock cords at a campfire.")
				return
			var bola_instance = bola_blueprint.instantiate()
			bola_instance.position = global_position + Vector3(0.0, 0.8, 0.0)
			get_parent().add_child(bola_instance)
			if bola_instance.has_method("initialize_bola_flight"):
				bola_instance.initialize_bola_flight(target_facing_vector)
			current_bola_ammo -= 1
			update_ammo_hud_display()

func update_ammo_hud_display() -> void:
	if is_instance_valid(ammo_label):
		if current_selected_gadget == GadgetType.PEBBLE:
			ammo_label.text = "Pebbles: INF"
		else:
			ammo_label.text = "Bolas: " + str(current_bola_ammo) + " / " + str(max_bola_ammo)

func _input(event: InputEvent) -> void:
	if event.is_echo(): return

	# 1. HOLD ACTUATOR ON KEYDOWN
	if event.is_action_pressed("swap_weapon"):
		execute_open_radial_menu()

	# 2. SELECTION SAVE & CLOSE ON KEYRELEASE
	elif event.is_action_released("swap_weapon"):
		if radial_menu_active:
			execute_close_radial_menu()
			
	# 3. MOUSE WHEEL SELECTION (Only works when menu is active)
	if radial_menu_active:
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cycle_backpack_gadget(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cycle_backpack_gadget(1)

# Tracks thumbstick flicking so it doesn't hyper-scroll across items
var controller_joystick_debounce: bool = false

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
