extends StaticBody3D
class_name HardenedResinStructure

enum StructureType { WALL_LEDGE, FOOT_BRIDGE }
var current_form: StructureType = StructureType.WALL_LEDGE

@export var structural_lifetime: float = 12.0

@onready var main_collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_mesh: MeshInstance3D = $VisualMesh
@onready var interaction_volume: Area3D = $InteractionVolume

var is_player_inside_climb_zone: bool = false

func _ready() -> void:
	# Enforce absolute group tagging
	add_to_group("ResinStructure")
	
	# Connect interaction prompt listeners
	interaction_volume.body_entered.connect(_on_player_entered_zone)
	interaction_volume.body_exited.connect(_on_player_exited_zone)
	
	# Schedule an automatic brittle structural breakdown
	get_tree().create_timer(structural_lifetime).timeout.connect(execute_brittle_fracture)

func configure_structure_form(type: StructureType, target_global_pos: Vector3, surface_normal: Vector3, span_distance: float = 1.0) -> void:
	current_form = type
	global_position = target_global_pos
	
	# Create a gorgeous crystalline amber material override look
	var amber_material = StandardMaterial3D.new()
	amber_material.albedo_color = Color("#ff8c00", 0.75) # Translucent glowing amber
	amber_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	amber_material.metallic = 0.3
	amber_material.roughness = 0.4
	if is_instance_valid(visual_mesh):
		visual_mesh.material_override = amber_material

	match current_form:
		StructureType.WALL_LEDGE:
			# Shape it into a flat, protruding horizontal wall ledge Eira can pull up onto
			look_at(global_position + surface_normal, Vector3.UP)
			if is_instance_valid(main_collision_shape) and main_collision_shape.shape is BoxShape3D:
				main_collision_shape.shape.size = Vector3(1.4, 0.15, 0.5) # Wide thin climbing ledge
			if is_instance_valid(visual_mesh) and visual_mesh.mesh is BoxMesh:
				visual_mesh.mesh.size = Vector3(1.4, 0.15, 0.5)
				
		StructureType.FOOT_BRIDGE:
			# Shape it into a long, flat footbridge bridging a narrow chasm
			look_at(global_position + surface_normal, Vector3.UP)
			if is_instance_valid(main_collision_shape) and main_collision_shape.shape is BoxShape3D:
				main_collision_shape.shape.size = Vector3(0.8, 0.1, span_distance)
			if is_instance_valid(visual_mesh) and visual_mesh.mesh is BoxMesh:
				visual_mesh.mesh.size = Vector3(0.8, 0.1, span_distance)

func _physics_process(_delta: float) -> void:
	if is_player_inside_climb_zone and current_form == StructureType.WALL_LEDGE:
		# Check if the player presses your native Interact key mapping (Joypad Button 13 / Key E)
		if Input.is_action_just_pressed("interact"):
			execute_climb_mantle_dispatch()

func _on_player_entered_zone(body: Node3D) -> void:
	if body.is_in_group("PlayerGroup") or body.name == "Player":
		is_player_inside_climb_zone = true
		# Hook onto her HUD overlay UI systems to show "[E] Climb Ledge"
		if body.has_method("display_interaction_prompt"):
			body.display_interaction_prompt("Climb Ledge")

func _on_player_exited_zone(body: Node3D) -> void:
	if body.is_in_group("PlayerGroup") or body.name == "Player":
		is_player_inside_climb_zone = false
		if body.has_method("clear_interaction_prompt"):
			body.clear_interaction_prompt()

func execute_climb_mantle_dispatch() -> void:
	var player = get_tree().get_first_node_in_group("PlayerGroup")
	if is_instance_valid(player) and player.has_method("execute_procedural_ledge_pull"):
		is_player_inside_climb_zone = false
		player.clear_interaction_prompt()
		
		# Teleport her over the ledge vector heights smoothly until your animations are ready!
		var target_top_landing_pos = global_position + Vector3(0.0, 0.8, 0.0) - global_transform.basis.z * 0.4
		player.execute_procedural_ledge_pull(target_top_landing_pos)

func execute_brittle_fracture() -> void:
	print("💥 RESIN SYSTEM: Crystalline structure fractured, shattered, and cleared memory.")
	# Symmetrical EventBus dust cloud pops can explode over these coordinates later
	queue_free()
