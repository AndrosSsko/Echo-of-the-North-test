extends Node3D

var stake_a_position: Vector3 = Vector3.ZERO
var stake_b_position: Vector3 = Vector3.ZERO
var is_active_tripwire: bool = false

# Component lookups read physical primitive mesh elements inside your .tscn scene [PDF: 0.1.20]
@onready var main_blade_housing: Node3D = get_node_or_null("HousingMesh")
@onready var stone_harpoon_bolt: Node3D = get_node_or_null("StoneBoltMesh")
@onready var taut_rope_line: MeshInstance3D = get_node_or_null("RopeVisualMesh")
@onready var trigger_bumper_volume: Area3D = get_node_or_null("TriggerArea3D")

func initialize_tripwire(pos_a: Vector3, pos_b: Vector3) -> void:
	stake_a_position = pos_a
	stake_b_position = pos_b
	is_active_tripwire = true
	
	# 1. MOUNT MAIN GEAR CASING TO WALL A [PDF: 0.1.20]
	if is_instance_valid(main_blade_housing):
		main_blade_housing.global_position = pos_a
		main_blade_housing.look_at(pos_b, Vector3.UP)
		
	# 2. MOUNT HEAVY PROJECTILE BOLT TO WALL B [PDF: 0.1.20]
	if is_instance_valid(stone_harpoon_bolt):
		stone_harpoon_bolt.global_position = pos_b
		stone_harpoon_bolt.look_at(pos_a, Vector3.UP)
		
	# 3. STRETCH THE PHYSICAL ROPE LINE: Scale Z axis to cleanly bridge the hallway width gap [PDF: 0.1.20]
	if is_instance_valid(taut_rope_line):
		var corridor_span_width: float = pos_a.distance_to(pos_b)
		taut_rope_line.global_position = pos_a.lerp(pos_b, 0.5)
		taut_rope_line.look_at(pos_b, Vector3.UP)
		taut_rope_line.scale = Vector3(1.0, 1.0, corridor_span_width)
		
	# 4. ALIGN COLLISION VOLUMES: Scale shape size to match exact cord distances [PDF: 0.1.20]
	if is_instance_valid(trigger_bumper_volume):
		trigger_bumper_volume.global_position = pos_a.lerp(pos_b, 0.5)
		trigger_bumper_volume.look_at(pos_b, Vector3.UP)
		
		var bumper_shape = trigger_bumper_volume.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if is_instance_valid(bumper_shape) and bumper_shape.shape is BoxShape3D:
			# Stretches collision capsule box perfectly parallel along the rope path lines
			bumper_shape.shape.size = Vector3(0.15, 0.4, pos_a.distance_to(pos_b))
			
		# Connect overlap filters to listen to passing guards [PDF: 0.1.20]
		if not trigger_bumper_volume.body_entered.is_connected(_on_guard_crossed_wire):
			trigger_bumper_volume.body_entered.connect(_on_guard_crossed_wire)
		
	print("TRIPWIRE TRAP: Spring loaded Viking harpoon armed successfully across hallway corridor!")

func _on_guard_crossed_wire(body: Node3D) -> void:
	if not is_active_tripwire: return
	if body.name == "Player" or body.is_in_group("PlayerGroup"): return
	
	# === CINEMATIC KNOCKDOWN SPRING IMPACT TRIGGER === [PDF: 0.1.21]
	if body.is_in_group("EnemyGroup") and body.has_method("execute_long_range_bola_snag"):
		is_active_tripwire = false
		
		# The tension mechanism snaps, pulling the rope and slamming the stone forward to knock him out cold!
		body.execute_long_range_bola_snag()
		print("TRAP SNAPPED: Guard tripped rope cord! Pulling spring and slamming stone bolt forward!")
		
		# Instantly free up resource memory chains
		queue_free()
