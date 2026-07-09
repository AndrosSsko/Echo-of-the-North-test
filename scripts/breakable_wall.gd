extends Area3D # FIXED: Changed from CSGBox3D to Area3D to perfectly match your new root!

# --- BARRICADE CONFIGURATION ---
@export_category("Durability Parameters")
@export var structure_health: int = 2 # Requires exactly two heavy axe strikes to break!
@export var shake_intensity: float = 0.15

var is_destroyed: bool = false
var original_position: Vector3 = Vector3.ZERO

@onready var visual_mesh: CSGBox3D = $Wall_Mesh

func _ready() -> void:
	# CRITICAL PLAYER HOOK: Adds this shape to the group Eira's weapon loop checks for!
	add_to_group("InteractableGroup")
	if is_instance_valid(visual_mesh):
		original_position = visual_mesh.position



# This function is triggered directly by Eira's player.gd weapon impact frame!
func take_damage(amount: int, _push_dir: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed: return
	
	structure_health -= amount
	print("DESTRUCTIBLE WALL HIT: Structural integrity dropped to ", structure_health)
	
	if structure_health <= 0:
		execute_destruction()
	else:
		execute_hit_shake()

func execute_hit_shake() -> void:
	if is_instance_valid(visual_mesh):
		var tween: Tween = create_tween()
		tween.tween_property(visual_mesh, "position:x", original_position.x + shake_intensity, 0.05)
		tween.tween_property(visual_mesh, "position:x", original_position.x - shake_intensity, 0.05)
		tween.tween_property(visual_mesh, "position:x", original_position.x, 0.05)

func execute_destruction() -> void:
	is_destroyed = true
	print("DESTRUCTIBLE WALL SMASHED: Eira cleared the detour pathway through the ruins!")
	
	# THE TREE ENTRY FIX: Cache the wall's current global position right now 
	# before we change any scene hierarchy node properties!
	var wall_impact_location: Vector3 = global_position
	
	if is_instance_valid(visual_mesh):
		visual_mesh.visible = false
		visual_mesh.queue_free()
		
	# Spawn a massive visual feedback dust cloud puff using your asset particle template
	var debris_blueprint = load("res://scenes/footstep_dust.tscn")
	if debris_blueprint:
		var debris_instance = debris_blueprint.instantiate() as GPUParticles3D
		
		# SAFE SEQUENCE: Add the child to the root tree FIRST so it is fully inside the tree matrix...
		get_tree().root.add_child(debris_instance)
		
		# ...and NOW it is completely safe to assign its 3D global position and scale vectors!
		debris_instance.global_position = wall_impact_location
		debris_instance.scale = Vector3(2.5, 2.5, 2.5) # Scale up dust cloud puff comically
		debris_instance.emitting = true
		debris_instance.finished.connect(func(): debris_instance.queue_free())
		
	# Safely clear the master root area container from the active scene memory tree layer
	queue_free()
