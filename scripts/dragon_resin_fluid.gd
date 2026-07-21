extends Area3D
class_name DragonResinFluid

@export var flight_speed: float = 16.0
@export var resin_structure_blueprint: PackedScene = preload("res://scenes/gadgets/hardened_resin_structure.tscn")

var move_direction: Vector3 = Vector3.FORWARD
var current_heat_ratio: float = 1.0 

# === FIXED ENGINE CRASH SAFETY DEBOUNCE VALVE [PDF: 0.1.6] ===
var has_already_impacted: bool = false

func _ready() -> void:
	body_entered.connect(_on_fluid_impact_registered)
	get_tree().create_timer(4.0).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	if has_already_impacted: return # Stop moving if processing a cleanup frame
	global_position += move_direction * flight_speed * delta

func _on_fluid_impact_registered(body: Node) -> void:
	if has_already_impacted: return
	if body == self or body.is_in_group("PlayerGroup") or body.name == "Player" or body.name == "Smudge":
		return
		
	has_already_impacted = true
	
	# === FIXED COMPILER BLOCK GATES: SAFELY DEFER COLLISION CLOSURES ===
	# This uses set_deferred to turn off physics checks right AFTER the signal finishes,
	# completely wiping out your 'Function blocked during in/out signal' console warnings!
	call_deferred("set_monitoring", false)
	call_deferred("set_monitorable", false)
	
	print("💧 RESIN PIPELINE: Molten liquid struck obstacle surface: ", body.name)

	
	# =============================================================================
	#     FORM FORMATION A: IMPACT DIRECTLY ON ENEMY GUARDS
	# =============================================================================
	if body.is_in_group("EnemyGroup"):
		if body.has_method("execute_resin_crust_freeze"):
			body.execute_resin_crust_freeze()
		queue_free()
		return

	# =============================================================================
	#     FORM FORMATION B: ENVIRONMENTAL RAYCAST TRACES [PDF: 0.1.8]
	# =============================================================================
	var space_state = get_world_3d().direct_space_state
	
	# FIXED SYNTAX GATES: Casts a tight probe from behind the fluid to its forward edge
	var probe_query = PhysicsRayQueryParameters3D.create(global_position - (move_direction * 0.5), global_position + (move_direction * 0.5))
	probe_query.exclude = [self.get_rid()]
	
	# Setting mask to 0xFFFFFFFF tells the raycast to check ALL collision layers in your scene!
	probe_query.collision_mask = 4294967295
	
	# Exclude her capsule body to prevent glitching offsets
	var player_char = get_tree().get_first_node_in_group("PlayerGroup")
	if is_instance_valid(player_char):
		probe_query.exclude = [player_char.get_rid(), self.get_rid()]
		
	var probe_hit = space_state.intersect_ray(probe_query)
	
	if not probe_hit.is_empty() and resin_structure_blueprint:
		var hit_pos: Vector3 = probe_hit["position"]
		var hit_normal: Vector3 = probe_hit["normal"]
		
		var spawned_structure = resin_structure_blueprint.instantiate() as HardenedResinStructure
		get_tree().current_scene.add_child(spawned_structure)
		
		# If the struck surface is a vertical wall face, shape it into a climbable ledge!
		if abs(hit_normal.dot(Vector3.UP)) < 0.15:
			spawned_structure.configure_structure_form(spawned_structure.StructureType.WALL_LEDGE, hit_pos, hit_normal)
		else:
			# Build a flat foot-bridge pathway spanning 3 meters long [PDF: 0.1.20]
			spawned_structure.configure_structure_form(spawned_structure.StructureType.FOOT_BRIDGE, hit_pos, hit_normal, 3.0)
			
	queue_free()
