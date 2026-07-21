extends Area3D
class_name DragonSpineSpike

@export var flight_speed: float = 14.0
var move_direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	# Connect our collision tracking registers cleanly
	body_entered.connect(_on_impact_registered)
	# Automatically clean up if it flies off into the abyss without hitting anything
	get_tree().create_timer(3.5).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	# Fly linearly forward down its custom calculated explosion angle corridor
	global_position += move_direction * flight_speed * delta

func _on_impact_registered(body: Node3D) -> void:
	if body.name == "Player" or body.is_in_group("PlayerGroup"): return
	
	if body.is_in_group("EnemyGroup") and body.has_method("execute_localized_poison_swell"):
		# Dispatch the precise local coordinate height where the spike pierced his skin mesh!
		body.execute_localized_poison_swell(global_position)
		queue_free()
