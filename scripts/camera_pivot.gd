extends Node3D

@export var tracking_speed: float = 5.0
@export var rotation_speed: float = 3.0

var target_sector_y_rotation: float = 0.0
var player_ref: CharacterBody3D = null
var target_orbit_yaw: float = 0.0 # Standard flat baseline angle

func _ready() -> void:
	# Locate Eira safely inside her global group registry
	player_ref = get_tree().get_first_node_in_group("PlayerGroup") as CharacterBody3D
	# Force the pivot to start unpaused so it processes even during campfire freezes
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(delta: float) -> void:
	# Smoothly interpolate her custom sector angle offset on the Y-axis matrix!
	rotation.y = lerp_angle(rotation.y, target_sector_y_rotation, 4.0 * delta)
	
	if not is_instance_valid(player_ref): return
	
	# 1. POSITION TRACKING: Smoothly glide the pivot to match Eira's exact spatial coordinates
	global_position = global_position.lerp(player_ref.global_position, tracking_speed * delta)
	
	# 2. ROTATION PIXELS ORBIT: Smoothly interpolate the yaw axis to match sector targets
	rotation.y = lerp_angle(rotation.y, target_orbit_yaw, rotation_speed * delta)

func change_sector_view_angle(angle_degrees: float) -> void:
	target_orbit_yaw = deg_to_rad(angle_degrees)
	print("CAMERA ENGINE: Adjusting viewport grid perspective to -> ", angle_degrees, " degrees.")

func set_target_sector_rotation(target_angle_deg: float) -> void:
	target_sector_y_rotation = deg_to_rad(target_angle_deg)
