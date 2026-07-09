extends Area3D

func _ready() -> void:
	# Connect the player overlap signal natively
	body_entered.connect(_on_player_entered)

func _physics_process(delta: float) -> void:
	# Comedic cartoon animation: Rotate the key endlessly in mid-air!
	rotate_y(3.0 * delta)

func _on_player_entered(body: Node) -> void:
	if body.name == "Player" and body.has_method("add_treasure_key_to_inventory"):
		print("TREASURE SYSTEM: Key collected by Eira!")
		body.add_treasure_key_to_inventory()
		queue_free() # Erase from memory instantly
