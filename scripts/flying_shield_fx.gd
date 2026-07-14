extends Node3D

var time_elapsed: float = 0.0
var duration: float = 0.50 # Total timeline in seconds to complete return path

var start_pos: Vector3
var target_node: Node3D
var initial_momentum: Vector3

func launch(start: Vector3, target: Node3D, player_momentum: Vector3) -> void:
	global_position = start
	start_pos = start
	target_node = target
	initial_momentum = player_momentum
	set_process(true)

func _process(delta: float) -> void:
	if target_node == null or not is_instance_valid(target_node):
		queue_free()
		return

	time_elapsed += delta
	var t: float = clampf(time_elapsed / duration, 0.0, 1.0)
	
	if t >= 1.0:
		# Locate your player's structural backpack mesh slot directly to turn visibility back on
		var real_back_mesh = target_node.get_node_or_null("BackShieldMesh")
		if real_back_mesh:
			real_back_mesh.show()
		queue_free()
		return
		
	# NEW LANDING VECTOR: Adjust target center line up to Eira's shoulder blades
	var destination: Vector3 = target_node.global_position + Vector3(0.0, 1.3, 0.0)
	
	var peak_height: float = start_pos.y + 2.8
	var control_point: Vector3 = start_pos.lerp(destination, 0.5)
	control_point.y = peak_height + initial_momentum.y
	control_point += initial_momentum * 0.30

	# Quadratic Bezier Curve Calculation Track
	var q0: Vector3 = start_pos.lerp(control_point, t)
	var q1: Vector3 = control_point.lerp(destination, t)
	global_position = q0.lerp(q1, t)
	
	rotate_object_local(Vector3.UP, 14.0 * delta)
	rotate_object_local(Vector3.FORWARD, 7.0 * delta)
