extends Area3D

@export_category("Sector View Adjustments")
# Controls the custom target angle when Eira is inside this trigger volume
@export var sector_angle_override: float = -45.0 

func _ready() -> void:
	# Connect our native trigger overlaps safely
	body_entered.connect(_on_player_entered_sector)
	body_exited.connect(_on_player_exited_sector)

func _on_player_entered_sector(body: Node3D) -> void:
	if body.name == "Player" or body.is_in_group("PlayerGroup"):
		var pivot_node = get_tree().get_first_node_in_group("CameraPivotGroup")
		if is_instance_valid(pivot_node) and pivot_node.has_method("set_target_sector_rotation"):
			print("CAMERA SECTOR: Transitioning angle to: ", sector_angle_override)
			pivot_node.set_target_sector_rotation(sector_angle_override)

func _on_player_exited_sector(body: Node3D) -> void:
	if body.name == "Player" or body.is_in_group("PlayerGroup"):
		var pivot_node = get_tree().get_first_node_in_group("CameraPivotGroup")
		if is_instance_valid(pivot_node) and pivot_node.has_method("set_target_sector_rotation"):
			print("CAMERA SECTOR: Reverting back to baseline tracking angle.")
			pivot_node.set_target_sector_rotation(0.0)
