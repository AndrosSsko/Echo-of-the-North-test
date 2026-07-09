extends CSGBox3D

# --- CRATE STRUCTURE PARAMETERS ---
@export_category("Crate Settings")
@export var crate_health: int = 1
@export var shake_intensity: float = 0.12

var is_broken: bool = false
var original_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Cache original coordinate placement parameters for our hit-shake animations
	original_pos = position

# Triggered automatically when Eira's Melee_Hitbox intersect shape sweeps through this object space
func take_damage(amount: int) -> void:
	if is_broken: return
	
	crate_health -= amount
	if crate_health <= 0:
		execute_splinter_destruction()
	else:
		execute_hit_twitch()

func execute_hit_twitch() -> void:
	# A quick, programmatic game-feel twitch to show physical impact feedback
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", original_pos.x + shake_intensity, 0.04)
	tween.tween_property(self, "position:x", original_pos.x - shake_intensity, 0.04)
	tween.tween_property(self, "position:x", original_pos.x, 0.04)

func execute_splinter_destruction() -> void:
	is_broken = true
	print("CRATE SHATTERED: Eira broke open the supply box!")
	
	# --- NARRATIVE DISCOVERY DISPATCH ---
	# Locate the objective label instance safely inside your global HUD scene tree
	var objective_label: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
	if is_instance_valid(objective_label):
		# Dynamically alter the text box tracker on her screen to guide her curiosity!
		objective_label.text = "Current Goal: [LORE DISCOVERED] Read her travel journal at the campfire!"
		
	# Future Expansion Hook: Instantiate splintering wood particle effects or a physical paper scroll asset here!
		
	# Safely delete this container obstacle node from the active physics memory layer
	queue_free()
