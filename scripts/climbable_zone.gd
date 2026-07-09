extends Area3D

var is_player_inside: bool = false

func _ready() -> void:
	body_entered.connect(_on_player_entered)
	body_exited.connect(_on_player_exited)

func _process(_delta: float) -> void:
	if is_player_inside:
		var player = get_tree().get_first_node_in_group("PlayerGroup")
		if is_instance_valid(player) and not player.is_rolling:
			# The Player can trigger climbing by pressing Crouch while inside the zone!
			if Input.is_action_just_pressed("stealth_crouch") and not player.is_climbing:
				player.initiate_ledge_climb(global_position.x)
			elif Input.is_action_just_pressed("stealth_crouch") and player.is_climbing:
				player.exit_ledge_climb()

func _on_player_entered(body: Node3D) -> void:
	if body.name == "Player":
		is_player_inside = true
		var tracker: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
		if is_instance_valid(tracker):
			var button_text: String = InputManager.get_action_button_text("stealth_crouch")
			tracker.text = "ALT ROUTE: Press " + button_text + " to scale the hidden cliff handholds!"

func _on_player_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_player_inside = false
		var tracker: Label = get_node_or_null("/root/Main/HUD/Objective_Tracker")
		if is_instance_valid(tracker):
			tracker.text = "Current Goal: Evade the Hunter Scout & Find the Hatchery"
