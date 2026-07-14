extends Node
class_name StanceTracker

signal stance_shattered

@export var max_stability: int = 4
@onready var current_stability: int = max_stability

func reduce_stability(amount: int, push_dir: Vector3 = Vector3.ZERO) -> void:
	current_stability -= amount
	print(get_parent().name, " Stance Component: Stability dropped to ", current_stability)
	
	if current_stability <= 0:
		print(get_parent().name, " Stance Component: SHATTERED! Triggering dizziness.")
		stance_shattered.emit()
		current_stability = max_stability # Reset stability after a breakdown
		
		# Direct call down to the parent brain script to enter his dizzy wobble loop
		if get_parent().has_method("execute_cartoon_dizzy_state"):
			get_parent().execute_cartoon_dizzy_state()
	else:
		# If he absorbs the hit, play a minor flinch animation or particle puff via duck-typing
		if get_parent().has_method("play_impact_flinch_fx"):
			get_parent().play_impact_flinch_fx(push_dir)
