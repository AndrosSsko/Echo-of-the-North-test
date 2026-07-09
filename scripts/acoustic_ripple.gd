extends MeshInstance3D

@export var max_sound_radius: float = 4.5 # The physical reach of your pebble noise distraction
@export var expansion_duration: float = 0.45 # Snappy, clean wave pulse speed

func _ready() -> void:
	# Start the 3D ring completely scaled down into a tiny pinprick dot mesh
	scale = Vector3.ZERO
	
	# Fetch the standard material resting inside your MeshInstance3D surface 0 slot
	var ring_material = get_active_material(0)
	if not is_instance_valid(ring_material):
		# Fallback guard if it's assigned to material_override instead
		ring_material = material_override
		
	# Execute a synchronized dual Tween loop to expand its size while fading out its opacity!
	var wave_tween: Tween = create_tween().set_parallel(true)
	
	# 1. Expand the ring flat along the X and Z ground planes over time
	wave_tween.tween_property(self, "scale", Vector3(max_sound_radius, 0.01, max_sound_radius), expansion_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. THE 3D ALPHA FIX: Instead of targeting 2D 'modulate', target the material albedo color alpha directly!
	if is_instance_valid(ring_material):
		wave_tween.tween_property(ring_material, "albedo_color:a", 0.0, expansion_duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	
	# 3. Clean up frame listeners: completely erase the asset node the exact second the tween finishes!
	wave_tween.chain().tween_callback(queue_free)
