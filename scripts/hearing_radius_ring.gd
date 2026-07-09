extends MeshInstance3D

func initialize_hearing_expansion(target_radius: float) -> void:
	# Start the ring tiny right at the point of impact coordinates
	scale = Vector3(0.01, 1.0, 0.01)
	
	# Create a duplicated material resource layout to avoid overlapping global rendering
	var runtime_mat = material_override.duplicate() as StandardMaterial3D
	material_override = runtime_mat
	
	# THE CARTOON PULSE PAYOFF: Smoothly expand the 3D ring outward until it 
	# perfectly matches your pebble's exact distraction sound radius distance!
	var expand_tween = create_tween().set_parallel(true)
	
	# Expand horizontally flat across the floor tiles over 0.5 seconds
	expand_tween.tween_property(self, "scale", Vector3(target_radius, 1.0, target_radius), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Simultaneously melt the alpha color track down into total transparency smoothly
	expand_tween.tween_property(runtime_mat, "albedo_color:a", 0.0, 0.5).set_trans(Tween.TRANS_LINEAR)
	
	# Safely clear the node from active level memory layers when the animation finishes
	expand_tween.chain().tween_callback(func(): queue_free())
