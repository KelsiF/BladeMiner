extends Node

@export var rock_scene: PackedScene
var rock_count: int = 15
var rocks_positions: Array[Vector2] = []
var max_attempts: int = 30

var rock_size_px: float = 32.0
var rock_scale: float = 2.375
var rock_radius: float = (rock_size_px * rock_scale) / 2.0
var min_distance: float = rock_radius * 2.0

func _ready() -> void:
	
	# (5+level)*1.25 даёт дробное число - раньше оно молча/небезопасно
	# присваивалось typed int-переменной (rock_count: int), из-за чего
	# либо терялась дробная часть непредсказуемым образом, либо GDScript
	# ругался на сужающее преобразование float -> int. Явно округляем.
	rock_count = int(round((5+Main.current_level)*1.25))
	
	
	Main.destroyed_rocks = 0
	Main.getted_money = 0
	Main.left_rocks = rock_count
	Main.need_rocks = rock_count
	# Main.current_level здесь раньше жёстко выставлялся в 1 - это
	# затирало правильный номер уровня, который уже успел выставить
	# Main.load_level()/load_next_level() ДО загрузки этой сцены.
	# Из-за этого HUD всегда показывал "1 Уровень", а следующий вызов
	# rock_count = (5 + Main.current_level) * 1.25 на новом уровне
	# считался так, будто мы всё ещё на первом уровне.
	
	Main.generate_rocks(rock_count, get_tree().current_scene, $SpawnZone)

func _process(delta: float) -> void:
	finish_level()

func finish_level():
	var destroyed_rocks = Main.destroyed_rocks
	
	if destroyed_rocks >= rock_count:
		Main.game_active = false
