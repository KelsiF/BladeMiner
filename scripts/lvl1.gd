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
	
	rock_count = (5+Main.current_level)*1.25
	
	print(rock_count)
	
	Main.destroyed_rocks = 0
	Main.getted_money = 0
	Main.left_rocks = rock_count
	Main.need_rocks = rock_count
	Main.current_level = 1
	
	var points: Array = []
	for marker in get_tree().get_nodes_in_group("rock_spawn"):
		points.append(marker.global_position)
	Main.generate_rocks(rock_count, points, self)

func _process(delta: float) -> void:
	finish_level()

func finish_level():
	var destroyed_rocks = Main.destroyed_rocks
	
	if destroyed_rocks >= rock_count:
		Main.game_active = false
		print("game_active = " + str(Main.game_active) + "\ndestroyed_rocks = " + str(Main.destroyed_rocks) + "\nrock_count = " + str(rock_count))
