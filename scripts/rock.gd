extends StaticBody2D
class_name Rock

signal rock_destroyed

@export var shake_strength: float = 8.0
@export var shake_duration: float = 0.4
@export var shake_count: int = 8

var original_position: Vector2
var current_tween: Tween

# игрок в среднем один камень должен ломать около 2х секунд
const type_rock = ["default", "strong", "big", "alive"]
const rock_hp = [25, 30, 37, 45]
const rock_size = [2.0, 2.25, 2.5, 2.75]
const rock_reward = [1.0, 1.5, 3.0, 5.0]

var forced_type: int = -1
var type
@onready var damage_particle = $DamageRock


@export var max_health: float = 10
var health: float

func _ready() -> void:
	
	original_position = position
	
	if Main.current_level >= 3:
		type = forced_type if forced_type != -1 else randi_range(0, 3)
	elif Main.current_level < 3:
		type = forced_type if forced_type != -1 else randi_range(0, 2)

	# Множитель HP от уровня. ВАЖНО: current_level - int, поэтому
	# "current_level / 10" без .0 - это ЦЕЛОЧИСЛЕННОЕ деление и для
	# уровней 1-9 даёт 0 (0 * 1.05 = 0, камни были бы "бессмертно слабыми"
	# на первых уровнях). Пишем "10.0", чтобы деление было дробным.
	# "+1.0" - база, чтобы множитель никогда не опускался ниже 1.0,
	# то есть камни не становятся слабее своих базовых значений rock_hp
	# даже на 1-м уровне, а только усиливаются по ходу игры.
	var hp_multiplier: float = 1.0 + Main.current_level / 10.0 * 1.05
	max_health = (rock_hp[type]+Main.damage*2) * hp_multiplier
	#print(max_health)
	scale = Vector2(rock_size[type], rock_size[type])
	
	#print("type: " + str(type) + "\nscale: " + str(scale))
	
	health = max_health

func _process(delta: float) -> void:
	#$HealthLabel.text = str(health) + "/" + str(max_health)
	$HealthBar.max_value = max_health
	$HealthBar.value = health

func damage_text(amount: float, is_crit: bool = false):
	var container := HBoxContainer.new()
	container.z_index = 100
	container.add_theme_constant_override("separation", 4)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if is_crit:
		var icon := TextureRect.new()
		icon.texture = preload("res://sprites/rock.png")
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(28, 28)
		container.add_child(icon)
	
	
	var label := Label.new()
	label.text = str(snappedf(amount, 0.1))
	label.z_index = 100
	
	label.add_theme_font_size_override("font_size", 24 if not is_crit else 32)
	label.add_theme_color_override("font_color", Color.RED if is_crit else Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_override("font",preload("res://fonts/montserrat.bold.ttf"))
	container.add_child(label)
		
	get_tree().current_scene.add_child(container)
	container.global_position = global_position + Vector2(randf_range(-15, 15), -20)
	
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(container, "global_position:y", label.global_position.y - 40, 0.8)
	tween.tween_property(container, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tween.chain().tween_callback(container.queue_free)
	

func take_damage(amount: float) -> void:
	
	print(health)
	if randf_range(0.00, 1.00) <= Main.chance_crit:
		var crit_damage = amount*Main.crit_multiplier
		health -= crit_damage
		health = max(health, 0)
		print("CRIT")
		damage_text(crit_damage, true)
		#тут партикл критов
		$CritRock.restart()
		$CritRock.emitting = true
		$CritRockSparkles.restart()
		$CritRockSparkles.emitting = true
	else:
		health -= amount
		health = max(health, 0)
		damage_particle.restart()
		damage_particle.emitting = true
		damage_text(amount, false)
	print("damage: " + str(amount))
	shake()
	

	#print("Rock health: ", health, " / ", max_health)

	if health <= 0:
		
		var particles = $BreakRock
		
		remove_child(particles)
		get_parent().add_child(particles)
		
		particles.global_position = global_position
		particles.emitting = true
		
		var timer = get_tree().create_timer(particles.lifetime)
		timer.timeout.connect(particles.queue_free)
		
		rock_destroyed.emit()
		queue_free()

		# Раньше бонус считался от Main.money (сколько денег УЖЕ есть у
		# игрока) - чем больше денег накоплено, тем больше бонус, и это
		# давало экспоненциальный "снежный ком": доход рос сам от себя,
		# а не от прогресса в игре, и баланс цен на апгрейды посчитать
		# было невозможно.
		#
		# Проблема, которую это решало, была реальной: без такого бонуса
		# под конец прохождения игроку не хватало денег на апгрейды.
		# Вместо роста от текущего капитала бонус теперь растёт линейно
		# от НОМЕРА УРОВНЯ - тем самым доход предсказуемо увеличивается
		# по ходу прохождения, но не зависит от того, сколько игрок уже
		# успел накопить/потратить.
		var level_bonus_multiplier: float = 1.0 + (Main.current_level - 1) * 0.15
		var base_reward: float = rock_reward[type]*Main.money_multiplier
		var additional_money: float = base_reward * randf_range(0.0, 0.5) * level_bonus_multiplier
		var total_reward: float = base_reward + additional_money

		Main.getted_money += snappedf(total_reward, 0.1)
		Main.money += total_reward
		Main.left_rocks -= 1
		Main.destroyed_rocks += 1

func shake():
	
	if current_tween and current_tween.is_valid():
		current_tween.kill()
		position = original_position
	
	current_tween = create_tween()
	var step_time = shake_duration / shake_count
	
	for i in shake_count:
		var strength = shake_strength * (1.0 - float(i) / shake_count)
		var offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		current_tween.tween_property(self, "position", original_position + offset, step_time) \
			.set_trans(Tween.TRANS_SINE)
	current_tween.tween_property(self, "position", original_position, step_time)
