extends RigidBody3D

@export var trap_duration: float = 4.0
var launch_direction: Vector3 = Vector3.ZERO
var is_active: bool = false
var lifetime: float = 3.5 # Automatically vaporizes after 3.5 seconds if it flies off-map [PDF: 0.1.32]

func _ready() -> void:
	# 1. CONNECT NATIVE CONTACT SIGNALS [PDF: 0.1.32]
	body_entered.connect(_on_bola_impact_registered)
	contact_monitor = true
	max_contacts_reported = 1
	
	# 2. SAFETY LAUNCH SHUTTER BOUNDARY [PDF: 0.1.32]
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	await get_tree().create_timer(0.08).timeout
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = false
	is_active = true

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

# === THE DATA-DRIVEN INITIALIZATION ENGINE (CALLED DYNAMICALLY BY PROJECTILELAUNCHER) === [PDF: 0.1.33]
func initialize_bola_flight(direction: Vector3, speed: float) -> void:
	print("BOLA PIPELINE: Firing parameters received! Launching rigid physics body.")
	launch_direction = direction.normalized()
	
	# Apply an instant high-velocity physics thrust impulse forward [PDF: 0.1.33]
	var launch_impulse_vector: Vector3 = launch_direction * speed
	apply_central_impulse(launch_impulse_vector)

func _on_bola_impact_registered(body: Node) -> void:
	if not is_active: return
	
	# Safety Gate: Skip her own character collision capsules or companion nodes [PDF: 0.1.33]
	if body.is_in_group("PlayerGroup") or body.name == "Player" or body.name == "Smudge" or body == self:
		return
		
	print("BOLA PIPELINE: Direct impact contact registered against: ", body.name)
	
	# =============================================================================
	# 1. STEALTH VS COMBAT AWARENESS EVENT ROUTER [PDF: 0.1.33, 0.1.34]
	# =============================================================================
	if body.is_in_group("EnemyGroup"):
		var current_suspicion: float = 0.0
		
		# Look up his live suspicion levels using his modular VisionSensor component
		if body.has_node("VisionSensor3D"):
			current_suspicion = body.get_node("VisionSensor3D").current_suspicion
			
		# === PATH A: UNSUSPECTING INFILTRATION SNAG === [PDF: 0.1.34]
		if current_suspicion < 15.0:
			print("BOLA PIPELINE: Caught unsuspecting guard! Yelling into global EventBus.")
			# Tell the EventBus: (Type 0 = Bola, global_position, radius = 1.0)
			# Nearby guard tasks will intercept this and freeze his legs instantly!
			if is_instance_valid(EventBus):
				EventBus.gadget_impact.emit(0, global_position, 1.0)
				
		# === PATH B: OPEN ALERT COMBAT BALANCE STRIP === [PDF: 0.1.34]
		else:
			print("BOLA PIPELINE: Guard is fully alert. Deducting stability posture hit points.")
			if body.has_method("take_damage"):
				body.take_damage(1, launch_direction)
				
			# AUDIO PERCEPTION INTERCEPT: Emit a loud metal strike distraction sound to alert allies!
			if is_instance_valid(EventBus) and EventBus.has_signal("distraction_sound_emitted"):
				EventBus.distraction_sound_emitted.emit(global_position, 8.0)
				
		queue_free()
		return
		
	# =============================================================================
	# 2. DESTRUCTIBLE PROP FALLBACK INTERACTION [PDF: 0.1.34]
	# =============================================================================
	elif body.has_method("take_damage"):
		body.take_damage(1, launch_direction)
		queue_free()
