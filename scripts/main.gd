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
const rock_scene: PackedScene = preload("res://objects/rock.tscn")

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

func is_on_wall(wall_tilemap: TileMapLayer, pos: Vector2) -> bool:
	var cell = wall_tilemap.local_to_map(wall_tilemap.to_local(pos))
	var source_id = wall_tilemap.get_cell_source_id(cell)
	return source_id != -1


func generate_rocks(count: int, spawn_points: Array, parent: Node) -> void:
	rocks_positions.clear()

	if spawn_points.is_empty():
		push_warning("Нет точек спавна для камней")
		return

	var available_points = spawn_points.duplicate()
	available_points.shuffle()

	var spawn_count = min(count, available_points.size())

	for i in spawn_count:
		var point_pos = available_points[i]

		var rock = rock_scene.instantiate()
		rock.z_index = 1
		rock.position = point_pos
		rock.add_to_group("rock")
		rocks_positions.append(point_pos)
		parent.add_child(rock)

	print("Заспавнено камней: ", spawn_count, " / ", count, " (доступно точек: ", available_points.size(), ")")
