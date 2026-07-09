extends Area3D

# --- LORE INTERACTION CONFIGURATIONS ---
@export var chest_description: String = "Open Ancestral Lore Chest"

@onready var prompt_label: Label = $"/root/Main/HUD/Prompt_Container/Interaction_Prompt"
@onready var codex_window: Panel = $"/root/Main/HUD/Codex_Journal_UI"
@onready var journal_text: RichTextLabel = $"/root/Main/HUD/Codex_Journal_UI/Journal_Content"

var is_eira_near: bool = false
var has_been_opened: bool = false # EXCLUSIVE INTERACTION LOCKED GUARD FLAG

func _ready() -> void:
	body_entered.connect(_on_player_entered_chest)
	body_exited.connect(_on_player_exited_chest)

func _process(_delta: float) -> void:
	# Only allow them to dive into the menu if the chest hasn't been looted yet!
	if is_eira_near and Input.is_action_just_pressed("interact") and not get_tree().paused and not has_been_opened:
		execute_lore_reveal_pipeline()

func _on_player_entered_chest(body: Node3D) -> void:
	if body.name == "Player":
		is_eira_near = true
		update_proximity_hud_display()

func _on_player_exited_chest(body: Node3D) -> void:
	if body.name == "Player":
		is_eira_near = false
		if is_instance_valid(prompt_label):
			prompt_label.visible = false

func update_proximity_hud_display() -> void:
	if not is_instance_valid(prompt_label): return
	
	if has_been_opened:
		# If already collected, show a passive non-interactable status reminder indicator!
		prompt_label.text = "[ Ancient Chest Empty ]"
	else:
		var key_btn: String = InputManager.get_action_button_text("interact")
		prompt_label.text = key_btn + " " + chest_description
		
	prompt_label.visible = true

func execute_lore_reveal_pipeline() -> void:
	print("LORE CHEST: Eira opens the stone chest and uncovers forgotten histories.")
	if is_instance_valid(prompt_label): prompt_label.visible = false
	
	# Freeze the 3D physics server world clock loops cleanly
	get_tree().paused = true
	
	# Force this specific node wrapper to stay awake to drive the exit catch frames flawlessly
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var lore_btn: String = InputManager.get_action_button_text("interact")
	var story_entry: String = "[color=#ffd39b][b]--- CHRONICLES OF THE EMBERBORN ---[/b][/color]\n\n"
	story_entry += "Before the great rift, our ancestors did not hunt the Veilstriders. "
	story_entry += "They shared the high cliff nests, mapping wind currents together. "
	story_entry += "The old steel traps hidden inside these ruins were not built by us... "
	story_entry += "They were forged by those who came across the eastern seas.\n\n"
	story_entry += "[color=#8b8b8b]Press " + lore_btn + " to return to world navigation.[/color]"
	
	if is_instance_valid(journal_text):
		journal_text.text = story_entry
	if is_instance_valid(codex_window):
		codex_window.visible = true
		
	# Connect a fresh background listening process check to track the exit frames cleanly
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	# Catching the exact click frame cleanly without any buffered button drops!
	if get_tree().paused and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled() # Absorb frame vectors safely
		
		# Close the interface window panel completely
		if is_instance_valid(codex_window): codex_window.visible = false
		
		# Wake up the world clocks and return to regular running physics
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
		set_process_unhandled_input(false)
		
		# ENGAGE THE STATE LOCK MATRIX
		has_been_opened = true
		
		# Update her top-left mission quest text to celebrate discovery milestones!
		var objective: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
		if is_instance_valid(objective):
			objective.text = "Current Goal: [LORE UNLOCKED] Escape via High Platform Archway"
			
		# Refresh her proximity prompt container text rows instantly on exit
		if is_eira_near:
			update_proximity_hud_display()
