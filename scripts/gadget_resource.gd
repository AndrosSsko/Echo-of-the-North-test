extends Resource
class_name GadgetResource

@export var display_name: String = "Unnamed Gadget"
@export var type: int = 0 # 0=Pebble, 1=Bola, 2=Slime, 3=TripWire, 4=Bomb, 5=Launcher
@export var throw_impulse: float = 18.5
@export var project_parabolic_lob_arc: bool = true
@export var projectile_scene_file: PackedScene
