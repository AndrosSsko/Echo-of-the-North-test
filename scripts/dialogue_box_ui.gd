extends Panel

@onready var subtitle_label: RichTextLabel = $Subtitle_Text
@onready var typewriter_audio: AudioStreamPlayer = $Typewriter_Snd_Player

var display_text_tween: Tween = null
var last_played_char_index: int = -1 # NEW: Smooth acoustic cadence index tracker

func _ready() -> void:
	visible = false

func roll_typewriter_dialogue(speaker_name: String, message_body: String, duration_per_letter: float = 0.05) -> void:
	# Clean out old tracking parameters on a fresh sentence startup frame
	last_played_char_index = -1
	subtitle_label.text = "[b][color=#ffd39b]" + speaker_name + ":[/color][/b] " + message_body
	subtitle_label.visible_characters = 0
	visible = true
	
	if display_text_tween: 
		display_text_tween.kill()
		
	display_text_tween = create_tween()
	var total_characters: int = subtitle_label.get_total_character_count()
	var full_scroll_duration: float = total_characters * duration_per_letter
	
	display_text_tween.tween_property(subtitle_label, "visible_characters", total_characters, full_scroll_duration).from(0)
	display_text_tween.parallel().tween_method(evaluate_text_scroll_audio_ticks, 0, total_characters, full_scroll_duration)

func evaluate_text_scroll_audio_ticks(current_character_index: int) -> void:
	# THE PACE BRAKE CADENCE FILTER: 
	# Only allow a click to trigger if the character count index has genuinely shifted forward.
	# We skip every alternate character index to give the ears a gentle, professional rhythmic pacing interval!
	if current_character_index != last_played_char_index and current_character_index % 2 == 0:
		last_played_char_index = current_character_index
		
		var full_string: String = subtitle_label.text
		if current_character_index < full_string.length():
			var single_letter: String = full_string[current_character_index]
			
			if single_letter != "" and single_letter != " " and single_letter != "\t" and single_letter != "\n":
				execute_generate_synthetic_type_click()

func execute_generate_synthetic_type_click() -> void:
	if not is_instance_valid(typewriter_audio): return
	
	if typewriter_audio.stream == null:
		var audio_sample: PackedByteArray = PackedByteArray()
		for i in range(500):
			var wave_v: float = sin(float(i) * 0.4) * 0.15 * (1.0 - (float(i) / 500.0))
			audio_sample.append(int(clamp((wave_v + 1.0) * 127.5, 0, 255)))
			
		var click_stream = AudioStreamWAV.new()
		click_stream.data = audio_sample
		click_stream.format = AudioStreamWAV.FORMAT_8_BITS
		click_stream.mix_rate = 11025
		typewriter_audio.stream = click_stream
		
		# === CRITICAL COZY FIX: TURN DOWN THE DESTRUCTIVE VOLUME HARMONICS ===
		# Setting volume_db to -14.0 drops the raw wave decibels down into a soft, satisfying tap!
		typewriter_audio.volume_db = -14.0

	# Rhythmic pitch randomization keeps it sounding tactile and organic
	typewriter_audio.pitch_scale = randf_range(1.1, 1.45)
	typewriter_audio.play()

func close_dialogue_window() -> void:
	visible = false
	if display_text_tween: display_text_tween.kill()
