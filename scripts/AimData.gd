class_name AimData
extends RefCounted

var direction: Vector3 = Vector3.FORWARD
var hit_position: Vector3 = Vector3.ZERO
var hit_normal: Vector3 = Vector3.UP

var current_distance := 0.0
var max_distance := 15.0

var charge_ratio := 0.0

var did_hit := false
var is_lob := false
