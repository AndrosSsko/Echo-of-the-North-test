extends Node # Inheriting from Node makes node path attachments inside her scene tree easy!
class_name TaskBolaStruggle

const STRUGGLE_DURATION: float = 4.0

func execute_task(host: CharacterBody3D, blackboard: AIBlackboard, delta: float) -> void:
	if not is_instance_valid(blackboard) or not blackboard.get_value("is_tangled", false):
		return
		
	# Countdown the persistent time clock inside his blackboard memory records [PDF: 0.1.35]
	var timer: float = blackboard.get_value("bola_timer", STRUGGLE_DURATION) - delta
	blackboard.set_value("bola_timer", timer)
	
	# Comedic rattle wobble math driven natively in the task [PDF: 0.1.35]
	host.rotation_degrees.z = sin(Time.get_ticks_msec() * 0.04) * 25.0
	
	# Expose countdown metrics to the host label displays cleanly [PDF: 0.1.35]
	var alert_text_label = host.get("alert_label")
	if is_instance_valid(alert_text_label):
		alert_text_label.text = "STEALTH LIMIT: " + str(snapped(timer, 0.1)) + "s"
		if not alert_text_label.visible: alert_text_label.visible = true
		
	if timer <= 0.0:
		# TIMEOUT FAILURE VALVE: Player failed to finish him. Alarm sounds! [PDF: 0.1.35]
		host.rotation_degrees.z = 0.0
		blackboard.set_value("is_tangled", false)
		
		# Trigger full alert suspicion spikes instantly!
		if host.has_node("VisionSensor3D"):
			host.get_node("VisionSensor3D").current_suspicion = 100.0
			
		if is_instance_valid(alert_text_label):
			alert_text_label.text = "INTRUDER ALERT!!"
			alert_text_label.modulate = Color("#ff3333")
			
		# Return his state cleanly to matching patrol loops
		if "current_phase" in host:
			host.current_phase = host.PatrolPhase.MARCHING
			
		print("🚨 ALARM: Guard broke out of the bola ties and screamed!")
