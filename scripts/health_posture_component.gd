extends Node
class_name HealthPostureComponent

signal posture_shattered()
signal posture_recovered()
signal posture_damaged(current: int, maximum: int)

@export var min_posture_pool: int = 2
@export var max_posture_pool: int = 5
@export var recover_cooldown: float = 4.0

var max_posture: int = 3
var current_posture: int = 3
var is_broken: bool = false
var recovery_timer: float = 0.0

func _ready() -> void:
	# VISCERAL RANDOMIZATION MATRIX: Every human takes varying numbers of hits!
	randomize()
	max_posture = randi_range(min_posture_pool, max_posture_pool)
	current_posture = max_posture
	is_broken = false

func _process(delta: float) -> void:
	if is_broken:
		recovery_timer -= delta
		if recovery_timer <= 0.0:
			recover_balance()

func take_posture_damage(amount: int) -> void:
	if is_broken: return
	
	current_posture = clampi(current_posture - amount, 0, max_posture)
	posture_damaged.emit(current_posture, max_posture)
	
	print("🩸 POSTURE DAMAGE: Guard took ", amount, " balance hit(s). Remaining: ", current_posture, "/", max_posture)
	
	if current_posture <= 0:
		shatter_balance()

func shatter_balance() -> void:
	is_broken = true
	recovery_timer = recover_cooldown
	posture_shattered.emit()

func recover_balance() -> void:
	is_broken = false
	current_posture = max_posture
	posture_recovered.emit()
