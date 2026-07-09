extends Area3D

@export_category("Reload Station Blueprint Settings")
@export var reload_time_required: float = 1.5

var player_ref: CharacterBody3D = null
var active_reload_hold_timer: float = 0.0
var is_currently_reloading: bool = false

func _ready() -> void:
	# Connect overlap tracking listeners natively [docs.godotengine.org]
	body_entered.connect(_on_player_approached)
	body_exited.connect(_on_player_left)

func _on_player_approached(body: Node) -> void:
	if body.name == "Player":
		player_ref = body
		print("WORKBENCH: Eira stepped near the invention workbench. [Hold E] to craft Bolas.")

func _on_player_left(body: Node) -> void:
	if body == player_ref:
		player_ref = null
		cancel_active_reload_session()

func _physics_process(delta: float) -> void:
	if is_instance_valid(player_ref):
		# THE UNIFIED INPUT MERGE:
		# Swapped out 'interact_lever' to target your clean, pre-existing master "interact" action!
		if Input.is_action_pressed("interact"):
			process_reload_hold_tick(delta)
		else:
			if is_currently_reloading:
				cancel_active_reload_session()

func process_reload_hold_tick(delta: float) -> void:
	if not is_currently_reloading:
		is_currently_reloading = true
		print("WORKBENCH: Crafting session started...")
		
	active_reload_hold_timer += delta
	
	# Comedic assembly line feedback bounce: make the table shake while hammering!
	position.x += sin(Time.get_ticks_msec() * 0.05) * 0.02
	
	if active_reload_hold_timer >= reload_time_required:
		execute_ammo_refill_payout()

func cancel_active_reload_session() -> void:
	is_currently_reloading = false
	active_reload_hold_timer = 0.0
	print("WORKBENCH: Crafting interrupted.")

func execute_ammo_refill_payout() -> void:
	if is_instance_valid(player_ref):
		# Call her ammo updater variables directly inside her script cache [docs.godotengine.org]
		if "current_bola_ammo" in player_ref and "max_bola_ammo" in player_ref:
			player_ref.current_bola_ammo = player_ref.max_bola_ammo
			if player_ref.has_method("update_ammo_hud_display"):
				player_ref.update_ammo_hud_display()
				
		print("WORKBENCH: Bolas fully crafted! Toolbelt reloaded.")
		
		# Comedic elastic pop stretch animation to celebrate the success!
		var pop_tween = create_tween()
		scale = Vector3(1.3, 1.3, 1.3)
		pop_tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC)
		
	cancel_active_reload_session()
