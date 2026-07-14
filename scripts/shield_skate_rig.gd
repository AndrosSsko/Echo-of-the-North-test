extends Node3D

@export var backpack_marker: Marker3D
@export var surfing_marker: Marker3D

var active_tween: Tween

func transition_to_surf():
	if active_tween: active_tween.kill()
	
	active_tween = create_tween().set_parallel(true)
	# Smoothly move to the surfing marker's transform
	active_tween.tween_property(self, "global_transform", surfing_marker.global_transform, 0.2).set_trans(Tween.TRANS_CUBIC)

func transition_to_backpack():
	if active_tween: active_tween.kill()
	
	active_tween = create_tween().set_parallel(true)
	# 1. Pop up first (using a small offset relative to the current position)
	active_tween.tween_property(self, "global_position", global_position + Vector3(0, 1.0, 0), 0.1)
	
	# 2. Chain to the backpack marker
	active_tween.chain().tween_property(self, "global_transform", backpack_marker.global_transform, 0.2).set_trans(Tween.TRANS_BACK)
