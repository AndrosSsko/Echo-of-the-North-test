extends CSGBox3D

# --- BARRICADE CONFIGURATION ---
@export_category("Barricade Parameters")
@export var structure_health: int = 3
@export var shake_intensity: float = 0.15

var is_destroyed: bool = false
var original_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	original_position = position

func take_damage(amount: int) -> void:
	if is_destroyed: return
	
	structure_health -= amount
	print("BARRICADE HIT: Structural integrity dropped to ", structure_health)
	
	if structure_health <= 0:
		execute_destruction()
	else:
		execute_hit_shake()

func execute_hit_shake() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", original_position.x + shake_intensity, 0.05)
	tween.tween_property(self, "position:x", original_position.x - shake_intensity, 0.05)
	tween.tween_property(self, "position:x", original_position.x, 0.05)

# --- REFACTORED NARRATIVE TRANSITION PIPELINE ---

func execute_destruction() -> void:
	is_destroyed = true
	print("BARRICADE SMASHED: Eira cleared the pathway through the ruins!")
	
	# Locate the objective label instance safely inside your global HUD scene tree
	var objective_label: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
	
	if is_instance_valid(objective_label):
		# Dynamically alter the visual text string to progress her journey!
		objective_label.text = "Current Goal: Evade the Hunter Scout & Find the Hatchery"
	
	# Safely clear this entire obstacle from the active physics memory layer
	queue_free()
