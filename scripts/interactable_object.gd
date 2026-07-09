extends Area3D

# --- ENUMERATED INTERACTION PHASES ---
enum CampfireState { DIALOGUE, SELECTION, VIEWING_SCREEN }

# --- INTERACTION CONFIGURATION ---
@export_category("Interaction Settings")
@export var action_description: String = "Rest at Campfire"

# --- PRIVATE SYSTEM VARIABLES ---
@onready var interaction_label: Label = $"../HUD/Prompt_Container/Interaction_Prompt"
@onready var codex_window: Panel = $"../HUD/Codex_Journal_UI"
@onready var journal_text: RichTextLabel = $"../HUD/Codex_Journal_UI/Journal_Content"
@onready var dialogue_box: Panel = $"../HUD/Dialogue_Box_UI"
@onready var subtitle_label: RichTextLabel = $"../HUD/Dialogue_Box_UI/Subtitle_Text"

# Campfire State Tracking Matrix
var current_interaction_state: CampfireState = CampfireState.DIALOGUE
var is_player_inside: bool = false
var active_typewriter_tween: Tween = null

# 1. Narrative Dialogue Data Rows
var dialogue_lines: Array[String] = [
	"Eira: The wind is turning cold. Smudge, get closer to the hearthfire.",
	"Smudge: *Chirps softly, curling up against her heavy boots*",
	"Eira: They call us outcasts... but we're going to find the others. I promise."
]
var current_dialogue_index: int = 0

# 2. Selection Hub Menu Options Array Data
var menu_options: Array[String] = [
	"[ Read Travel Logbook Ledger ]",
	"[ Unlock Emberborn Skill Tree ]",
	"[ Forge Short Axe Weapon Upgrades ]",
	"[ Leave Campfire / Stand Up ]"
]
var selected_option_index: int = 0

var input_block_lock: bool = false # NEW: Prevents frame-bleed from restarting loops

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	InputManager.input_device_changed.connect(_on_input_device_changed)


func _process(_delta: float) -> void:
	# Standard navigation loop check: Only execute if our frame debounce lock is open!
	if is_player_inside and Input.is_action_just_pressed("interact") and not input_block_lock:
		if not get_tree().paused:
			execute_interaction_behavior()

func _on_body_entered(body: Node3D) -> void:
	if body.name == "Player":
		is_player_inside = true
		update_prompt_display()
		interaction_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_player_inside = false
		interaction_label.visible = false

func _on_input_device_changed(_is_gamepad: bool) -> void:
	if is_player_inside and not get_tree().paused:
		update_prompt_display()

func update_prompt_display() -> void:
	var btn: String = InputManager.get_action_button_text("interact")
	interaction_label.text = btn + " " + action_description

# --- CAMPFIRE HUB ENGINE ACTIONS ---

func execute_interaction_behavior() -> void:
	# THE RECOVERY HEAL & RESTOCK PIPELINE
	var player: CharacterBody3D = get_tree().get_first_node_in_group("PlayerGroup")
	if is_instance_valid(player):
		# 1. Full Heart Regeneration
		if player.current_health < player.maximum_health:
			player.current_health = player.maximum_health
			player.update_health_bar_display()
			
		# 2. NEW GADGET POUCH REFILL HOOK
		# Automatically top off her tracking bag parameters and refresh her HUD counter container!
		player.current_bola_ammo = player.max_bola_ammo
		player.update_ammo_hud_display()
		print("CAMPFIRE: Eira rests by the hearthfire. Health and Bola ammunition fully restored!")

	# 3. START DIALOGUE PHASE
	interaction_label.visible = false
	dialogue_box.visible = true
	current_interaction_state = CampfireState.DIALOGUE
	current_dialogue_index = 0
	
	run_typewriter_animation(dialogue_lines[current_dialogue_index])
	
	# Freeze the 3D world physics processing server loop safely
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_unhandled_input(true)

func run_typewriter_animation(full_text: String) -> void:
	# 1. BBCODE CHARACTER PARSER MATRIX
	# Scan the text string and inject dynamic colors directly into the speaker tags
	var formatted_text: String = full_text
	
	if full_text.begins_with("Eira:"):
		# Wrap Eira's name in a bold, rich fiery orange tint
		formatted_text = full_text.replace("Eira:", "[b][color=#ff7f24]Eira:[/color][/b]")
	elif full_text.begins_with("Smudge:"):
		# Wrap Smudge's name in a bold, soft dragon-scale green tint
		formatted_text = full_text.replace("Smudge:", "[b][color=#4ca64c]Smudge:[/color][/b]")
		
	# 2. ASSIGN CODES TO DISPLAY LABEL
	subtitle_label.text = formatted_text
	subtitle_label.visible_characters = 0
	
	# 3. INITIALIZE ANIMATION TWEEN TIMELINES
	if is_instance_valid(active_typewriter_tween):
		active_typewriter_tween.kill()
		
	active_typewriter_tween = create_tween()
	active_typewriter_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	# We use the raw text length for the typing duration so hidden BBCode tags don't slow it down!
	var animation_duration: float = full_text.length() * 0.03
	active_typewriter_tween.tween_property(subtitle_label, "visible_ratio", 1.0, animation_duration)

# --- MENU SELECTION NAVIGATION & INPUT ENGINE ---

func _unhandled_input(event: InputEvent) -> void:
	if not get_tree().paused: return
	
	# PHASE 1 & 2 INTERACT SELECTION ACTION (Mapped to E Key / Xbox Y Button)
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		
		if current_interaction_state == CampfireState.DIALOGUE:
			if is_instance_valid(active_typewriter_tween) and active_typewriter_tween.is_running():
				active_typewriter_tween.kill()
				subtitle_label.visible_ratio = 1.0
				return
				
			current_dialogue_index += 1
			if current_dialogue_index < dialogue_lines.size():
				run_typewriter_animation(dialogue_lines[current_dialogue_index])
			else:
				# Dialogue completed smoothly! Transition to selection hub menu
				current_interaction_state = CampfireState.SELECTION
				dialogue_box.visible = false
				codex_window.visible = true
				selected_option_index = 0
				update_menu_selection_text()
				
		elif current_interaction_state == CampfireState.SELECTION:
			execute_selected_option()
			
		elif current_interaction_state == CampfireState.VIEWING_SCREEN:
			# Pressing interact back out of sub-screens drops you straight back to the selection choices list
			current_interaction_state = CampfireState.SELECTION
			update_menu_selection_text()
			
	# PHASE 2 DIRECTIONAL SELECTION NAVIGATION (Listen for Up/Down input mappings)
	elif current_interaction_state == CampfireState.SELECTION:
		if event.is_action_pressed("move_up"):
			get_viewport().set_input_as_handled()
			selected_option_index = max(0, selected_option_index - 1)
			update_menu_selection_text()
		elif event.is_action_pressed("move_down"):
			get_viewport().set_input_as_handled()
			selected_option_index = min(menu_options.size() - 1, selected_option_index + 1)
			update_menu_selection_text()

func update_menu_selection_text() -> void:
	var select_btn: String = InputManager.get_action_button_text("interact")
	
	var display_text: String = "[color=#ffd39b][b]--- FIRE HEARTH CAMP HAVEN ---[/b][/color]\n"
	display_text += "Navigate via Up/Down keys. Select choice with: " + select_btn + "\n\n"
	
	for i in range(menu_options.size()):
		if i == selected_option_index:
			display_text += "[color=#ff7f24][b]> " + menu_options[i] + " <[/b][/color]\n"
		else:
			display_text += "  " + menu_options[i] + "\n"
			
	journal_text.text = display_text

func execute_selected_option() -> void:
	var back_btn: String = InputManager.get_action_button_text("interact")
	
	match selected_option_index:
		0: # Read Travel Logbook Ledger Page Screen
			current_interaction_state = CampfireState.VIEWING_SCREEN
			var page_text: String = "[color=#ffd39b][b]--- JOURNAL: ENTRY 1 ---[/b][/color]\n\n"
			page_text += "Sparing Smudge. The tribe called me stubborn. They called me a traitor. "
			page_text += "But when I looked into the eyes of that small Veilstrider hatchling, "
			page_text += "I didn't see a monster... I just saw something terrified.\n\n"
			page_text += "[color=#8b8b8b]Press " + back_btn + " to return to menu options.[/color]"
			journal_text.text = page_text
			
		1: # Unlock Skill Tree Placeholder Screen
			current_interaction_state = CampfireState.VIEWING_SCREEN
			var skill_text: String = "[color=#ffd39b][b]--- BOOKS OF THE EMBERBORN ---[/b][/color]\n\n"
			skill_text += "[X] Stave Strike (Unlocked)\n"
			skill_text += "[ ] Cinder Flight (Requires Bond Level: Kindle)\n"
			skill_text += "[ ] Silhouette wing Shift (Requires Bond Level: Flame)\n\n"
			skill_text += "[color=#8b8b8b]Press " + back_btn + " to return to menu options.[/color]"
			journal_text.text = skill_text
			
		2: # Weapon Upgrades Placeholder Screen
			current_interaction_state = CampfireState.VIEWING_SCREEN
			var forge_text: String = "[color=#ffd39b][b]--- FORGE HEARTH STATION ---[/b][/color]\n\n"
			forge_text += "Ancestral Short Axe - Level 1\n"
			forge_text += "Structural Damage: 1 | Cleave Arc Size: 2.5m\n"
			forge_text += "Materials Needed: 0/3 Ironwood Splinters\n\n"
			forge_text += "[color=#8b8b8b]Press " + back_btn + " to return to menu options.[/color]"
			journal_text.text = forge_text
			
		3: # Leave Campfire / Stand Up Reset Logic Block
			print("CAMPFIRE: Eira breaks her rest state and stands up tall.")
			codex_window.visible = false
			get_tree().paused = false
			
			process_mode = Node.PROCESS_MODE_INHERIT
			set_process(true)
			set_process_unhandled_input(false)
			
			current_interaction_state = CampfireState.DIALOGUE
			current_dialogue_index = 0
			
			# ENGAGE INPUT SAFETY LOCK: Turn on the lock to absorb the trailing click frames
			input_block_lock = true
			
			# Fire a quick, micro-second asynchronous timer thread to clear the frame buffer
			get_tree().create_timer(0.15).timeout.connect(func():
				input_block_lock = false # Safely reopen the camp trigger zone for future use
			)
			
			if is_player_inside:
				interaction_label.visible = true
