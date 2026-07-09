extends Area3D

@onready var gate_mesh: MeshInstance3D = $MeshInstance3D
@onready var gate_collision: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	body_entered.connect(_on_door_approached)

func _on_door_approached(body: Node) -> void:
	if body.name == "Player":
		# Check if Eira has a key carried inside her player.gd bag tracker
		if "carried_treasure_keys_count" in body and body.carried_treasure_keys_count > 0:
			print("GATE SYSTEM: Valid key detected! Unlocking door path.")
			body.carried_treasure_keys_count -= 1 # Spend the key resource
			
			# Comedic swing or fade out: Melt the door block out of existence!
			var door_tween = create_tween().set_parallel(true)
			door_tween.tween_property(self, "position:y", -3.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			door_tween.tween_property(gate_mesh, "modulate:a", 0.0, 0.4)
			
			# Permanently disable the collision server block lines so she can walk past
			gate_collision.set_deferred("disabled", true)
		else:
			print("GATE SYSTEM: Path locked! You must explore the guard alcoves to find a key first.")
