extends BTActionNode
class_name TaskSlimeSlip

const SCRAMBLE_DURATION: float = 1.4 # on-the-spot scramble before the launch
const STUN_DURATION: float = 3.0     # flat-on-the-ground stun after the launch
const LAUNCH_SPEED: float = 12.0     # forward face-plant slide impulse

func execute_task(host: CharacterBody3D, blackboard: AIBlackboard, delta: float) -> TaskStatus:
	if not blackboard.get_value("is_slipped", false):
		return TaskStatus.FAILURE
		
	var elapsed: float = blackboard.get_value("slip_elapsed", 0.0) + delta
	blackboard.set_value("slip_elapsed", elapsed)
	
	var weapon_dropped: bool = blackboard.get_value("slip_weapon_dropped", false)
	
	if not weapon_dropped:
		return _process_scramble(host, blackboard, delta, elapsed)
	else:
		return _process_faceplant(host, blackboard, delta, elapsed)

func _process_scramble(host: CharacterBody3D, blackboard: AIBlackboard, delta: float, elapsed: float) -> TaskStatus:
	# STAGE 1: The cartoon on-the-spot scramble lock.
	host.velocity.x = 0.0
	host.velocity.z = 0.0
	host.velocity.y = -0.1
	
	if not host.is_on_floor():
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		host.velocity.y -= gravity * delta
		
	host.move_and_slide()
	
	if elapsed >= SCRAMBLE_DURATION:
		_begin_faceplant(host, blackboard)
		
	return TaskStatus.RUNNING

func _process_faceplant(host: CharacterBody3D, blackboard: AIBlackboard, delta: float, elapsed: float) -> TaskStatus:
	# STAGE 2: Forcefully pin him flat on his face so he stops drifting.
	host.velocity.y = -4.0
	host.velocity.x = move_toward(host.velocity.x, 0.0, 16.0 * delta)
	host.velocity.z = move_toward(host.velocity.z, 0.0, 16.0 * delta)
	host.move_and_slide()
	
	if elapsed >= SCRAMBLE_DURATION + STUN_DURATION:
		_recover(host, blackboard)
		return TaskStatus.SUCCESS
		
	return TaskStatus.RUNNING

func _begin_faceplant(host: CharacterBody3D, blackboard: AIBlackboard) -> void:
	blackboard.set_value("slip_weapon_dropped", true)
	
	# Forward cartoon launch impulse
	var forward: Vector3 = -host.global_transform.basis.z.normalized()
	host.velocity.x = forward.x * LAUNCH_SPEED
	host.velocity.z = forward.z * LAUNCH_SPEED
	host.velocity.y = 0.0
	
	# Tilt the visual mesh flat, if this host has one
	var mesh = host.get("visual_mesh")
	if is_instance_valid(mesh):
		mesh.rotation_degrees.x = -90.0
		
	# Duck-typed weapon disarm drop hook
	if host.has_method("execute_disarm_parry_drop"):
		host.execute_disarm_parry_drop()
		
	# Optional host-side hook for local cosmetic flourishes (camera shake, stars, text)
	if host.has_method("_on_slip_faceplant"):
		host._on_slip_faceplant()

func _recover(host: CharacterBody3D, blackboard: AIBlackboard) -> void:
	var mesh = host.get("visual_mesh")
	if is_instance_valid(mesh):
		mesh.rotation_degrees.x = 0.0
		
	blackboard.set_value("is_slipped", false)
	blackboard.set_value("slip_elapsed", 0.0)
	blackboard.set_value("slip_weapon_dropped", false)
	
	if host.has_method("_on_slip_recovered"):
		host._on_slip_recovered()
