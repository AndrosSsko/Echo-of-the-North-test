extends Area3D

# --- WIND VECTOR COEFFICIENTS ---
@export_category("Wind Parameters")
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, -2.5) # Force vector blowing toward the far wall
@export var wind_velocity_boost: float = 8.0

var is_eira_present: bool = false

func _ready() -> void:
	# Bind sensory overlaps to detect Eira's physical location status
	body_entered.connect(_on_player_entered_draft)
	body_exited.connect(_on_player_exited_draft)

func _process(_delta: float) -> void:
	# Real-time state check: If Eira is standing inside the draft, update her prompt description!
	if is_eira_present:
		var objective_label: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
		if is_instance_valid(objective_label) and not "WIND CURRENT" in objective_label.text:
			# Teach the rookie player about their spatial architectural options!
			var command_button: String = InputManager.get_action_button_text("companion_command")
			objective_label.text = "TACTICAL CHOICE: Press " + command_button + " to throw pebble into the wind current!"

func _on_player_entered_draft(body: Node3D) -> void:
	if body.name == "Player":
		is_eira_present = true
		
		# Give Eira's player instance a direct variable reference to this wind zone force modifier
		if body.has_method("set_active_wind_zone"):
			body.set_active_wind_zone(self)

func _on_player_exited_draft(body: Node3D) -> void:
	if body.name == "Player":
		is_eira_present = false
		if body.has_method("set_active_wind_zone"):
			body.set_active_wind_zone(null)
			
		# Revert screen goal tracking text back to default exploration streams smoothly
		var objective_label: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
		if is_instance_valid(objective_label):
			objective_label.text = "Current Goal: Evade the Hunter Scout & Find the Hatchery"
