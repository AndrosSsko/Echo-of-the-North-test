extends CharacterBody3D

enum PatrolPhase { MARCHING, INVESTIGATING, DIZZY, STUNNED, PANICKING, BOLA_STRUGGLE }

@export_category("Dynamic Field of View Constraints")
@export var vision_range: float = 9.0       # Max forward viewing reach limit
@export var vision_angle: float = 45.0       # Sight cone angle radius bounds
@export var suspicion_build_speed: float = 85.0
@export var suspicion_decay_speed: float = 65.0
@export var ray_density_multiplier: int = 40 # Number of physical rays cast to shape the mesh mesh

@export_category("Patrol Waypoints")
@export var movement_speed: float = 3.5
@export var investigation_speed: float = 4.2
@export var acceleration: float = 8.0
@export var turn_speed: float = 5.0





@export_category("Posture System")
@export var max_thump_posture: int = 5 
var current_thump_posture: int = 5
var dizzy_timer: float = 0.0
@export var dizzy_duration: float = 4.0 

var player_ref: CharacterBody3D = null
var current_suspicion_value: float = 0.0
var current_phase: PatrolPhase = PatrolPhase.MARCHING

var is_currently_armed: bool = true
var dropped_weapon_global_target_pos: Vector3 = Vector3.ZERO

@onready var dynamic_cone_mesh_instance: MeshInstance3D = $Dynamic_Vision_Cone
@onready var suspicion_label_3d: Label3D = find_child("Suspicion_Label", true, false)
@onready var takedown_label_3d: Label3D = $Takedown_Label
@onready var thump_label_3d: Label3D = $Thump_Label
@onready var visual_mesh: MeshInstance3D = $MeshInstance3D
@onready var cascade_sensor_area: Area3D = $Impact_Cascade_Sensor
@onready var point_a: Vector3 = $"../Patrol_Point_C".global_position if name == "Dragon_Hunter_High" else $"../Patrol_Point_A".global_position
@onready var point_b: Vector3 = $"../Patrol_Point_D".global_position if name == "Dragon_Hunter_High" else $"../Patrol_Point_B".global_position

@export_category("Lootable Rewards System")
@export var matches_to_award: int = 1
@export var bola_ammo_to_award: int = 1
@export_category("Disarm System Blueprint Layout")
@export var dropped_weapon_blueprint: PackedScene 
@export var hand_weapon_mesh: MeshInstance3D 
@export var alert_anchor: Node3D
@export var alert_label: Label3D

var alert_bubble_spring_scale: float = 0.0
var alert_bubble_spring_velocity: float = 0.0
var alert_bubble_display_timer: float = 0.0
var vision_cone_material: StandardMaterial3D = null
var cascade_slide_velocity: Vector3 = Vector3.ZERO
var current_target_destination: Vector3 = Vector3.ZERO
var noise_target_position: Vector3 = Vector3.ZERO
var phase_timer: float = 0.0
var is_flashing_alert: bool = false
var original_mesh_y: float = 0.0
var is_frantically_disarmed: bool = false
var active_dropped_weapon_instance: RigidBody3D = null
var max_stability: int
var current_stability: int
var is_currently_lootable: bool = false
var has_already_been_looted: bool = false
var bola_struggle_timer: float = 0.0

func _ready() -> void:
	max_stability = randi_range(2, 5)
	current_stability = max_stability
	add_to_group("EnemyGroup")
	current_target_destination = point_a
	current_thump_posture = max_thump_posture
	if is_instance_valid(visual_mesh):
		original_mesh_y = visual_mesh.position.y
	if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
	if is_instance_valid(takedown_label_3d): takedown_label_3d.visible = false
	if is_instance_valid(thump_label_3d): thump_label_3d.visible = false
	if is_instance_valid(dynamic_cone_mesh_instance):
		if is_instance_valid(dynamic_cone_mesh_instance.material_override):
			vision_cone_material = dynamic_cone_mesh_instance.material_override.duplicate() as StandardMaterial3D
			dynamic_cone_mesh_instance.material_override = vision_cone_material
		elif dynamic_cone_mesh_instance.get_active_material(0):
			vision_cone_material = dynamic_cone_mesh_instance.get_active_material(0).duplicate() as StandardMaterial3D
			dynamic_cone_mesh_instance.material_override = vision_cone_material

func _physics_process(delta: float) -> void:
	# 1. PANICKING STATE MATRIX OVERRIDE
	if current_phase == PatrolPhase.PANICKING:
		current_suspicion_value = 0.0
		if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
		process_weapon_scramble_panic_loop(delta)
		return
		
	# 2. TICK THE SPRING MATH VARIABLES EVERY FRAME TICK
	process_alert_bubble_spring_math(delta)
	
	# 3. SAFETY FALLBACK HOOKS
	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("PlayerGroup") as CharacterBody3D
		return
		
	# 4. INCAPACITATION GATES (STUNNED / DIZZY / BOLA_STRUGGLE)
	# Cleanly unified all 3 immobilization states together into one safe processing channel!
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.DIZZY or current_phase == PatrolPhase.BOLA_STRUGGLE:
		current_suspicion_value = 0.0
		velocity = Vector3.ZERO
		if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
		if is_instance_valid(takedown_label_3d): takedown_label_3d.visible = false
		
		# Execute specialized sub-state handlers
		if current_phase == PatrolPhase.DIZZY:
			process_dizzy_state(delta)
		elif current_phase == PatrolPhase.BOLA_STRUGGLE:
			process_bola_entanglement_struggle_loop(delta)
			
		# ACCIDENTAL DOMINO CASCADE EFFECT ENFORCER
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
			
		return # Exit cleanly after processing the active incapacitation frame
		
	# 5. CORE SENSORY & VISION ENGINE LOOPS
	var is_player_currently_visible: bool = evaluate_vision_state()
	
	if not is_player_currently_visible and current_phase == PatrolPhase.MARCHING:
		var all_guards = get_tree().get_nodes_in_group("EnemyGroup")
		for other_guard in all_guards:
			if is_instance_valid(other_guard) and other_guard != self:
				if "current_phase" in other_guard:
					if other_guard.current_phase == PatrolPhase.STUNNED:
						var distance_to_body = global_position.distance_to(other_guard.global_position)
						if distance_to_body <= vision_range:
							var forward_heading: Vector3 = -global_transform.basis.z.normalized()
							var vec_to_body: Vector3 = other_guard.global_position - global_position
							var angle_to_body: float = rad_to_deg(forward_heading.angle_to(vec_to_body.normalized()))
							
							if angle_to_body <= vision_angle:
								var space_state = get_world_3d().direct_space_state
								var ray_query = PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.5, 0.0), other_guard.global_position + Vector3(0.0, 0.5, 0.0))
								var ray_result = space_state.intersect_ray(ray_query)
								
								if ray_result.is_empty() or ray_result["collider"] == other_guard:
									investigate_noise(other_guard.global_position)
									if is_instance_valid(suspicion_label_3d):
										suspicion_label_3d.visible = true
										suspicion_label_3d.text = "❓ What happened here? ❓"
										suspicion_label_3d.modulate = Color("#33ccff")
										
	# Capture reset mechanics
	if current_suspicion_value >= 100.0:
		player_ref.trigger_capture_respawn()
		current_suspicion_value = 0.0
		current_phase = PatrolPhase.MARCHING
		current_target_destination = point_a
		
	# 6. ROUTE DISPATCH SWITCH STATE LOOP
	match current_phase:
		PatrolPhase.MARCHING:
			process_patrol_loop(delta)
		PatrolPhase.INVESTIGATING:
			process_investigation_loop(delta)


func process_alert_bubble_spring_math(delta: float) -> void:
	# THE EXPORT ALIGNMENT FIX: Use your new clean 'alert_anchor' and 'alert_label' variables!
	if is_instance_valid(alert_anchor) and is_instance_valid(alert_label):
		if alert_bubble_display_timer > 0.0:
			alert_bubble_display_timer -= delta
			alert_label.visible = true
			
			# --- HOOKE'S LAW EQUATION SOLVER ---
			var displacement: float = 1.0 - alert_bubble_spring_scale
			var spring_force: float = (displacement * 180.0) - (alert_bubble_spring_velocity * 14.0)
			
			alert_bubble_spring_velocity += spring_force * delta
			alert_bubble_spring_scale += alert_bubble_spring_velocity * delta
			
			# COMEDIC SQUASH & STRETCH EXTRUSION
			var stretch_x: float = alert_bubble_spring_scale + (alert_bubble_spring_velocity * 0.015)
			var squash_y: float = alert_bubble_spring_scale - (alert_bubble_spring_velocity * 0.012)
			alert_anchor.scale = Vector3(stretch_x, squash_y, alert_bubble_spring_scale)
			
			# Smoothly fade the text alpha during the final frames
			if alert_bubble_display_timer <= 0.4:
				alert_label.modulate.a = move_toward(alert_label.modulate.a, 0.0, 2.5 * delta)
		else:
			# Shutter close reset routines
			alert_label.visible = false
			alert_bubble_spring_scale = 0.0
			alert_bubble_spring_velocity = 0.0


# --- MASTER SENSORY OVERRIDE GATEWAY (REPLACE YOUR INVESTIGATE_NOISE ENTIRELY) ---
func investigate_noise(noise_pos: Vector3) -> void:
	if current_phase == PatrolPhase.DIZZY or current_phase == PatrolPhase.STUNNED:
		return
		
	var dialog_bubble_text: String = "HUH? What's that noise?"
	var _bubble_panel_tint: Color = Color("#33ccff") # Cyan bubble theme for general noise clatter
	
	# Group radar scanning check: Did a teammate drop flat out cold nearby?
	var all_guards = get_tree().get_nodes_in_group("EnemyGroup")
	var found_unconscious_ally: bool = false
	for other_guard in all_guards:
			if is_instance_valid(other_guard) and other_guard != self:
				# THE SAFETY GUARD FIX: Ensure the object actually has a phase variable!
				if "current_phase" in other_guard:
					if other_guard.current_phase == PatrolPhase.STUNNED and global_position.distance_to(other_guard.global_position) <= vision_range:
						found_unconscious_ally = true
						break
				
	if found_unconscious_ally:
		dialog_bubble_text = "WHAT HAPPENED?! This one is out cold!"
		_bubble_panel_tint = Color("#ff3333") # Urgent panic alert red
	elif current_suspicion_value > 45.0:
		dialog_bubble_text = "WHO'S THERE?! I know someone is hiding!"
		_bubble_panel_tint = Color("#ffcc00") # Warning alert amber orange
		
	get_node("/root/DialogueBox").roll_typewriter_dialogue("Guard", dialog_bubble_text, 0.05)
	
	# Trigger state mechanics updates
	if current_phase != PatrolPhase.INVESTIGATING:
		noise_target_position = noise_pos
		current_phase = PatrolPhase.INVESTIGATING
		phase_timer = 3.0 # Inspect the coordinates for 3 full seconds
		
		# --- INITIALIZE COMIIC SPRING STAGE ---
		if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
			alert_label.text = dialog_bubble_text
			
			# Drive the Comic Bubble background color panel texture in real-time
			alert_label.modulate = Color.BLACK # Text color stays black for sharp contrast
			
			# Reset alpha transparency levels and snap scale down to absolute zero
			alert_label.modulate.a = 1.0
			alert_anchor.scale = Vector3.ZERO
			
			# Give the spring velocity a heavy initial kick-start impulse value!
			# 12.0 launches it exploding outward instantly before it begins to wobble!
			alert_bubble_spring_velocity = 12.0 
			alert_bubble_spring_scale = 0.0
			alert_bubble_display_timer = 2.8 # Visible duration limit parameter

func evaluate_vision_state() -> bool:
	var smudge_node: Node = null
	
	# 1. INITIAL INSTANCE VALIDATION FALLBACKS
	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("PlayerGroup") as CharacterBody3D
		if not is_instance_valid(player_ref):
			clear_procedural_vision_mesh()
			return false
			
	# 2. THE STEALTH FOLIAGE COVER SHUTTER GATEWAY
	if "is_player_currently_visible" in player_ref:
		if not player_ref.is_player_currently_visible:
			current_suspicion_value = move_toward(current_suspicion_value, 0.0, 35.0 * get_process_delta_time())
			if is_instance_valid(suspicion_label_3d): suspicion_label_3d.visible = false
			construct_dynamic_clipping_vision_mesh()
			return false

	# 3. NATIVE ALGEBRAIC FIELD OF VIEW INTERSECTION CHECKS
	var is_player_tracked: bool = false
	var distance_to_eira: float = global_position.distance_to(player_ref.global_position)
	
	if distance_to_eira <= vision_range:
		var forward_heading: Vector3 = -global_transform.basis.z.normalized()
		var vector_to_eira: Vector3 = player_ref.global_position - global_position
		var angle_to_eira: float = rad_to_deg(forward_heading.angle_to(vector_to_eira.normalized()))
		
		if angle_to_eira <= vision_angle:
			var space_state = get_world_3d().direct_space_state
			var eye_level: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)
			var target_level: Vector3 = player_ref.global_position + Vector3(0.0, 0.5, 0.0)
			
			var sight_line_query = PhysicsRayQueryParameters3D.create(eye_level, target_level)
			
			# Fetch your companion handle safely (No 'var' keyword to respect upper scope!)
			smudge_node = get_tree().get_first_node_in_group("CompanionGroup")
			
			# --- BULLETPROOF SINGLE-LINE DIRECT INITIALIZATION ---
			if is_instance_valid(smudge_node):
				sight_line_query.exclude = [self.get_rid(), smudge_node.get_rid()]
			else:
				sight_line_query.exclude = [self.get_rid()]

			var ray_hit_data = space_state.intersect_ray(sight_line_query)
			if ray_hit_data.is_empty() or ray_hit_data["collider"] == player_ref:
				is_player_tracked = true

	# 4. COMPANION SMUDGE SIGHT CONE SCANNER
	var is_smudge_tracked: bool = false
	smudge_node = get_tree().get_first_node_in_group("CompanionGroup")
	
	if is_instance_valid(smudge_node):
		var dist_to_smudge: float = global_position.distance_to(smudge_node.global_position)
		if dist_to_smudge <= vision_range:
			var forward_heading: Vector3 = -global_transform.basis.z.normalized()
			var vec_to_smudge: Vector3 = smudge_node.global_position - global_position
			var angle_to_smudge: float = rad_to_deg(forward_heading.angle_to(vec_to_smudge.normalized()))
			
			if angle_to_smudge <= vision_angle:
				var space_state = get_world_3d().direct_space_state
				var eye_level: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)
				var target_level: Vector3 = smudge_node.global_position + Vector3(0.0, 0.5, 0.0)
				var smudge_query = PhysicsRayQueryParameters3D.create(eye_level, target_level)
				smudge_query.exclude = [self.get_rid()]
				
				var ray_hit = space_state.intersect_ray(smudge_query)
				if ray_hit.is_empty() or ray_hit["collider"] == smudge_node:
					is_smudge_tracked = true

	# 5. PROGRESSIVE SUSPICION BAR ACCUMULATOR
	if is_player_tracked or is_smudge_tracked:
		var active_dist = distance_to_eira if is_player_tracked else global_position.distance_to(smudge_node.global_position)
		# Stepping deeper into the cone fills the bar significantly faster
		var closeness_factor: float = remap(clamp(active_dist, 0.001, vision_range), 0.0, vision_range, 2.5, 0.8)
		current_suspicion_value = move_toward(current_suspicion_value, 100.0, 40.0 * closeness_factor * get_process_delta_time())
	else:
		current_suspicion_value = move_toward(current_suspicion_value, 0.0, 20.0 * get_process_delta_time())

	# 6. RENDER DETECTION TEXT WARNING LABELS
	if current_suspicion_value > 0.01:
		if is_instance_valid(suspicion_label_3d):
			suspicion_label_3d.visible = true
			if current_suspicion_value >= 100.0:
				suspicion_label_3d.text = "🚨 ALERT: Spotted! 🚨"
				suspicion_label_3d.modulate = Color("#ff3333")
				if current_phase == PatrolPhase.MARCHING:
					investigate_noise(player_ref.global_position if is_player_tracked else smudge_node.global_position)
			else:
				suspicion_label_3d.text = "👀 Detecting... " + str(int(current_suspicion_value)) + "% 👀"
				suspicion_label_3d.modulate = Color("#ffcc00")
	else:
		if is_instance_valid(suspicion_label_3d): 
			suspicion_label_3d.visible = false

	# RE-RENDER CLIPPED GEOMETRY
	construct_dynamic_clipping_vision_mesh()
	
	# === 6. RENDER DETECTION WARNING LABELS AND ALBEDO TINTS ===
	if is_instance_valid(dynamic_cone_mesh_instance) and is_instance_valid(vision_cone_material):
		if current_suspicion_value > 0.01:
			if is_instance_valid(suspicion_label_3d):
				suspicion_label_3d.visible = true
				
				if current_suspicion_value >= 100.0:
					suspicion_label_3d.text = "🚨 ALERT: Spotted! 🚨"
					suspicion_label_3d.modulate = Color("#ff3333")
					
					# COMBAT PHASE COLOR SHIFT: Flash Neon Crimson Red!
					vision_cone_material.albedo_color = Color(1.0, 0.2, 0.2, 0.22)
					
					if current_phase == PatrolPhase.MARCHING:
						investigate_noise(player_ref.global_position if is_player_tracked else smudge_node.global_position)
				else:
					suspicion_label_3d.text = "👀 Detecting... " + str(int(current_suspicion_value)) + "% 👀"
					suspicion_label_3d.modulate = Color("#ffcc00")
					
					# SUSPICION DETECTION COLOR SHIFT: Blend to Alert Amber Orange!
					# Linearly interpolate the color brightness based on how close they are to full alert!
					var blend_t: float = current_suspicion_value / 100.0
					vision_cone_material.albedo_color = Color(1.0, 0.6, 0.0, 0.16).lerp(Color(1.0, 0.4, 0.0, 0.2), blend_t)
		else:
			if is_instance_valid(suspicion_label_3d): 
				suspicion_label_3d.visible = false
				
			# RELAXED CALM STATE COLOR SHIFT: Default back to cool, passive Cyan Blue!
			if current_phase == PatrolPhase.INVESTIGATING:
				vision_cone_material.albedo_color = Color(0.2, 0.8, 1.0, 0.18) # Investigating Alert Cyan
			else:
				vision_cone_material.albedo_color = Color(0.1, 0.6, 1.0, 0.12) # Standard Patrol Calm Blue
	
	return current_suspicion_value >= 100.0
	#UPDATE YOUR STANDARD OPEN COMBAT STRIKES CHECK MESH
func execute_cartoon_dizzy_state() -> void:
	current_phase = PatrolPhase.DIZZY
	dizzy_timer = dizzy_duration
	velocity = Vector3.ZERO
	print("CARTOON PHYSICS: Guard posture shattered! Entering Dizzy State.")
	
	if is_instance_valid(thump_label_3d):
		thump_label_3d.text = "💫 DIZZY State! 💫"
		thump_label_3d.modulate = Color("#ff66cc") # Comedic pink tint

	# Comedic wobble loop animation: Spin his body mesh left-and-right rapidly!
	if is_instance_valid(visual_mesh):
		var w_tween = create_tween().set_loops(int(dizzy_duration / 0.3))
		w_tween.tween_property(visual_mesh, "rotation_degrees:y", 15.0, 0.15)
		w_tween.tween_property(visual_mesh, "rotation_degrees:y", -15.0, 0.15)

func process_dizzy_state(delta: float) -> void:
	dizzy_timer -= delta
	
	# FINISHER EXECUTION GATE: If the player strikes a DIZZY enemy, knock him out instantly!
	if is_instance_valid(player_ref) and player_ref.is_attacking and global_position.distance_to(player_ref.global_position) <= 2.2:
		execute_stealth_stun()
		return
		
	if dizzy_timer <= 0.0:
		print("AI SYSTEMS: Guard recovered his balance and stood back up.")
		current_phase = PatrolPhase.MARCHING
		current_thump_posture = max_thump_posture
		if is_instance_valid(thump_label_3d): thump_label_3d.visible = false
		if is_instance_valid(visual_mesh): visual_mesh.rotation_degrees.y = 0.0

func execute_stealth_stun(push_dir: Vector3 = Vector3.ZERO) -> void:
	spawn_procedural_takedown_fx_cloud()
	
	current_phase = PatrolPhase.STUNNED
	current_suspicion_value = 0.0
	cascade_slide_velocity = push_dir * 9.0
	
	# === THE LOOT REGISTRY ACTUATOR LOCK ===
	# If he hasn't been cleaned out yet, make him immediately search-ready on the floor!
	if not has_already_been_looted:
		is_currently_lootable = true
		print("LOOT SYSTEM: Guard capsule is now an active resource node on the floor.")
	
	# --- THE CARTOON EXPLOSION TRIGGER ---
	# Fires our procedural mesh generators on the exact frame of the takedown!
	spawn_procedural_takedown_fx_cloud()
	
	current_phase = PatrolPhase.STUNNED
	current_suspicion_value = 0.0
	cascade_slide_velocity = push_dir * 9.0
	
	var cone_node = get_node_or_null("Vision_Cone_Mesh")
	if is_instance_valid(cone_node):
		cone_node.visible = false
	
	if is_instance_valid(thump_label_3d):
		thump_label_3d.text = "💤 OUT COLD 💤"
		thump_label_3d.modulate = Color("#777777")
		
	print("STEALTH TAKEDOWN: Tilting master character capsule container onto its side!")
	rotation_degrees.x = 90.0
	position.y -= 0.6

# --- LOCOMOTION METHODS ---
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

func process_investigation_loop(delta: float) -> void:
	var vector_to_noise: Vector3 = noise_target_position - global_position
	vector_to_noise.y = 0.0
	if vector_to_noise.length() < 0.6:
		velocity = Vector3.ZERO
		phase_timer -= delta
		if phase_timer <= 0.0: 
			current_phase = PatrolPhase.MARCHING
			current_target_destination = point_b if current_target_destination == point_a else point_a
			
			# Wipe the alert timers so the bubble dissolves smoothly on patrol resume
			alert_bubble_display_timer = 0.0
			# Clear out investigation text banners cleanly when returning to patrol
			if is_instance_valid(suspicion_label_3d): 
				suspicion_label_3d.visible = false
	else:
		var heading_dir = vector_to_noise.normalized()
		velocity.x = lerp(velocity.x, (heading_dir * investigation_speed).x, acceleration * delta)
		velocity.z = lerp(velocity.z, (heading_dir * investigation_speed).z, acceleration * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-heading_dir.x, -heading_dir.z), turn_speed * delta)
		move_and_slide()

func execute_cascade_trip_fall() -> void:
	# Force the tripped guard into the stunned phase state loop comically
	current_phase = PatrolPhase.STUNNED
	velocity = Vector3.ZERO
	current_suspicion_value = 0.0
	
	if is_instance_valid(thump_label_3d):
		thump_label_3d.visible = true
		thump_label_3d.text = "💥 WHOOPS! 💥"
		thump_label_3d.modulate = Color("#ff3333")
		
	# Comedic flat-fall cartoon animation: Tilt his mesh flat opposite direction!
	if is_instance_valid(visual_mesh):
		visual_mesh.rotation_degrees.x = -90.0
		visual_mesh.position.y = -0.6
		
	# Automatically wake him back up and reset his posture nodes after 3 seconds
	get_tree().create_timer(3.0).timeout.connect(func():
		if current_phase == PatrolPhase.STUNNED and is_instance_valid(thump_label_3d) and thump_label_3d.text == "💥 WHOOPS! 💥":
			print("AI LOCOMOTION: Tripped guard scrambled back onto his feet.")
			current_phase = PatrolPhase.MARCHING
			current_thump_posture = max_thump_posture
			thump_label_3d.visible = false
			if is_instance_valid(visual_mesh):
				visual_mesh.rotation_degrees.x = 0.0
				visual_mesh.position.y = original_mesh_y
	)

func execute_bowling_knockdown(knock_direction: Vector3, force: float, upward_force: float) -> void:
	# Called by the player's slide tackle — the "cartoon bowling strike" hit.
	# Reuses the same STUNNED channel as trip-fall/stealth-stun so recovery, cascading
	# dominoes into nearby guards, and label/visual state all stay unified.
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.BOLA_STRUGGLE:
		return

	current_phase = PatrolPhase.STUNNED
	current_suspicion_value = 0.0
	cascade_slide_velocity = knock_direction * force

	if is_instance_valid(thump_label_3d):
		thump_label_3d.visible = true
		thump_label_3d.text = "💫 BOWLED OVER! 💫"
		thump_label_3d.modulate = Color("#ffaa00")

	# Comedic launch: quick pop upward, spin, then flop flat on his back
	if is_instance_valid(visual_mesh):
		var launch_tween := create_tween()
		launch_tween.tween_property(visual_mesh, "position:y", original_mesh_y + upward_force * 0.1, 0.12)
		launch_tween.parallel().tween_property(visual_mesh, "rotation_degrees:z", 360.0, 0.25)
		launch_tween.tween_property(visual_mesh, "position:y", -0.6, 0.18)
		launch_tween.tween_callback(func():
			if is_instance_valid(visual_mesh):
				visual_mesh.rotation_degrees.x = -90.0
				visual_mesh.rotation_degrees.z = 0.0
		)

	# Automatically wake him back up and reset his posture nodes after 3 seconds
	get_tree().create_timer(3.0).timeout.connect(func():
		if current_phase == PatrolPhase.STUNNED and is_instance_valid(thump_label_3d) and thump_label_3d.text == "💫 BOWLED OVER! 💫":
			print("AI LOCOMOTION: Bowled-over guard scrambled back onto his feet.")
			current_phase = PatrolPhase.MARCHING
			current_thump_posture = max_thump_posture
			thump_label_3d.visible = false
			if is_instance_valid(visual_mesh):
				visual_mesh.rotation_degrees.x = 0.0
				visual_mesh.rotation_degrees.z = 0.0
				visual_mesh.position.y = original_mesh_y
	)



func execute_player_capture() -> void:
	current_suspicion_value = 0.0
	current_phase = PatrolPhase.MARCHING
	current_target_destination = point_a
	
	# Wake up his sightlines and reset rotation transforms on player reload
	var cone_node = get_node_or_null("Vision_Cone_Mesh")
	if is_instance_valid(cone_node):
		cone_node.visible = true
		
	if is_instance_valid(visual_mesh):
		visual_mesh.rotation_degrees.x = 0.0
		visual_mesh.position.y = original_mesh_y
		
	rotation_degrees.x = 0.0 # Reset backup parent rotations too
	
	player_ref.trigger_capture_respawn()
	
func process_stunned_recovery(delta: float) -> void:
	phase_timer -= delta
	if phase_timer <= 0.0:
		print("HUNTER AI: Recovery timer expired. Resuming march routines.")
		current_phase = PatrolPhase.MARCHING
		# RESET STABILITY HERE:
		current_stability = max_stability 
		
		# Reset his structural capsule body back upright perfectly
		rotation_degrees.x = 0.0
		position.y += 0.6
		
		if is_instance_valid(thump_label_3d):
			thump_label_3d.visible = false
		var cone_node = get_node_or_null("Vision_Cone_Mesh")
		if is_instance_valid(cone_node):
			cone_node.visible = true

func execute_disarm_parry_drop() -> void:
	if is_frantically_disarmed or current_phase == PatrolPhase.STUNNED: return 
	
	is_frantically_disarmed = true
	is_currently_armed = false
	current_phase = PatrolPhase.PANICKING
	velocity = Vector3.ZERO
	
	# 1. Hide the weapon currently bound to his hand socket safely
	if is_instance_valid(hand_weapon_mesh):
		hand_weapon_mesh.visible = false
		
	# 2. Spawn the comical spinning physics replica into the world map
	if dropped_weapon_blueprint:
		var spawned_sword = dropped_weapon_blueprint.instantiate() as RigidBody3D
		get_tree().root.add_child(spawned_sword)
		
		# Align starting positions perfectly to match his hand anchor coordinates
		spawned_sword.global_position = hand_weapon_mesh.global_position
		spawned_sword.global_basis = hand_weapon_mesh.global_basis
		active_dropped_weapon_instance = spawned_sword
		
		# Apply a cartoonish upward & backward explosion impulse vector!
		var escape_direction: Vector3 = (global_transform.basis.z + Vector3(0.0, 1.2, 0.0)).normalized()
		var spin_torque: Vector3 = Vector3(randf_range(8.0, 20.0), randf_range(8.0, 20.0), 0.0)
		
		spawned_sword.apply_central_impulse(escape_direction * 9.0)
		spawned_sword.apply_torque_impulse(spin_torque)
		
	# 3. Pop the elastic comic-book text bubble!
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "😱 MY SWORD?! 😱"
		alert_anchor.visible = true
		alert_label.visible = true
		alert_label.modulate.a = 1.0
		
		# Quick comic bounce effect using a neat local spring tween layout
		var pop_tween = create_tween()
		alert_anchor.scale = Vector3.ZERO
		alert_bubble_spring_scale = 1.0 # Set safety flags for the background math
		alert_bubble_display_timer = 3.0
		pop_tween.tween_property(alert_anchor, "scale", Vector3(1.3, 1.3, 1.3), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(alert_anchor, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func process_weapon_scramble_panic_loop(delta: float) -> void:
	# Real-time path tracker targeting the actual physics body rolling across the map tiles!
	if is_instance_valid(active_dropped_weapon_instance):
		var target_sword_position: Vector3 = active_dropped_weapon_instance.global_position
		var vector_to_sword: Vector3 = target_sword_position - global_position
		vector_to_sword.y = 0.0
		
		if vector_to_sword.length() < 0.7:
			print("AI MECHANICS: Scramble success! Guard re-armed hand slots.")
			velocity = Vector3.ZERO
			
			# Kill the rolling projectile and reveal his hand blade back into visual matrix rows
			active_dropped_weapon_instance.queue_free()
			if is_instance_valid(hand_weapon_mesh):
				hand_weapon_mesh.visible = true
				
			is_currently_armed = true
			is_frantically_disarmed = false
			current_phase = PatrolPhase.MARCHING
			current_target_destination = point_a
		else:
			# Frantic run steering math loops
			var heading_dir = vector_to_sword.normalized()
			var panic_speed: float = movement_speed * 1.4 # High speed sprint panic pacing
			velocity.x = lerp(velocity.x, (heading_dir * panic_speed).x, acceleration * delta)
			velocity.z = lerp(velocity.z, (heading_dir * panic_speed).z, acceleration * delta)
			rotation.y = lerp_angle(rotation.y, atan2(-heading_dir.x, -heading_dir.z), turn_speed * 1.6 * delta)
			move_and_slide()
			
			
func spawn_procedural_takedown_fx_cloud() -> void:
	print("VISUAL ENGINE: Forcing CPU-driven cartoon smoke puffs onto helmet...")
	
	# 1. CREATE THE STABLE CPU EMITTER CONTAINERS
	var fx_root_node: Node3D = Node3D.new()
	var dust_emitter: CPUParticles3D = CPUParticles3D.new()
	var star_emitter: CPUParticles3D = CPUParticles3D.new()
	
	# Snap the effects container precisely to the guard's shoulders (0.8 meters up)
	get_tree().root.add_child(fx_root_node)
	fx_root_node.global_position = global_position + Vector3(0.0, 0.8, 0.0)
	
	fx_root_node.add_child(dust_emitter)
	fx_root_node.add_child(star_emitter)
	
	# =========================================================================
	# CONTAINER A: TUNING THE FLUFFY CARTOON DUST PUFF EMITTER
	# =========================================================================
	dust_emitter.one_shot = true
	dust_emitter.lifetime = 0.35
	dust_emitter.explosiveness = 1.0
	dust_emitter.amount = 12
	
	# CPUParticles3D settings are assigned directly to the node properties!
	dust_emitter.gravity = Vector3.ZERO # Stops the cloud from plunging into the floor tiles
	dust_emitter.direction = Vector3(0.0, 1.0, 0.0)
	dust_emitter.spread = 180.0 # Blows outward into a perfect rounded sphere explosion
	dust_emitter.initial_velocity_min = 4.0
	dust_emitter.initial_velocity_max = 4.0
	dust_emitter.damping_min = 7.0
	dust_emitter.damping_max = 7.0
	
	# Procedural scale expansion over time
	dust_emitter.scale_amount_min = 1.0
	dust_emitter.scale_amount_max = 1.8
	
	# Generate the visual mesh shape (Fluffy billboard smoke circle cards)
	var cloud_quad_mesh: QuadMesh = QuadMesh.new()
	cloud_quad_mesh.size = Vector2(0.6, 0.6)
	
	var dust_draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	dust_draw_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	dust_draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85) # High-visibility thick white
	dust_draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dust_draw_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	
	# THE CELL-SHADED BLACK OUTLINE: Chains a bold black border line around the smoke pieces
	var outline_mat: StandardMaterial3D = StandardMaterial3D.new()
	outline_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	outline_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	outline_mat.grow = true
	outline_mat.grow_amount = 0.04 # 4cm thick ink line width
	dust_draw_mat.next_pass = outline_mat
	
	cloud_quad_mesh.material = dust_draw_mat
	dust_emitter.mesh = cloud_quad_mesh
	
	# =========================================================================
	# CONTAINER B: TUNING THE SPINNING DIZZY STARS EMITTER
	# =========================================================================
	star_emitter.one_shot = true
	star_emitter.lifetime = 1.0
	star_emitter.explosiveness = 0.8
	star_emitter.amount = 4
	
	star_emitter.gravity = Vector3.ZERO
	star_emitter.spread = 0.0
	star_emitter.orbit_velocity_min = 3.0 # The vector that forces the stars to circle his head
	star_emitter.orbit_velocity_max = 3.0
	
	var star_mesh: PrismMesh = PrismMesh.new()
	star_mesh.size = Vector3(0.12, 0.25, 0.12)
	
	var star_draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	star_draw_mat.albedo_color = Color("#ffff00") # Neon golden yellow!
	star_draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	star_mesh.material = star_draw_mat
	star_emitter.mesh = star_mesh
	
	# =========================================================================
	# RE-ARM ACTUATORS & AUTO-DESTRUCT RECOVERY
	# =========================================================================
	dust_emitter.emitting = true
	star_emitter.emitting = true
	
	# Automatically clean up the procedural system once the animation wraps up
	get_tree().create_timer(1.2).timeout.connect(func():
		fx_root_node.queue_free()
	)


# Place inside the AI's _physics_process or vision loop
func check_for_fallen_allies() -> void:
	for body in get_tree().get_nodes_in_group("UnconsciousEnemy"):
		if global_position.distance_to(body.global_position) < vision_range:
			# Simple line-of-sight check
			var space_state = get_world_3d().direct_space_state
			var result = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, body.global_position))
			
			if result and result["collider"] == body:
				print("AI SENSORS: Found an ally! Investigating...")
				current_phase = PatrolPhase.INVESTIGATING
				noise_target_position = body.global_position

func construct_dynamic_clipping_vision_mesh() -> void:
	if not is_instance_valid(dynamic_cone_mesh_instance): return
	
	# Fetch the pre-allocated immediate mesh resource container from the node property slot
	var immediate_mesh: ImmediateMesh = dynamic_cone_mesh_instance.mesh as ImmediateMesh
	if not immediate_mesh: return
	
	# GODOT 4.7 CLEANUP: Always clear old surface memory layers completely before re-allocating!
	immediate_mesh.clear_surfaces()
	
	var space_state = get_world_3d().direct_space_state
	var eye_origin: Vector3 = global_position + Vector3(0.0, 0.1, 0.0) # Hover just slightly off the floor tiles
	
	var perimeter_vertex_points: Array[Vector3] = []
	var angle_increment_step: float = (vision_angle * 2.0) / ray_density_multiplier
	
	# --- HORIZONTAL RADIAL RAY-CAST SWEEP CONSTRUCTOR ---
	for i in range(ray_density_multiplier + 1):
		var current_ray_angle_deg: float = -vision_angle + (i * angle_increment_step)
		var current_ray_angle_rad: float = deg_to_rad(current_ray_angle_deg)
		
		var local_ray_dir: Vector3 = Vector3(sin(current_ray_angle_rad), 0.0, -cos(current_ray_angle_rad))
		var global_ray_target_dir: Vector3 = (global_transform.basis * local_ray_dir).normalized()
		var optimal_reach_destination: Vector3 = eye_origin + (global_ray_target_dir * vision_range)
		
		var geometry_ray_query = PhysicsRayQueryParameters3D.create(eye_origin, optimal_reach_destination)
		
		# Isolated inline physics exclusions safely bypassing memory pointer overlaps
		var current_smudge = get_tree().get_first_node_in_group("CompanionGroup")
		if is_instance_valid(current_smudge):
			geometry_ray_query.exclude = [self.get_rid(), current_smudge.get_rid()]
		else:
			geometry_ray_query.exclude = [self.get_rid()]
			
		var contact_data = space_state.intersect_ray(geometry_ray_query)
		if not contact_data.is_empty():
			var local_collision_offset: Vector3 = to_local(contact_data["position"])
			local_collision_offset.y = 0.1 # Keep it flattened to floor planes
			perimeter_vertex_points.append(local_collision_offset)
		else:
			var local_reach_offset: Vector3 = to_local(optimal_reach_destination)
			local_reach_offset.y = 0.1
			perimeter_vertex_points.append(local_reach_offset)
			
	# --- GODOT 4.7 UPGRADED PRIMITIVE SURFACE DRAW STREAM ---
	# Uses the modern explicit material pipeline to populate primitive triangles safely
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(perimeter_vertex_points.size() - 1):
		# Triangle Vertex 1: The guard's center local origin position point
		immediate_mesh.surface_add_vertex(Vector3(0, 0.1, 0))
		# Triangle Vertex 2: Current ray slice edge point
		immediate_mesh.surface_add_vertex(perimeter_vertex_points[i])
		# Triangle Vertex 3: Next sequential ray slice edge point (bridges the gap!)
		immediate_mesh.surface_add_vertex(perimeter_vertex_points[i + 1])
		
	immediate_mesh.surface_end()
	dynamic_cone_mesh_instance.mesh = immediate_mesh

func clear_procedural_vision_mesh() -> void:
	if is_instance_valid(dynamic_cone_mesh_instance):
		dynamic_cone_mesh_instance.mesh = null
		
func execute_long_range_bola_snag() -> void:
	if current_phase == PatrolPhase.STUNNED or current_phase == PatrolPhase.BOLA_STRUGGLE: return
	
	# Fall flat layout onto the floor tiles but stay conscious!
	current_phase = PatrolPhase.BOLA_STRUGGLE
	bola_struggle_timer = 4.0 # Give the player exactly 4 seconds to sprint over and finish him!
	velocity = Vector3.ZERO
	
	if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
		alert_label.text = "⛓️ CRAP! BOLA TRAP! ⛓️"
		alert_label.modulate = Color("#ffcc00") # High caution amber
		alert_anchor.visible = true
		alert_label.visible = true
		alert_label.modulate.a = 1.0

func process_bola_entanglement_struggle_loop(delta: float) -> void:
	if bola_struggle_timer > 0.0:
		bola_struggle_timer -= delta
		
		# Comedic panic struggle rattle: Make his capsule wobble while tangled up!
		# (Simulates trying to break free from Viking engineering cords!)
		rotation_degrees.z = sin(Time.get_ticks_msec() * 0.04) * 25.0
		
		# Display a countdown warning text overhead so the player tracks the window
		if is_instance_valid(alert_label):
			alert_label.text = "⏳ STEALTH LIMIT: " + str(snapped(bola_struggle_timer, 0.1)) + "s ⏳"
	else:
		# TIMEOUT BREAKPOINT: The player failed to finish him off! Sound the absolute alarm!
		rotation_degrees.z = 0.0 # Reset his orientation angle
		current_suspicion_value = 100.0
		current_phase = PatrolPhase.MARCHING
		investigate_noise(player_ref.global_position if is_instance_valid(player_ref) else global_position)
		
		if is_instance_valid(alert_label) and is_instance_valid(alert_anchor):
			alert_label.text = "🚨 INTRUDER ALERT!! 🚨"
			alert_label.modulate = Color("#ff3333")
