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


func generate_rocks(count: int, parent: Node2D, zone: ReferenceRect) -> void:

	# Список позиций - переменная автозагрузки Main, она переживает
	# смену/перезапуск уровня. Если не чистить её перед новой генерацией,
	# камни прошлого уровня будут "мешать" новым и генерация со временем
	# сломается. Очищаем перед каждым вызовом.
	rocks_positions.clear()

	# ReferenceRect - это Control, а Control.position - это координаты
	# внутри родителя-Control. Так как SpawnZone лежит в дереве под Node2D,
	# надёжнее брать global_position/size: это всегда реальные границы
	# зоны в мировых координатах, независимо от того, что у неё за родитель.
	var zone_global_pos: Vector2 = zone.global_position
	var zone_size: Vector2 = zone.size

	# Отступ от края зоны, чтобы камень (с учётом его радиуса) не вылезал
	# за пределы SpawnZone. rock_radius УЖЕ включает в себя rock_scale
	# (см. объявление переменной выше), поэтому здесь его больше
	# не умножаем на rock_scale повторно - раньше это раздувало отступ
	# почти в 2.4 раза и при небольшой зоне ломало randf_range.
	var margin: float = rock_radius

	# Область внутри зоны, в которой реально можно ставить центр камня.
	var usable_size: Vector2 = zone_size - Vector2(margin, margin) * 2.0

	# Подстраховка: если зона меньше, чем нужный отступ, не даём
	# usable_size уйти в минус (иначе randf_range получит min > max).
	usable_size.x = max(usable_size.x, 0.0)
	usable_size.y = max(usable_size.y, 0.0)

	for i in count:
		var rock = rock_scene.instantiate()

		var spawn_pos_global: Vector2 = Vector2.ZERO
		var valid_pos: bool = false
		var attempts: int = 0

		while not valid_pos and attempts < max_attempts:
			# Точка внутри SpawnZone: от левого-верхнего угла зоны (+margin)
			# и до правого-нижнего (-margin).
			spawn_pos_global = zone_global_pos + Vector2(margin, margin) + Vector2(
				randf_range(0.0, usable_size.x),
				randf_range(0.0, usable_size.y)
			)

			valid_pos = true
			for existing_pos in rocks_positions:
				if spawn_pos_global.distance_to(existing_pos) < min_distance:
					valid_pos = false
					break

			attempts += 1

		rocks_positions.append(spawn_pos_global)

		# rock добавляется как child именно в "parent", поэтому позицию
		# нужно задавать в локальных координатах parent, а не в мировых.
		# to_local() сам учтёт сдвиг/масштаб/поворот parent, если они есть.
		rock.position = parent.to_local(spawn_pos_global)
		rock.z_index = 1

		parent.add_child(rock)
