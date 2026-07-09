extends Area3D

@export_category("Stealth Camouflage Settings")
@export var stealth_alpha_transparency: float = 0.35

func _ready() -> void:
	# Connect our native physical boundary signal traps
	body_entered.connect(_on_player_entered_foliage)
	body_exited.connect(_on_player_exited_foliage)

func _on_player_entered_foliage(body: Node) -> void:
	# DUCK TYPING PROTECTION LAYER: Ensure the overlapping node is actually Eira
	if body.is_in_group("PlayerGroup") or body.name == "Player":
		print("STEALTH ENGINE: Eira entered tall grass. Masking visibility profiles.")
		
		# Turn her global visibility tracker off instantly so guard line-of-sight casts fail!
		if "is_player_currently_visible" in body:
			body.is_player_currently_visible = false
			
		# Visual feedback loop: smoothly fade her capsule semi-translucent
		var player_mesh = body.get_node_or_null("MeshInstance3D")
		if is_instance_valid(player_mesh):
			var material_clone = player_mesh.get_active_material(0)
			if is_instance_valid(material_clone):
				var tween = create_tween()
				tween.tween_property(material_clone, "albedo_color:a", stealth_alpha_transparency, 0.2)

func _on_player_exited_foliage(body: Node) -> void:
	if body.is_in_group("PlayerGroup") or body.name == "Player":
		print("STEALTH ENGINE: Eira broke foliage cover. Sights restored.")
		
		if "is_player_currently_visible" in body:
			body.is_player_currently_visible = true
			
		# Smoothly snap her capsule back to full solid opacity
		var player_mesh = body.get_node_or_null("MeshInstance3D")
		if is_instance_valid(player_mesh):
			var material_clone = player_mesh.get_active_material(0)
			if is_instance_valid(material_clone):
				var tween = create_tween()
				tween.tween_property(material_clone, "albedo_color:a", 1.0, 0.15)
