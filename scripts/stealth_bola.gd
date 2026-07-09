extends Area3D

@export var flight_speed: float = 16.0
@export var trap_duration: float = 4.0

var launch_direction: Vector3 = Vector3.ZERO
var lifetime: float = 2.0 # Delete automatically after 2 seconds if it hits nothing
var is_active: bool = false


func _ready() -> void:
	body_entered.connect(_on_obstacle_intersected)
	
	# Disable collision initially
	$CollisionShape3D.disabled = true
	# Wait 0.1 seconds to move out of the player, then activate
	await get_tree().create_timer(0.1).timeout
	$CollisionShape3D.disabled = false
	is_active = true

func initialize_bola_flight(dir: Vector3) -> void:
	launch_direction = dir.normalized()
	# Rotate the rope visual slightly every frame to simulate a spinning throw animation
	set_process(true)

func _process(delta: float) -> void:
	# Move the projectile forward lineally through space
	global_position += launch_direction * flight_speed * delta
	rotate_y(15.0 * delta) # Visual spin simulation
	
	lifetime -= delta
	if lifetime <= 0.0: queue_free()

func _on_obstacle_intersected(body: Node3D) -> void:
	if not is_active: return
	
	if body.name == "Player" or body.name == "Smudge" or body.is_in_group("PlayerGroup"): return
	
	# 1. TRIGGER ADAPTIVE AI BOLA LOGIC 
	# Routes the hit through our new stealth vs alert combat rules
	if body.is_in_group("EnemyGroup") or body.has_method("execute_long_range_bola_snag"):
		var current_suspicion = body.current_suspicion_value if "current_suspicion_value" in body else 0.0
		
		# GHOST INFILTRATION PATH: If the guard is un-alerted (<15 suspicion), drop them into the struggle state!
		if current_suspicion < 15.0 and body.has_method("execute_long_range_bola_snag"):
			body.execute_long_range_bola_snag()
			print("BOLA HIT: Caught an unsuspecting guard! Initiating 4-second struggle window.")
		else:
			# OPEN COMBAT PATH: If he already spotted you, pass normal damage and the launch vector push direction!
			if body.has_method("take_damage"):
				body.take_damage(1, launch_direction)
				print("BOLA HIT: Guard was already alert. Processing standard posture/thump damage.")
		
	# 2. TRIGGER PROP INTERACTION
	# Falls back to standard damage for destructible environment objects like walls or pottery
	elif body.has_method("take_damage"):
		if body.get_method_argument_count("take_damage") >= 2:
			body.take_damage(1, launch_direction)
		else:
			body.take_damage(1)
		
	# Instantly erase the projectile from memory after impact contact
	queue_free()
