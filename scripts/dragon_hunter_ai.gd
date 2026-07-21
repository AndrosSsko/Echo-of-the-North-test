extends CharacterBody3D

# =============================================================================
#     1. ENUMS AND MODULAR BEHAVIOR PHASES 
# =============================================================================
enum PatrolPhase { MARCHING, INVESTIGATING, DIZZY, STUNNED, PANICKING, BOLA_STRUGGLE, SLIPPING, CHASING }

@export_category("Patrol Waypoints")
@export var movement_speed: float = 3.5
@export var investigation_speed: float = 4.2
@export var acceleration: float = 8.0
@export var turn_speed: float = 5.0

@export_category("Incapacitation Durations")
@export var dizzy_duration: float = 4.0 

# CHILD COMPONENT INTERFACE HOOKS [PDF: 0.1.10]
@onready var vision_sensor: VisionSensor3D = $VisionSensor3D
@onready var health_posture: HealthPostureComponent = $HealthPostureComponent
@onready var dizzy_stars_halo: Node3D = $DizzyStarsHaloMotor

# SCENE LAYER OVERLAYS [PDF: 0.1.10]
@onready var suspicion_label_3d: Label3D = find_child("Suspicion_Label", true, false)
@onready var takedown_label_3d: Label3D = $Takedown_Label
@onready var visual_mesh: MeshInstance3D = $MeshInstance3D
@onready var cascade_sensor_area: Area3D = $Impact_Cascade_Sensor

@onready var point_a: Vector3 = $"../Patrol_Point_C".global_position if name == "Dragon_Hunter_High" else $"../Patrol_Point_A".global_position
@onready var point_b: Vector3 = $"../Patrol_Point_D".global_position if name == "Dragon_Hunter_High" else $"../Patrol_Point_B".global_position
@onready var equipped_weapon_mesh: Node3D = get_node_or_null("Skeleton3D/RightHandSlot/SwordMesh")

@export_category("Lootable Rewards System")
@export var matches_to_award: int = 1
@export var bola_ammo_to_award: int = 1

@export_category("Disarm System Blueprint Layout")
@export var dropped_weapon_blueprint: PackedScene 
@export var hand_weapon_mesh: MeshInstance3D 
@export var alert_anchor: Node3D
@export var alert_label: Label3D

# REAL-TIME WORKING STATE TELEMETRIES [PDF: 0.1.10]
var player_ref: CharacterBody3D = null
var current_phase: PatrolPhase = PatrolPhase.MARCHING
var is_currently_armed: bool = true
var dropped_weapon_global_target_pos: Vector3 = Vector3.ZERO
var cascade_slide_velocity: Vector3 = Vector3.ZERO
var current_target_destination: Vector3 = Vector3.ZERO
var noise_target_position: Vector3 = Vector3.ZERO
var phase_timer: float = 0.0
var is_flashing_alert: bool = false
var original_mesh_y: float = 0.0
var is_frantically_disarmed: bool = false
var active_dropped_weapon_instance: RigidBody3D = null
var is_currently_lootable: bool = false
var has_already_been_looted: bool = false
var bola_struggle_timer: float = 0.0
var alert_bubble_spring_scale: float = 0.0
var alert_bubble_spring_velocity: float = 0.0
var alert_bubble_display_timer: float = 0.0
var dizzy_timer: float = 0.0

# === 🦇 ARKHAM-STYLE FREEFLOW COUNTER STATE HOOKS ===
var is_vulnerable_to_counter: bool = false
var combat_strike_cooldown_clock: float = 0.0

# INTEGRATED BEHAVIOR TREE UTILITIES [PDF: 0.1.11]
var blackboard: AIBlackboard
var slip_task: TaskSlimeSlip

# =============================================================================
#     2. ENGINE SYSTEM READY CORRIDORS [PDF: 0.1.11, 0.1.12]
# =============================================================================
func _ready() -> void:
	add_to_group("EnemyGroup")
	current_target_destination = point_a
	
	if is_instance_valid(visual_mesh):
		original_mesh_y = visual_mesh.position.y
	if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
	if is_instance_valid(takedown_label_3d): takedown_label_3d.visible = false
	
	# BRIDGE HEALTH/SIGHT SIGNALS TO OUR STREAMLINED SENSOR NODES [PDF: 0.1.12]
	if is_instance_valid(health_posture):
		health_posture.posture_damaged.connect(_on_posture_damaged)
		health_posture.posture_shattered.connect(_on_posture_shattered)
		health_posture.posture_recovered.connect(_on_posture_recovered)
		
	if is_instance_valid(vision_sensor):
		vision_sensor.player_detected.connect(_on_vision_sensor_updated)
		vision_sensor.player_lost.connect(_on_vision_sensor_lost)

	# --- BEHAVIOR TREE INITIALIZATION --- [PDF: 0.1.12]
	blackboard = AIBlackboard.new()
	blackboard.name = "Blackboard"
	add_child(blackboard)
	
	slip_task = TaskSlimeSlip.new()
	slip_task.name = "SlipTask"
	add_child(slip_task)
	
	var bola_task = TaskBolaStruggle.new()
	bola_task.name = "BolaTask"
	add_child(bola_task)
	
	if is_instance_valid(EventBus):
		EventBus.gadget_impact.connect(_on_gadget_impact_received)
		if EventBus.has_signal("distraction_sound_emitted"):
			EventBus.distraction_sound_emitted.connect(_on_distraction_sound_emitted)

func _on_distraction_sound_emitted(sound_position: Vector3, hearing_distance: float) -> void:
	if global_position.distance_to(sound_position) <= hearing_distance:
		investigate_noise(sound_position)

# =============================================================================
#     3. CORE PHYSICS PROCESS INTERCEPTS (_PHYSICS_PROCESS) [PDF: 0.1.13]
# =============================================================================
func _physics_process(delta: float) -> void:
	if blackboard.get_value("is_slipped", false):
		process_tactical_stealth_takedown_radar()
		if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
		if is_instance_valid(takedown_label_3d): takedown_label_3d.visible = false
		slip_task.execute_task(self, blackboard, delta)
		return

	process_tactical_stealth_takedown_radar()

	if current_phase == PatrolPhase.PANICKING:
		if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
		process_weapon_scramble_panic_loop(delta)
		return

	process_alert_bubble_spring_math(delta)

	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("PlayerGroup") as CharacterBody3D
		return

	if current_phase == PatrolPhase.CHASING:
		if combat_strike_cooldown_clock > 0.0:
			combat_strike_cooldown_clock -= delta
		else:
			var distance_to_eira: float = global_position.distance_to(player_ref.global_position)
			if distance_to_eira <= 1.9:
				trigger_procedural_counter_window()

	# HARD-LOCK IMMOBILIZATION STATES TOGETHER [PDF: 0.1.13]
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.DIZZY or current_phase == PatrolPhase.BOLA_STRUGGLE:
		velocity = Vector3.ZERO
		is_vulnerable_to_counter = false # Instantly close counter windows if incapacitated
		if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
		if is_instance_valid(takedown_label_3d): takedown_label_3d.visible = false
		
		if current_phase == PatrolPhase.DIZZY:
			process_dizzy_state(delta)
		elif current_phase == PatrolPhase.BOLA_STRUGGLE:
			if has_node("BolaTask"):
				get_node("BolaTask").execute_task(self, blackboard, delta)
				if not blackboard.get_value("is_tangled", false):
					rotation_degrees.z = 0.0
					
		# ACCIDENTAL DOMINO CASCADE TRANSFERS [PDF: 0.1.14]
		if current_phase == PatrolPhase.STUNNED and is_instance_valid(cascade_sensor_area):
			for overlapping_body in cascade_sensor_area.get_overlapping_bodies():
				if overlapping_body is CharacterBody3D and overlapping_body != self and overlapping_body.is_in_group("EnemyGroup"):
					if "current_phase" in overlapping_body:
						if overlapping_body.current_phase == PatrolPhase.MARCHING or overlapping_body.current_phase == PatrolPhase.INVESTIGATING:
							overlapping_body.execute_cascade_trip_fall()
							
		if current_phase == PatrolPhase.STUNNED and cascade_slide_velocity.length_squared() > 0.01:
			velocity = cascade_slide_velocity
			move_and_slide()
			cascade_slide_velocity = lerp(cascade_slide_velocity, Vector3.ZERO, 6.0 * delta)
		return

	# === 🦇 THE LIVE COMBAT STRIKE TRIGGER INTERCEPT ===
	# If fully alerted and standing within a tight 2.3m close-quarters bubble, cycle attacks!
	if is_instance_valid(vision_sensor) and vision_sensor.current_suspicion >= 100.0:
		if combat_strike_cooldown_clock > 0.0:
			combat_strike_cooldown_clock -= delta
		else:
			var distance_to_eira: float = global_position.distance_to(player_ref.global_position)
			if distance_to_eira <= 2.3 and current_phase == PatrolPhase.MARCHING:
				trigger_procedural_counter_window()

	# MONITOR DROPPED TEAMMATES VIA ANGULAR SENSORY CHECKS [PDF: 0.1.14]
	var is_cone_active: bool = is_instance_valid(vision_sensor) and vision_sensor.current_suspicion > 0.01
	if not is_cone_active and current_phase == PatrolPhase.MARCHING:
		var all_guards = get_tree().get_nodes_in_group("EnemyGroup")
		for other_guard in all_guards:
			if is_instance_valid(other_guard) and other_guard != self and "current_phase" in other_guard:
				if other_guard.current_phase == PatrolPhase.STUNNED and global_position.distance_to(other_guard.global_position) <= vision_sensor.vision_range:
					var forward_heading: Vector3 = -global_transform.basis.z.normalized()
					var vec_to_body: Vector3 = (other_guard.global_position - global_position).normalized()
					if acos(clampf(forward_heading.dot(vec_to_body), -1.0, 1.0)) <= deg_to_rad(vision_sensor.vision_angle):
						var space_state = get_world_3d().direct_space_state
						var query = PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.5, 0.0), other_guard.global_position + Vector3(0.0, 0.5, 0.0))
						var ray_result = space_state.intersect_ray(query)
						if ray_result.is_empty() or ray_result["collider"] == other_guard:
							investigate_noise(other_guard.global_position)

	match current_phase:
		PatrolPhase.MARCHING: process_patrol_loop(delta)
		PatrolPhase.INVESTIGATING: process_investigation_loop(delta)
		PatrolPhase.CHASING: process_combat_chase_loop(delta)

# =============================================================================
#     4. STANDARD WAYPOINT MOVEMENT TRACKS [PDF: 0.1.18]
# =============================================================================
func process_patrol_loop(delta: float) -> void:
	var vector_to_waypoint: Vector3 = current_target_destination - global_position
	vector_to_waypoint.y = 0.0
	if vector_to_waypoint.length() < 0.6:
		velocity = Vector3.ZERO
		current_target_destination = point_b if current_target_destination == point_a else point_a
	else:
		var heading_dir = vector_to_waypoint.normalized()
		velocity.x = lerp(velocity.x, (heading_dir * movement_speed).x, acceleration * delta)
		velocity.z = lerp(velocity.z, (heading_dir * movement_speed).z, acceleration * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-heading_dir.x, -heading_dir.z), turn_speed * delta)
		move_and_slide()

# === FIXED REFACTOR BREAK: RESTORED MISSING FUNCTION SIGNAL OVERLAY ===
func process_investigation_loop(delta: float) -> void:
	var vector_to_noise: Vector3 = noise_target_position - global_position
	vector_to_noise.y = 0.0
	
	# STAGE 1: Dashing toward your Last Known Position vector spot
	if vector_to_noise.length() > 0.7 and phase_timer > 0.5:
		var heading_dir = vector_to_noise.normalized()
		# Run aggressively to the corner where he last saw Eira's shadow!
		var search_dash_speed: float = investigation_speed * 1.15
		velocity.x = lerp(velocity.x, (heading_dir * search_dash_speed).x, acceleration * delta)
		velocity.z = lerp(velocity.z, (heading_dir * search_dash_speed).z, acceleration * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-heading_dir.x, -heading_dir.z), turn_speed * delta)
		move_and_slide()
	else:
		# STAGE 2: Arrived at LKP! Halt feet and swing body left/right to scan local sectors [PDF: 0.1.50]
		velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)
		move_and_slide()
		
		# Procedural scanning look sweep: Wiggles his Y rotation using a clean sine wave arc!
		var scanning_wiggle_angle: float = sin(Time.get_ticks_msec() * 0.004) * 0.9
		rotation.y += scanning_wiggle_angle * delta
		
		# Count down his alert search state duration clocks
		phase_timer -= delta
		
		# STAGE 3: THE DISAPPOINTED GIVE-UP (WIPES SUSPICION CHANNELS) [PDF: 0.1.50]
		if phase_timer <= 0.0:
			current_phase = PatrolPhase.MARCHING
			current_target_destination = point_a # Go all the way back to default tracks
			
			# Flash a cinematic comic dialog bubble over his shoulders! [PDF: 0.1.45]
			if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
				alert_label.text = "Guess they slipped away..."
				alert_label.modulate = Color("#33ccff") # Safe relaxed cyan blue
				alert_label.visible = true
				alert_anchor.scale = Vector3.ZERO
				alert_bubble_spring_velocity = 10.0
				alert_bubble_display_timer = 2.5
				
			if is_instance_valid(suspicion_label_3d): 
				suspicion_label_3d.visible = false
			print("🕵️ STEALTH: Guard lost tracking, gave up search, and returned to patrol lines.")
		
# =============================================================================
#     4. COMPONENT SIGNAL RECEIVERS & DATA ROUTERS [PDF: 0.1.15, 0.1.16]
# =============================================================================
func _on_vision_sensor_updated(suspicion: float) -> void:
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.DIZZY: return
	
	if is_instance_valid(suspicion_label_3d):
		suspicion_label_3d.visible = true
		if suspicion >= 100.0:
			suspicion_label_3d.text = "ALERT: Spotted!"
			suspicion_label_3d.modulate = Color("#ff3333")
			
			if current_phase != PatrolPhase.CHASING and current_phase != PatrolPhase.PANICKING:
				current_phase = PatrolPhase.CHASING
		else:
			# DYNAMIC RECOVERY: If suspicion drops from a full hunt, don't drop out of stance!
			# Force him to aggressively investigate your last known coordinates [PDF: 0.1.8, 0.1.10]
			if current_phase == PatrolPhase.CHASING and is_instance_valid(player_ref):
				noise_target_position = player_ref.global_position
				current_phase = PatrolPhase.INVESTIGATING
				phase_timer = 4.5 # Scans your escape sector for 4.5 seconds
				
			suspicion_label_3d.text = "Detecting... " + str(int(suspicion)) + "%"
			suspicion_label_3d.modulate = Color("#ffcc00")

func _on_vision_sensor_lost() -> void:
	if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
	

	if current_phase == PatrolPhase.CHASING:
		current_phase = PatrolPhase.INVESTIGATING
		if is_instance_valid(player_ref):
			noise_target_position = player_ref.global_position
		phase_timer = 4.5



func _on_posture_damaged(current: int, maximum: int) -> void:
	print("COMBAT INTEGRATION: Guard took posture hits. Stability: ", current, "/", maximum)

func _on_posture_shattered() -> void:
	# Triggers his cartoon balance break dizzy wobbles
	execute_cartoon_dizzy_state()

func _on_posture_recovered() -> void:
	# === FIXED ZOMBIE RESURRECTION LOOP ===
	# If he is completely out cold on the floor, block his posture recovery clock 
	# from forcefully forcing him back up onto his feet!
	if current_phase == PatrolPhase.STUNNED: 
		return
		
	current_phase = PatrolPhase.MARCHING
	if is_instance_valid(visual_mesh): 
		visual_mesh.rotation_degrees.y = 0.0

# =============================================================================
#     5. COMIC STRIP DIALOG TEXT TIMERS [PDF: 0.1.16, 0.1.17]
# =============================================================================
func process_alert_bubble_spring_math(delta: float) -> void:
	if is_instance_valid(alert_anchor) and is_instance_valid(alert_label):
		if alert_bubble_display_timer > 0.0:
			alert_bubble_display_timer -= delta
			alert_label.visible = true
			var displacement: float = 1.0 - alert_bubble_spring_scale
			var spring_force: float = (displacement * 180.0) - (alert_bubble_spring_velocity * 14.0)
			alert_bubble_spring_velocity += spring_force * delta
			alert_bubble_spring_scale += alert_bubble_spring_velocity * delta
			var stretch_x: float = alert_bubble_spring_scale + (alert_bubble_spring_velocity * 0.015)
			var squash_y: float = alert_bubble_spring_scale - (alert_bubble_spring_velocity * 0.012)
			alert_anchor.scale = Vector3(stretch_x, squash_y, alert_bubble_spring_scale)
			if alert_bubble_display_timer <= 0.4:
				alert_label.modulate.a = move_toward(alert_label.modulate.a, 0.0, 2.5 * delta)
		else:
			alert_label.visible = false
			alert_bubble_spring_scale = 0.0
			alert_bubble_spring_velocity = 0.0

func investigate_noise(noise_pos: Vector3) -> void:
	if current_phase == PatrolPhase.DIZZY or current_phase == PatrolPhase.STUNNED: return
	var dialog_bubble_text: String = "HUH? What's that noise?"
	
	if is_instance_valid(vision_sensor) and vision_sensor.current_suspicion > 45.0:
		dialog_bubble_text = "WHO'S THERE?! I know someone is hiding!"
		
	if current_phase != PatrolPhase.INVESTIGATING:
		noise_target_position = noise_pos
		current_phase = PatrolPhase.INVESTIGATING
		phase_timer = 3.0
		
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = dialog_bubble_text
		alert_label.modulate = Color.BLACK
		alert_label.modulate.a = 1.0
		alert_anchor.scale = Vector3.ZERO
		alert_bubble_spring_velocity = 12.0 
		alert_bubble_spring_scale = 0.0
		alert_bubble_display_timer = 2.8

# =============================================================================
#     7. CARTOON INCAPACITATIONS & MOVIE RECOVERIES [PDF: 0.1.19, 0.1.20]
# =============================================================================
func execute_cartoon_dizzy_state() -> void:
	current_phase = PatrolPhase.DIZZY
	dizzy_timer = dizzy_duration
	velocity = Vector3.ZERO
	if is_instance_valid(visual_mesh):
		var w_tween = create_tween().set_loops(int(dizzy_duration / 0.3))
		w_tween.tween_property(visual_mesh, "rotation_degrees:y", 15.0, 0.15)
		w_tween.tween_property(visual_mesh, "rotation_degrees:y", -15.0, 0.15)

func process_dizzy_state(delta: float) -> void:
	dizzy_timer -= delta
	if is_instance_valid(player_ref) and player_ref.is_attacking and global_position.distance_to(player_ref.global_position) <= 2.2:
		execute_stealth_stun()
		return
	if dizzy_timer <= 0.0:
		if is_instance_valid(health_posture): health_posture.recover_balance()

func execute_stealth_stun(_push_dir: Vector3 = Vector3.ZERO) -> void:
	if current_phase == PatrolPhase.STUNNED: return
	
	current_phase = PatrolPhase.STUNNED
	velocity = Vector3.ZERO
	is_vulnerable_to_counter = false
	
	# Open his pocket grids so Eira can scavenge rare tool supplies from his body!
	if not has_already_been_looted: 
		is_currently_lootable = true
		
	spawn_procedural_takedown_fx_cloud()
	
	# Turn off his vision tracking cone entirely so he is blind while asleep
	if is_instance_valid(vision_sensor):
		vision_sensor.current_suspicion = 0.0
		vision_sensor.set_physics_process(false)
	
	# Drop his capsule mesh flat onto the floor bricks permanently
	rotation_degrees.x = 90.0
	position.y -= 0.6
	
	print("💤 PERMANENT STASIS: ", name, " is out cold. He will stay asleep permanently.")

func execute_cascade_trip_fall() -> void:
	current_phase = PatrolPhase.STUNNED
	velocity = Vector3.ZERO
	if is_instance_valid(visual_mesh):
		visual_mesh.rotation_degrees.x = -90.0
		visual_mesh.position.y = -0.6
	get_tree().create_timer(3.0).timeout.connect(func():
		if current_phase == PatrolPhase.STUNNED:
			current_phase = PatrolPhase.MARCHING
			if is_instance_valid(health_posture): health_posture.recover_balance()
			if is_instance_valid(visual_mesh):
				visual_mesh.rotation_degrees.x = 0.0
				visual_mesh.position.y = original_mesh_y
	)

func execute_disarm_parry_drop() -> void:
	if is_frantically_disarmed or current_phase == PatrolPhase.STUNNED: return
	is_frantically_disarmed = true
	is_currently_armed = false
	if current_phase != PatrolPhase.SLIPPING:
		current_phase = PatrolPhase.PANICKING
		velocity = Vector3.ZERO
		
	if is_instance_valid(hand_weapon_mesh): hand_weapon_mesh.visible = false
	if dropped_weapon_blueprint:
		var spawned_sword = dropped_weapon_blueprint.instantiate() as RigidBody3D
		get_tree().root.add_child(spawned_sword)
		spawned_sword.global_position = hand_weapon_mesh.global_position
		spawned_sword.global_basis = hand_weapon_mesh.global_basis
		active_dropped_weapon_instance = spawned_sword
		var escape_direction: Vector3 = (global_transform.basis.z + Vector3(0.0, 1.2, 0.0)).normalized()
		var spin_torque: Vector3 = Vector3(randf_range(8.0, 20.0), randf_range(8.0, 20.0), 0.0)
		spawned_sword.apply_central_impulse(escape_direction * 9.0)
		spawned_sword.apply_torque_impulse(spin_torque)
		
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "MY SWORD?!"
		alert_anchor.visible = true
		alert_label.visible = true
		alert_label.modulate.a = 1.0
		var pop_tween = create_tween()
		alert_anchor.scale = Vector3.ZERO
		alert_bubble_spring_scale = 1.0 
		alert_bubble_display_timer = 3.0
		pop_tween.tween_property(alert_anchor, "scale", Vector3(1.3, 1.3, 1.3), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(alert_anchor, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func process_weapon_scramble_panic_loop(delta: float) -> void:
	if is_instance_valid(active_dropped_weapon_instance):
		var target_sword_position: Vector3 = active_dropped_weapon_instance.global_position
		var vector_to_sword: Vector3 = target_sword_position - global_position
		vector_to_sword.y = 0.0
		if vector_to_sword.length() < 0.7:
			velocity = Vector3.ZERO
			active_dropped_weapon_instance.queue_free()
			if is_instance_valid(hand_weapon_mesh): hand_weapon_mesh.visible = true
			is_currently_armed = true
			is_frantically_disarmed = false
			current_phase = PatrolPhase.MARCHING
			current_target_destination = point_a
		else:
			var heading_dir = vector_to_sword.normalized()
			var panic_speed: float = movement_speed * 1.4 
			velocity.x = lerp(velocity.x, (heading_dir * panic_speed).x, acceleration * delta)
			velocity.z = lerp(velocity.z, (heading_dir * panic_speed).z, acceleration * delta)
			rotation.y = lerp_angle(rotation.y, atan2(-heading_dir.x, -heading_dir.z), turn_speed * 1.6 * delta)
			move_and_slide()

# =============================================================================
#     8. SLIME HAZARD INTERFACE TASKS [PDF: 0.1.23, 0.1.24]
# =============================================================================
func execute_cascade_stumble_fall() -> void:
	if current_phase == PatrolPhase.SLIPPING or current_phase == PatrolPhase.STUNNED: return
	current_phase = PatrolPhase.SLIPPING
	blackboard.set_value("is_slipped", true)
	blackboard.set_value("slip_elapsed", 0.0)
	blackboard.set_value("slip_weapon_dropped", false)
	velocity = Vector3.ZERO
	global_transform.basis = global_transform.basis.orthonormalized()
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "WHOA! TOO SLIPPERY!!"
		alert_anchor.visible = true
		alert_label.visible = true
		alert_label.modulate.a = 1.0
		alert_label.modulate = Color("#33ccff") 
		alert_bubble_spring_scale = 1.0
		alert_bubble_spring_velocity = 14.0 
		alert_bubble_display_timer = 2.0

func _on_slip_faceplant() -> void:
	if is_instance_valid(alert_label):
		alert_label.text = "NO! MY BLADE!!"
		alert_label.modulate = Color("#ff3333")
	if is_instance_valid(visual_mesh):
		visual_mesh.position.y = -0.6
	var active_cam = get_viewport().get_camera_3d()
	if is_instance_valid(active_cam) and active_cam.has_method("get_pcam"):
		var pcam = active_cam.get_pcam()
		if pcam and "shake_noise" in pcam:
			pcam.set_shake_frequency(15.0)
			pcam.set_shake_amplitude(0.25)
			get_tree().create_timer(0.3).timeout.connect(func(): pcam.set_shake_amplitude(0.0))
	if is_instance_valid(dizzy_stars_halo) and dizzy_stars_halo.has_method("start_dizzy_halo_sequence"):
		dizzy_stars_halo.start_dizzy_halo_sequence()
	var fade_timer_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	fade_timer_tween.tween_interval(2.4)
	fade_timer_tween.tween_property(dizzy_stars_halo, "scale", Vector3.ZERO, 0.6)
	
func _on_slip_recovered() -> void:
	if is_instance_valid(alert_label): alert_label.visible = false
	alert_bubble_display_timer = 0.0
	if is_instance_valid(visual_mesh):
		visual_mesh.position.y = 0.0 
	if is_instance_valid(dizzy_stars_halo) and dizzy_stars_halo.has_method("stop_dizzy_halo_sequence"):
		dizzy_stars_halo.stop_dizzy_halo_sequence()
	current_phase = PatrolPhase.MARCHING
	current_target_destination = point_a

func execute_long_range_bola_snag() -> void:
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.BOLA_STRUGGLE: return
	current_phase = PatrolPhase.BOLA_STRUGGLE
	bola_struggle_timer = 4.0 
	velocity = Vector3.ZERO
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "CRAP! BOLA TRAP!"
		alert_label.modulate = Color("#ffcc00") 
		alert_anchor.visible = true
		alert_label.visible = true
		alert_label.modulate.a = 1.0

# =============================================================================
#     9. COGNITIVE SPIDER-MAN WITNESS RADAR (DOT PRODUCT OPTIMIZED) [INDEX_0.1.25]
# =============================================================================
func process_tactical_stealth_takedown_radar() -> void:
	if not is_instance_valid(player_ref) or not is_instance_valid(takedown_label_3d): return
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.DIZZY or current_phase == PatrolPhase.BOLA_STRUGGLE:
		takedown_label_3d.visible = false
		return
	var player_is_sneaking: bool = player_ref.get("is_crouching") if "is_crouching" in player_ref else false
	if not player_is_sneaking:
		takedown_label_3d.visible = false
		return
	var distance_to_player: float = global_position.distance_to(player_ref.global_position)
	if distance_to_player <= 2.3:
		var guard_forward: Vector3 = -global_transform.basis.z.normalized()
		var direction_to_player: Vector3 = (player_ref.global_position - global_position).normalized()
		var angle_dot: float = guard_forward.dot(direction_to_player)
		if angle_dot < 0.35 and (current_phase == PatrolPhase.MARCHING or current_phase == PatrolPhase.INVESTIGATING):
			var is_any_other_guard_watching_me: bool = false
			var all_guards = get_tree().get_nodes_in_group("EnemyGroup")
			for witness in all_guards:
				if is_instance_valid(witness) and witness != self and "current_phase" in witness and witness.has_node("VisionSensor3D"):
					if witness.current_phase == PatrolPhase.STUNNED or witness.current_phase == PatrolPhase.DIZZY or witness.current_phase == PatrolPhase.PANICKING: continue
					var distance_to_me: float = witness.global_position.distance_to(global_position)
					var w_sensor = witness.vision_sensor
					if distance_to_me <= w_sensor.vision_range:
						var witness_forward: Vector3 = -witness.global_transform.basis.z.normalized()
						var dir_to_me: Vector3 = (global_position - witness.global_position).normalized()
						var witness_angle: float = rad_to_deg(witness_forward.angle_to(dir_to_me))
						if witness_angle <= witness.vision_sensor.vision_angle:
							var space_state = get_world_3d().direct_space_state
							var eye_level: Vector3 = witness.global_position + Vector3(0.0, 0.5, 0.0)
							var target_level: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)
							var query = PhysicsRayQueryParameters3D.create(eye_level, target_level)
							query.exclude = [witness.get_rid(), self.get_rid()]
							var ray_hit = space_state.intersect_ray(query)
							if ray_hit.is_empty() or ray_hit["collider"] == self:
								is_any_other_guard_watching_me = true
								break
			takedown_label_3d.visible = true
			var connected_pads = Input.get_connected_joypads()
			var is_gamepad: bool = !connected_pads.is_empty() and Input.is_joy_known(connected_pads[0])
			var attack_prompt: String = "[Button East]" if is_gamepad else "[X]"
			if is_any_other_guard_watching_me:
				takedown_label_3d.text = attack_prompt + " DANGER: WATCHED!"
				takedown_label_3d.modulate = Color("#ff3333")
			else:
				takedown_label_3d.text = attack_prompt + " Stealth Takedown [SAFE]"
				takedown_label_3d.modulate = Color("#33ccff")
			return
	takedown_label_3d.visible = false

# =============================================================================
#     10. VISUAL VFX PARTICLES GENERATOR 
# =============================================================================
func spawn_procedural_takedown_fx_cloud() -> void:
	var fx_root_node: Node3D = Node3D.new()
	var dust_emitter: CPUParticles3D = CPUParticles3D.new()
	var star_emitter: CPUParticles3D = CPUParticles3D.new()
	get_tree().root.add_child(fx_root_node)
	fx_root_node.global_position = global_position + Vector3(0.0, 0.8, 0.0)
	fx_root_node.add_child(dust_emitter)
	fx_root_node.add_child(star_emitter)
	
	dust_emitter.one_shot = true
	dust_emitter.lifetime = 0.35
	dust_emitter.explosiveness = 1.0
	dust_emitter.amount = 12
	dust_emitter.gravity = Vector3.ZERO 
	dust_emitter.direction = Vector3(0.0, 1.0, 0.0)
	dust_emitter.spread = 180.0 
	dust_emitter.initial_velocity_min = 4.0
	dust_emitter.initial_velocity_max = 4.0
	dust_emitter.damping_min = 7.0
	dust_emitter.damping_max = 7.0
	dust_emitter.scale_amount_min = 1.0
	dust_emitter.scale_amount_max = 1.8
	var cloud_quad_mesh: QuadMesh = QuadMesh.new()
	cloud_quad_mesh.size = Vector2(0.6, 0.6)
	var dust_draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	dust_draw_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	dust_draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85) 
	dust_draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dust_draw_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	var outline_mat: StandardMaterial3D = StandardMaterial3D.new()
	outline_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	outline_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	outline_mat.grow = true
	outline_mat.grow_amount = 0.04 
	dust_draw_mat.next_pass = outline_mat
	cloud_quad_mesh.material = dust_draw_mat
	dust_emitter.mesh = cloud_quad_mesh
	
	star_emitter.one_shot = true
	star_emitter.lifetime = 1.0
	star_emitter.explosiveness = 0.8
	star_emitter.amount = 4
	star_emitter.gravity = Vector3.ZERO
	star_emitter.spread = 0.0
	star_emitter.orbit_velocity_min = 3.0 
	star_emitter.orbit_velocity_max = 3.0
	var star_mesh: PrismMesh = PrismMesh.new()
	star_mesh.size = Vector3(0.12, 0.25, 0.12)
	var star_draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	star_draw_mat.albedo_color = Color("#ffff00") 
	star_draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	star_mesh.material = star_draw_mat
	star_emitter.mesh = star_mesh
	
	dust_emitter.emitting = true
	star_emitter.emitting = true
	get_tree().create_timer(1.2).timeout.connect(func(): fx_root_node.queue_free())

func _on_gadget_impact_received(type: int, impact_pos: Vector3, radius: float) -> void:
	var distance: float = global_position.distance_to(impact_pos)
	if distance > radius: return 
	
	match type:
		1:
			# === THE DRAGON SLIME PUDDLE INTERCEPT GATES ===
			# Flips his blackboard memory logs to tell his behavior tree task to execute a faceplant!
			if is_instance_valid(blackboard):
				blackboard.set_value("is_slipped", true)
				blackboard.set_value("slip_elapsed", 0.0)
				blackboard.set_value("slip_weapon_dropped", false)
				
				# Call your custom stumble fall method to shift his current phase state
				execute_cascade_stumble_fall()
		0:
			if is_instance_valid(blackboard):
				blackboard.set_value("is_tangled", true)
				blackboard.set_value("bola_timer", 4.0)
			current_phase = PatrolPhase.BOLA_STRUGGLE

func take_damage(amount: int, push_dir: Vector3 = Vector3.ZERO) -> void:
	if current_phase == PatrolPhase.STUNNED: return
	
	if is_instance_valid(health_posture):
		health_posture.take_posture_damage(amount)
		
		# Apply an instant kinetic recoil knockback vector over the tiles!
		if push_dir.length_squared() > 0.01 and current_phase != PatrolPhase.STUNNED:
			velocity = push_dir * 6.5
			move_and_slide()

# =============================================================================
#     11. DYNAMIC PROCEDURAL NON-LETHAL SWELLING SYSTEM [INDEX_0.1.30, INDEX_0.1.32]
# =============================================================================
func execute_localized_poison_swell(spike_global_impact_pos: Vector3) -> void:
	if current_phase == PatrolPhase.STUNNED: return
	
	var local_impact_height: float = to_local(spike_global_impact_pos).y
	var swell_offset_vector: Vector3 = Vector3.ZERO
	var target_part_label_name: String = "Torso"
	var custom_swell_mesh: Mesh = BoxMesh.new()
	
	# Cache original sensory limits to manipulate on impact frames [INDEX_0.1.32]
	var old_vision_range: float = 9.0
	if is_instance_valid(vision_sensor):
		old_vision_range = vision_sensor.vision_range
	
	if local_impact_height > 0.45:
		target_part_label_name = "Head"
		swell_offset_vector = Vector3(0.0, 0.9, 0.0) 
		custom_swell_mesh = SphereMesh.new() 
		
		# === STEALTH MECHANIC: TUMOR BLINDNESS MATRIX === [INDEX_0.1.30]
		# Swelling blocks his view, dropping sight reach down to a blind 1.5m corridor!
		if is_instance_valid(vision_sensor):
			vision_sensor.vision_range = 1.5
			print("🕶️ BLINDNESS: Guard's swollen eyes can no longer track distant movement!")
	elif local_impact_height < -0.35:
		target_part_label_name = "Ankle"
		swell_offset_vector = Vector3(randf_range(-0.2, 0.2), -0.6, randf_range(-0.2, 0.2))
		custom_swell_mesh = CapsuleMesh.new()
	else:
		target_part_label_name = "Arm"
		swell_offset_vector = Vector3(0.35 if randf() > 0.5 else -0.35, 0.1, 0.0)
		custom_swell_mesh = SphereMesh.new()

	print("🎈 POISON EFFECT: Guard's ", target_part_label_name, " is beginning to swell up!")
	
	var balloon_node: MeshInstance3D = MeshInstance3D.new()
	balloon_node.mesh = custom_swell_mesh
	add_child(balloon_node)
	
	balloon_node.position = swell_offset_vector
	balloon_node.scale = Vector3.ZERO 
	
	var swell_material: StandardMaterial3D = StandardMaterial3D.new()
	swell_material.albedo_color = Color("#ffaa44") 
	swell_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	balloon_node.material_override = swell_material
	
	var old_marching_speed: float = movement_speed
	movement_speed *= 0.45 
	
	var swell_tween = create_tween().set_parallel(true)
	swell_tween.tween_property(balloon_node, "scale", Vector3(0.45, 0.45, 0.45), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# DEFLATION TIMERS: Restores sensory reach and locomotion metrics seamlessly [INDEX_0.1.32]
	get_tree().create_timer(4.5).timeout.connect(func():
		if is_instance_valid(balloon_node):
			var shrink_tween = create_tween()
			shrink_tween.tween_property(balloon_node, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			shrink_tween.tween_callback(func():
				movement_speed = old_marching_speed
				if is_instance_valid(vision_sensor):
					vision_sensor.vision_range = old_vision_range
				balloon_node.queue_free()
			)
	)


func trigger_procedural_counter_window() -> void:
	if current_phase != PatrolPhase.MARCHING: return
	
	# Open the vulnerability lock and enforce a fresh strike rate cooldown pause clock
	is_vulnerable_to_counter = true
	combat_strike_cooldown_clock = randf_range(3.5, 5.0) # Attacks every 3-5 seconds organically
	
	# Flash the non-diegetic lightning bolt warning popups over his crown! [PDF: 0.1.11, 0.1.18]
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "⚡ ⚡"
		alert_label.modulate = Color("#33ccff") # Neon tactical parry sapphire blue!
		alert_label.visible = true
		alert_anchor.scale = Vector3.ZERO
		alert_bubble_spring_velocity = 16.0 # Snappy comic pop physics speed
		alert_bubble_display_timer = 0.45   # The counter intercept window duration length
		
	# Create a brief deferred one-shot timer to close the window and execute damage if missed!
	get_tree().create_timer(0.45).timeout.connect(func():
		if is_vulnerable_to_counter and current_phase == PatrolPhase.MARCHING:
			is_vulnerable_to_counter = false
			execute_unblocked_sword_swing_hit()
	)

func execute_unblocked_sword_swing_hit() -> void:
	# Close alert popup overlay tracks safely [PDF: 0.1.18]
	if is_instance_valid(alert_label): alert_label.visible = false
	
	# Verify Eira is still inside his strike range block before dealing damage
	if is_instance_valid(player_ref) and global_position.distance_to(player_ref.global_position) <= 2.4:
		print("⚔️ COMBAT DAMAGE: Guard lands an unblocked sword strike on Eira!")
		# Call her native shield block absorption metrics inside player.gd here!
		if player_ref.has_method("absorb_unblocked_combat_hit"):
			player_ref.absorb_unblocked_combat_hit(1)


func process_combat_chase_loop(delta: float) -> void:
	if not is_instance_valid(player_ref): return
	
	var vector_to_eira: Vector3 = player_ref.global_position - global_position
	vector_to_eira.y = 0.0 
	var distance_to_eira: float = vector_to_eira.length()
	
	# Close-Quarters Strike Pocket
	if distance_to_eira <= 1.8:
		# Freeze his feet movement lines smoothly so he doesn't drift past you
		velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)
		
		# === FIXED SPINNIG AXIS AXELS: ABSOLUTE HARDFACING LOCK ===
		# Instantly locks his torso orientation matrix directly onto Eira's skin centers,
		# completely crushing the weapon-swing delay when running tight circles around him!
		var heading_dir = vector_to_eira.normalized()
		if heading_dir.length_squared() > 0.01:
			var target_look_angle: float = atan2(-heading_dir.x, -heading_dir.z)
			global_rotation.y = target_look_angle # Instant snap lock! No sticky lerp delay loops!
			
		move_and_slide()
		
		# INSTANT WINDOW ACCELERATOR: Force attack countdown checks to tick down immediately when in-range
		if combat_strike_cooldown_clock <= 0.0 and current_phase == PatrolPhase.CHASING:
			trigger_procedural_counter_window()
	else:
		# Standard run tracking loop
		var heading_dir = vector_to_eira.normalized()
		var combat_run_speed: float = movement_speed * 1.35
		
		velocity.x = lerp(velocity.x, (heading_dir * combat_run_speed).x, acceleration * delta)
		velocity.z = lerp(velocity.z, (heading_dir * combat_run_speed).z, acceleration * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-heading_dir.x, -heading_dir.z), turn_speed * 1.5 * delta)
		move_and_slide()


# =============================================================================
#     12. DYNAMIC THERMAL RESIN IMMOBILIZATION CRYSTALLIZATION
# =============================================================================
func execute_resin_crust_freeze() -> void:
	if current_phase == PatrolPhase.STUNNED: return
	
	# Freeze his movement speed down completely to a dead standstill
	var _old_phase_state: PatrolPhase = current_phase
	current_phase = PatrolPhase.STUNNED
	velocity = Vector3.ZERO
	
	# Instantly drop a text message display block warning over his head
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "🧊 RESIN FREEZE! 🧊"
		alert_label.modulate = Color("#ffaa44") # Angry amber hardening color
		alert_label.visible = true
		alert_anchor.scale = Vector3(1.3, 1.3, 1.3)
		
	print("🧊 TRAP IMPACT: Molten dragon resin hardened over ", name, "'s armor! Immobilized.")
	
	# Schedule an automated brittle shell crack breakout callback after exactly 4.0 seconds!
	get_tree().create_timer(4.0).timeout.connect(func():
		if current_phase == PatrolPhase.STUNNED:
			current_phase = PatrolPhase.MARCHING # Return him to his pacing paths
			if is_instance_valid(alert_label): alert_label.visible = false
			print("💥 TRAP BREAKOUT: Brittle resin crust shattered. Guard freed.")
	)
