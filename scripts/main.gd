extends Node

const LEVEL_PATH_TEMPLATE = "res://levels/level%d.tscn"
var current_level = 1

var damage = 10.0
var max_health = 200.0
var chance_crit = 0.025
var crit_multiplier = 1.25
var move_speed = 300.0
var money_multiplier = 1.0
var money = 0.0


var need_rocks = 15
var left_rocks = 15
var destroyed_rocks = 0
var getted_money = 0

var game_active = true

# variables for generate rocks
var rock_scene = "res://objects/rock.tscn"

var rocks_positions: Array[Vector2] = []
var max_attempts: int = 30

var rock_size_px: float = 32.0
var rock_scale: float = 2.375
var rock_radius: float = (rock_size_px * rock_scale) / 2.0
var min_distance: float = rock_radius * 2.0

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart_level()

func load_level(level_num: int):
	current_level = level_num
	var full_path = LEVEL_PATH_TEMPLATE % level_num
	
	if ResourceLoader.exists(full_path):
		get_tree().change_scene_to_file(full_path)
	else:
		print("Ошибка: Уровень ", level_num, " не найден по пути ", full_path)

func load_next_level() -> void:
	load_level(current_level + 1)
	current_level += 1

func restart_level() -> void:
	get_tree().reload_current_scene()

func generate_rocks(count: int):
	var viewport = get_viewport().get_visible_rect().size
	for i in count:
		var rock = rock_scene.instantiate()
		
		var spawn_pos = Vector2.ZERO
		var valid_pos = false
		var attempts = 0
		
		while not valid_pos and attempts < max_attempts:
			spawn_pos = Vector2(
				randf_range(rock_radius, viewport.x - rock_radius),
				randf_range(rock_radius, viewport.y - rock_radius)
			)
			
			valid_pos = true
			for existing_pos in rocks_positions:
				if spawn_pos.distance_to(existing_pos) < min_distance:
					valid_pos = false
					break
			
			attempts += 1
		
		rock.position = spawn_pos
		rocks_positions.append(spawn_pos)
		add_child(rock)
