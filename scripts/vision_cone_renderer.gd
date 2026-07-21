extends MeshInstance3D
class_name VisionConeRenderer

@export var vision_sensor: VisionSensor3D
@export var ray_density: int = 16
@export var frame_update_stride: int = 3 # Time-sliced framework: Updates geometry every 3 frames!

var active_frame_counter: int = 0
var cone_material: StandardMaterial3D = null

func _ready() -> void:
	mesh = ImmediateMesh.new()
	if material_override:
		cone_material = material_override.duplicate() as StandardMaterial3D
		material_override = cone_material

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(vision_sensor): return
	
	# TIME-SLICED PERFORMANCE INTERCEPT: Drastically limits ray query spam!
	active_frame_counter += 1
	if active_frame_counter % frame_update_stride != 0:
		return
		
	var parent_guard = get_parent()
	if "current_phase" in parent_guard and parent_guard.current_phase == parent_guard.PatrolPhase.STUNNED:
		if mesh: (mesh as ImmediateMesh).clear_surfaces()
		return

	_reconstruct_vision_mesh()

func _reconstruct_vision_mesh() -> void:
	var immediate_mesh = mesh as ImmediateMesh
	if not immediate_mesh: return
	immediate_mesh.clear_surfaces()
	
	var space_state = get_world_3d().direct_space_state
	var eye_origin = global_position + Vector3(0.0, 0.1, 0.0)
	var perimeter_points: Array[Vector3] = []
	var angle_step = (vision_sensor.vision_angle * 2.0) / ray_density

	for i in range(ray_density + 1):
		var ray_angle = -vision_sensor.vision_angle + (i * angle_step)
		var local_dir = Vector3(sin(deg_to_rad(ray_angle)), 0.0, -cos(deg_to_rad(ray_angle)))
		var global_dir = (global_transform.basis * local_dir).normalized()
		
		var ray_query = PhysicsRayQueryParameters3D.create(eye_origin, eye_origin + (global_dir * vision_sensor.vision_range))
		ray_query.exclude = [get_parent().get_rid()]
		
		var contact = space_state.intersect_ray(ray_query)
		if not contact.is_empty():
			var local_hit = to_local(contact["position"])
			local_hit.y = 0.1
			perimeter_points.append(local_hit)
		else:
			var local_reach = to_local(eye_origin + (global_dir * vision_sensor.vision_range))
			local_reach.y = 0.1
			perimeter_points.append(local_reach)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(perimeter_points.size() - 1):
		immediate_mesh.surface_add_vertex(Vector3(0, 0.1, 0))
		immediate_mesh.surface_add_vertex(perimeter_points[i])
		immediate_mesh.surface_add_vertex(perimeter_points[i + 1])
	immediate_mesh.surface_end()

	# Dynamically sync colors relative to suspicion levels cleanly
	if is_instance_valid(cone_material):
		var suspicion = vision_sensor.current_suspicion
		if suspicion > 0.01:
			var blend = suspicion / 100.0
			cone_material.albedo_color = Color(1.0, 0.6, 0.0, 0.16).lerp(Color(1.0, 0.2, 0.2, 0.2), blend)
		else:
			cone_material.albedo_color = Color(0.1, 0.6, 1.0, 0.12)
