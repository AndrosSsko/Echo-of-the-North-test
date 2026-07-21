extends RigidBody3D

func _ready() -> void:
	# High velocity direct projectile rules
	gravity_scale = 0.0 # Bypasses gravity to slide completely flat
	contact_monitor = true
	max_contacts_reported = 1
