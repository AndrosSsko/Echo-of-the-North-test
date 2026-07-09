extends Area3D

# --- HUD & WORLD ARCHITECTURE REFERENCES ---
@onready var interaction_label: Label = $"/root/Main/HUD/Prompt_Container/Interaction_Prompt"
@onready var objective_label: Label = $"/root/Main/HUD/Objective_Tracker"

var is_player_inside: bool = false
var puzzle_completed: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	# Continuous Hardware Input Loop: Process if Eira taps her interact key [E / Y]
	if is_player_inside and not puzzle_completed:
		if Input.is_action_just_pressed("interact"):
			verify_and_execute_smudge_action()

func _on_body_entered(body: Node3D) -> void:
	if body.name == "Player" and not puzzle_completed:
		is_player_inside = true
		update_prompt_text()
		interaction_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_player_inside = false
		interaction_label.visible = false

func update_prompt_text() -> void:
	# Use our global InputManager to fetch her agnostic hardware layout strings cleanly
	var interact_btn: String = InputManager.get_action_button_text("interact")
	interaction_label.text = interact_btn + " Command Smudge: Burn the Winch Rope"

func verify_and_execute_smudge_action() -> void:
	# Locate Smudge inside the active world layer tree space
	var smudge: CharacterBody3D = get_node_or_null("/root/Main/Smudge")
	
	if is_instance_valid(smudge):
		# Query the distance between Smudge and this mechanical spool mechanism
		var distance_to_smudge: float = global_position.distance_to(smudge.global_position)
		
		# AI Safety Check: Smudge must be standing close to Eira on the platform to help!
		if distance_to_smudge <= 6.0:
			puzzle_completed = true
			interaction_label.visible = false
			
			print("CHOICE MECHANICAL BRANCH: Smudge ignites the winch rope! The vertical escape path drops open.")
			
			# Dynamically update her screen goals to reward her alternative choice navigation
			if is_instance_valid(objective_label):
				objective_label.text = "Current Goal: [AGILITY PATH] Escape through the High Archway!"
				
			# --- FUTURE ARCHITECTURAL ANIMATION HOOK ---
			# This is where we will play a tween to drop a massive bridge mesh onto your platform:
			# drop_suspended_bridge_mesh()
		else:
			print("PUZZLE BLOCKED: Smudge is lagging behind or stuck on a lower floor. Wait for him!")
