extends RigidBody3D

@export_category("Tactical Environmental Hazard Layout")
# Reusing your public VFX slot layout for absolute plug-and-play visual flexibility!
@export var shatter_vfx_blueprint: PackedScene 

var has_already_shattered: bool = false

@onready var crush_sensor: ShapeCast3D = $Crush_Sensor

func _ready() -> void:
	# Connect the native rigid body impact listener natively
	body_entered.connect(_on_physical_collision_registered)

func take_damage(_amount: int, _push_dir: Vector3 = Vector3.ZERO) -> void:
	# DUCK TYPING BRIDGE: When a pebble strike calls 'take_damage' on this prop, unfreeze it!
	trigger_environmental_plummet()

func trigger_environmental_plummet() -> void:
	if not freeze: return # Already falling!
	
	# THE PHYSICS ACTUATOR UNLOCK: Unfreeze the node natively inside Godot 4.5's server
	freeze = false
	print("HAZARD SYSTEMS: Pottery structural integrity broken! Gravity taking over.")
	
	# Apply a tiny random cartoon torque push nudge to make it wobble/tumble off the ledge beautifully
	apply_torque_impulse(Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))

func _physics_process(_delta: float) -> void:
	# Active real-time downward sweep detection while plummeting
	if not freeze and not has_already_shattered:
		if is_instance_valid(crush_sensor) and crush_sensor.is_colliding():
			# Scan through all intersected bodies inside the shape-cast matrix
			for i in range(crush_sensor.get_collision_count()):
				var hit_actor = crush_sensor.get_collider(i)
				if is_instance_valid(hit_actor) and hit_actor.is_in_group("EnemyGroup"):
					print("HAZARD COMBAT: ShapeCast detected enemy helmet! Injecting dizzy parameters.")
					if hit_actor.has_method("execute_cartoon_dizzy_state"):
						hit_actor.execute_cartoon_dizzy_state() # Instantly stun the guard!
					execute_pottery_shatter_climax()
					break

func _on_physical_collision_registered(body: Node) -> void:
	# If the plummeting physics prop hits a stone floor block, shatter instantly!
	if not freeze and not has_already_shattered:
		if body.is_in_group("WorldGeometry") or body.name == "StaticBody3D" or body is GridMap:
			execute_pottery_shatter_climax()

func execute_pottery_shatter_climax() -> void:
	if has_already_shattered: return
	has_already_shattered = true
	
	print("HAZARD SYSTEMS: Terracotta vase shattered into pieces!")
	
	# SPARK DUCK-TYPING DUST PLUG: Instantiate your takedown particle scene natively!
	if shatter_vfx_blueprint:
		var fx_instance = shatter_vfx_blueprint.instantiate() as Node3D
		get_tree().root.add_child(fx_instance)
		fx_instance.global_position = global_position
		
		# Validate emitting components safely across all node architectures
		if "emitting" in fx_instance:
			fx_instance.set("emitting", true)
		elif fx_instance.has_method("spawn_procedural_takedown_fx_cloud"):
			fx_instance.call("spawn_procedural_takedown_fx_cloud")
			
	# Safely clear the master prop scene out of active memory grids seamlessly
	queue_free()
