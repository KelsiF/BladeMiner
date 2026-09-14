extends StaticBody2D
class_name Rock

signal rock_destroyed

@export var shake_strength: float = 8.0
@export var shake_duration: float = 0.4
@export var shake_count: int = 8

var original_position: Vector2
var current_tween: Tween

const default_texture = preload("res://sprites/rock.png")
const alive_texture = preload("res://sprites/rock_enemy.png")

# игрок в среднем один камень должен ломать около 2х секунд
#
# Раньше "alive" был единственным враждебным типом. Теперь это ТРИ разных
# класса ожившего камня с общей "душой" (преследование/атака), но разным
# силуэтом поведения - см. ALIVE_* массивы ниже:
#   alive_chaser  - прежнее поведение "alive" один-в-один: бежит вплотную
#                   и бьёт в ближнем бою.
#   alive_thrower - держит дистанцию (kiting) и закидывает игрока камнями
#                   издалека, стараясь не подпускать его к себе вплотную.
#   alive_tank    - медленный "танк": много HP, ощутимо больнее бьёт по
#                   касанию, но почти не опасен, если просто убегать.
# Три новых типа не заменяют старый "alive", а разворачивают его в три
# отдельных индекса в type_rock/rock_hp/... - весь остальной код камня
# (спавн, HP, скейл, награда) продолжает работать точно так же, как для
# default/strong/big, просто добавились ещё три строки в таблицах.
const type_rock = ["default", "strong", "big", "alive_chaser", "alive_thrower", "alive_tank"]
const rock_hp = [25, 30, 37, 45, 40, 95]
const rock_size = [2.0, 2.25, 2.5, 2.75, 2.6, 3.3]
const rock_reward = [1.0, 1.5, 3.0, 5.0, 6.0, 9.0]

# Индексы враждебных типов внутри type_rock/rock_hp/... Вычисляются один
# раз через find(), а не захардкожены числами "3,4,5", чтобы порядок
# типов можно было менять в одном месте (type_rock), не трогая логику
# атаки ниже.
var alive_chaser_index: int = type_rock.find("alive_chaser")
var alive_thrower_index: int = type_rock.find("alive_thrower")
var alive_tank_index: int = type_rock.find("alive_tank")
var alive_type_indices: Array = [alive_chaser_index, alive_thrower_index, alive_tank_index]

# --- Параметры агрессивного поведения ожившего камня, по одному значению
# на КАЖДЫЙ тип из type_rock (индексы совпадают). У default/strong/big
# они просто не используются (стоят нулями-заглушками) - камень читает
# их только когда type входит в alive_type_indices, см. _physics_process().
#
# alive_chase_speed     - скорость движения к игроку (или от него для thrower).
# alive_detection_range - на каком расстоянии камень вообще замечает игрока.
# alive_attack_range     - для chaser/tank: дистанция ближней атаки;
#                          для thrower: максимальная дистанция броска.
# alive_keep_distance    - только у thrower: если игрок ближе этой дистанции,
#                          камень отступает вместо броска (не даёт себя
#                          зажать в ближнем бою).
# alive_attack_interval  - кулдаун между атаками.
# alive_attack_damage    - базовый урон одной атаки (до масштабирования
#                          по номеру уровня, см. _attack_player()).
# alive_projectile_speed - только у thrower: скорость летящего камня.
#
# ВАЖНО: alive_attack_range у ближников должен быть НЕ МЕНЬШЕ фактического
# радиуса соприкосновения коллайдеров камня и игрока, иначе physical-контакт
# (и отскок игрока, см. player.gd::_handle_collisions()) произойдёт раньше,
# чем distance успеет опуститься до attack_range, и дальнобойная проверка
# в _physics_process() никогда не сработает (основную атаку при касании
# всё равно подстраховывает notify_player_contact() ниже).
const alive_chase_speed      = [0.0, 0.0, 0.0, 70.0, 45.0, 38.0]
const alive_detection_range  = [0.0, 0.0, 0.0, 260.0, 320.0, 230.0]
const alive_attack_range     = [0.0, 0.0, 0.0, 60.0, 230.0, 70.0]
const alive_keep_distance    = [0.0, 0.0, 0.0, 0.0, 150.0, 0.0]
const alive_attack_interval  = [0.0, 0.0, 0.0, 1.0, 1.7, 1.3]
const alive_attack_damage    = [0.0, 0.0, 0.0, 4.0, 4.5, 8.0]
const alive_projectile_speed = [0.0, 0.0, 0.0, 0.0, 260.0, 0.0]

var forced_type: int = -1
var type
@onready var damage_particle = $DamageRock
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var player_ref: Node2D = null
var attack_cooldown: float = 0.0

# Небольшой прямолинейный "снаряд" для alive_thrower. Никакой отдельной
# .tscn-сцены не требуется - собирается целиком в коде и добавляется в
# текущую сцену тем же способом, что и всплывающий текст урона ниже
# (damage_text()). Урон наносится не через физические сигналы Area2D
# (мы не знаем, как в проекте настроены collision-слои), а простой
# проверкой дистанции до цели каждый кадр - надёжно работает при любой
# настройке коллизий.
class ThrownRock extends Node2D:
	var velocity: Vector2 = Vector2.ZERO
	var damage: float = 0.0
	var life_left: float = 2.5
	var hit_radius: float = 24.0
	var target: Node2D = null
	# Камень-источник броска - передаётся в target.take_damage(), чтобы
	# скилл ШИПЫ (player.gd) знал, кому вернуть часть урона.
	var source_rock: Rock = null

	func _ready() -> void:
		var sprite := Sprite2D.new()
		sprite.texture = Rock.alive_texture
		sprite.scale = Vector2(0.5, 0.5)
		sprite.modulate = Color(0.55, 0.75, 1.0)
		add_child(sprite)

	func _physics_process(delta: float) -> void:
		life_left -= delta
		if life_left <= 0.0:
			queue_free()
			return

		global_position += velocity * delta

		if is_instance_valid(target):
			if global_position.distance_to(target.global_position) <= hit_radius:
				if target.has_method("take_damage"):
					target.take_damage(damage, source_rock)
				queue_free()


# --- Параметры скиллов, влияющих на разрушение камня (см. take_damage()
# ниже). Сами скиллы описаны/продаются в upgrade_card.gd, здесь только
# их игровой эффект - has_skill() проверяется отдельно для каждого, т.к.
# скиллы не исключают друг друга (можно купить оба).
const EXPLOSIVE_KILL_CHANCE: float = 0.25       # шанс сдетонировать при убийстве
const EXPLOSIVE_KILL_RADIUS: float = 140.0      # радиус, в котором задевает соседние камни
const EXPLOSIVE_KILL_DAMAGE_FRACTION: float = 0.5 # урон взрыва = доля от Main.damage
const MONEY_MAGNET_FLAT_BONUS: float = 1.0      # плоский бонус монет за камень, не масштабируется money_multiplier

@export var max_health: float = 10
var health: float

func _ready() -> void:
	
	original_position = position

	# Раньше состав типов зависел жёстко от номера уровня (порог "level >= 3"
	# открывал "alive"), из-за чего единственным способом менять ощущение
	# уровня было "больше камней". Теперь level.gd перед спавном кладёт в
	# Main.current_type_weights веса по каждому типу под конкретный уровень
	# (рой почти без "alive", элита без слабых типов, босс - только "alive"
	# и т.д.), а камень просто выбирает тип по этим весам.
	type = forced_type if forced_type != -1 else Main.weighted_random_index(Main.current_type_weights)

	# Множитель HP от уровня. ВАЖНО: current_level - int, поэтому
	# "current_level / 10" без .0 - это ЦЕЛОЧИСЛЕННОЕ деление и для
	# уровней 1-9 даёт 0 (0 * 1.05 = 0, камни были бы "бессмертно слабыми"
	# на первых уровнях). Пишем "10.0", чтобы деление было дробным.
	# "+1.0" - база, чтобы множитель никогда не опускался ниже 1.0,
	# то есть камни не становятся слабее своих базовых значений rock_hp
	# даже на 1-м уровне, а только усиливаются по ходу игры.
	#
	# level_hp_multiplier_extra - дополнительный множитель СВЕРХУ этой
	# обычной формулы, который задаёт level.gd под конкретный уровень
	# (например x3-x4 для боссовых уровней с 1-3 камнями), не трогая
	# общую кривую сложности для остальных уровней.
	var hp_multiplier: float = (1.0 + Main.current_level / 10.0 * 1.05) * Main.level_hp_multiplier_extra
	max_health = (rock_hp[type]+Main.damage*2) * hp_multiplier
	#print(max_health)
	scale = Vector2(rock_size[type], rock_size[type])
	
	#print("type: " + str(type) + "\nscale: " + str(scale))
	
	health = max_health

	# Визуально отличаем "ожившие" камни от обычных (текстуры уже были
	# заготовлены выше, но раньше нигде не применялись). Отдельных
	# спрайтов под каждый новый класс пока нет, поэтому thrower/tank
	# используют ту же alive_texture с разным оттенком (modulate) -
	# дёшево и позволяет на глаз отличить класс камня ещё до того,
	# как он проявит себя поведением.
	if sprite:
		if type == alive_chaser_index:
			sprite.texture = alive_texture
			sprite.modulate = Color(1, 1, 1)
		elif type == alive_thrower_index:
			sprite.texture = alive_texture
			sprite.modulate = Color(0.55, 0.75, 1.0)
		elif type == alive_tank_index:
			sprite.texture = alive_texture
			sprite.modulate = Color(0.55, 0.55, 0.6)
		else:
			sprite.texture = default_texture

	# Только ожившие типы враждебны и должны искать игрока для
	# преследования/атаки. Игрок регистрирует себя в группе "player"
	# в своём _ready().
	if type in alive_type_indices:
		player_ref = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	#$HealthLabel.text = str(health) + "/" + str(max_health)
	$HealthBar.max_value = max_health
	$HealthBar.value = health

func _physics_process(delta: float) -> void:
	# Преследование/атака есть только у ожившых камней. Остальные типы
	# (default/strong/big) остаются статичными препятствиями, как раньше.
	if type not in alive_type_indices or not Main.game_active:
		return

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(player_ref):
			return

	var distance: float = global_position.distance_to(player_ref.global_position)
	var is_shaking: bool = current_tween and current_tween.is_valid()

	if type == alive_thrower_index:
		# --- Kiting: thrower старается держаться в "полосе" между
		# alive_keep_distance (слишком близко - убегать) и
		# alive_attack_range (слишком далеко - подойти чуть ближе).
		# Внутри полосы он не двигается и просто закидывает игрока камнями.
		if distance < alive_keep_distance[type]:
			if not is_shaking:
				var away_dir: Vector2 = player_ref.global_position.direction_to(global_position)
				position += away_dir * alive_chase_speed[type] * delta
				original_position = position
		elif distance <= alive_attack_range[type]:
			_try_attack()
		elif distance <= alive_detection_range[type]:
			if not is_shaking:
				var approach_dir: Vector2 = global_position.direction_to(player_ref.global_position)
				position += approach_dir * alive_chase_speed[type] * delta
				original_position = position
	else:
		# --- Ближний бой (chaser/tank): поведение один-в-один со старым
		# "alive" - бежать вплотную и бить по достижении attack_range.
		if distance <= alive_attack_range[type]:
			# Дальнобойная проверка - подстраховка на случай, если игрок
			# стоит на месте: move_and_slide() у игрока не всегда
			# регистрирует столкновение с неподвижным объектом, если сам
			# игрок не движется, а значит notify_player_contact() снизу
			# может не вызваться.
			_try_attack()
		elif distance <= alive_detection_range[type]:
			# Не двигаем камень, пока играет анимация "тряски" от
			# полученного урона (shake()), иначе ручное position += ...
			# будет конфликтовать с активным Tween'ом и камень будет
			# дёргаться.
			if not is_shaking:
				var direction: Vector2 = global_position.direction_to(player_ref.global_position)
				position += direction * alive_chase_speed[type] * delta
				# original_position - это "точка покоя", вокруг которой
				# играет shake(). Раз камень постоянно движется, эта точка
				# должна ехать вместе с ним, иначе после следующего урона
				# камень резко телепортирует обратно к месту своего спавна.
				original_position = position

# Вызывается игроком (player.gd::_handle_collisions()) в момент РЕАЛЬНОГО
# физического столкновения с этим камнем.
#
# Так исправлен баг: attack_range (дистанция для "дальнобойной" проверки
# выше) была меньше, чем фактический радиус соприкосновения коллайдеров
# камня и игрока - камень физически касался игрока и получал отскок
# (knockback в player.gd) ЗАДОЛГО до того, как distance успевала опуститься
# до attack_range, поэтому атака никогда не срабатывала. Теперь атака
# привязана напрямую к самому факту столкновения, а не только к дистанции,
# и не зависит от точного подбора радиусов коллайдеров. Для thrower это
# заодно и "аварийный" случай, если игрок всё же прорвался вплотную -
# _attack_player() среагирует немедленным броском в упор.
func notify_player_contact() -> void:
	if type in alive_type_indices:
		_try_attack()

func _try_attack() -> void:
	if attack_cooldown > 0.0:
		return
	_attack_player()
	attack_cooldown = alive_attack_interval[type]

func _attack_player() -> void:
	# Лёгкое масштабирование урона от номера уровня, в духе того, как hp
	# камней и денежная награда растут по ходу игры (см. rock_hp/
	# level_bonus_multiplier выше) - иначе ожившие камни быстро перестанут
	# ощущаться угрозой на поздних уровнях.
	var scaled_damage: float = alive_attack_damage[type] * (1.0 + (Main.current_level - 1) * 0.08)

	if type == alive_thrower_index:
		_throw_rock_at_player(scaled_damage)
	elif player_ref.has_method("take_damage"):
		player_ref.take_damage(scaled_damage, self)

	# Переиспользуем существующую тряску как визуальный отклик на атаку -
	# камень "дёргается" в сторону игрока в момент удара.
	shake()

# Создаёт летящий камень (класс ThrownRock, см. объявление в начале файла)
# и запускает его по прямой в сторону игрока. Собирается целиком в коде,
# отдельная .tscn-сцена не нужна - добавляется в дерево так же, как
# всплывающий текст урона в damage_text() ниже.
func _throw_rock_at_player(damage: float) -> void:
	if not is_instance_valid(player_ref):
		return

	var projectile := ThrownRock.new()
	projectile.damage = damage
	projectile.target = player_ref
	projectile.source_rock = self

	var direction: Vector2 = global_position.direction_to(player_ref.global_position)
	projectile.velocity = direction * alive_projectile_speed[type]

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position

func damage_text(amount: float, is_crit: bool = false):
	var container := HBoxContainer.new()
	container.z_index = 100
	container.add_theme_constant_override("separation", 4)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if is_crit:
		var icon := TextureRect.new()
		icon.texture = preload("res://sprites/crit_icon.png")
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(28, 28)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		# level_money_multiplier_extra - доп. множитель поверх обычной награды,
		# который level.gd выставляет для боссовых уровней (см.
		# level.gd::_apply_boss_overrides()); на обычных уровнях равен 1.0
		# и ни на что не влияет.
		var base_reward: float = rock_reward[type]*Main.money_multiplier*Main.level_money_multiplier_extra
		var additional_money: float = base_reward * randf_range(0.0, 0.5) * level_bonus_multiplier
		var total_reward: float = base_reward + additional_money

		Main.getted_money += snappedf(total_reward, 0.1)
		Main.money += total_reward
		Main.left_rocks -= 1
		Main.destroyed_rocks += 1

		# Скилл "ЖАДНОСТЬ" - плоская монета за КАЖДЫЙ разрушенный камень,
		# независимо от типа и money_multiplier (тот уже применён выше
		# к base_reward). Флэт-бонус нужен, чтобы скилл давал ощутимый
		# профит и на ранних уровнях, где money_multiplier ещё мал.
		if Main.has_skill("money_magnet"):
			Main.getted_money += MONEY_MAGNET_FLAT_BONUS
			Main.money += MONEY_MAGNET_FLAT_BONUS

		# Скилл "ЦЕПНАЯ РЕАКЦИЯ" - разрушенный камень может задеть соседей.
		# Вызываем в конце, после начисления награды за ЭТОТ камень, чтобы
		# порядок начислений был предсказуемым, даже если взрыв тут же
		# убьёт ещё один камень (и рекурсивно вызовет take_damage() у него).
		if Main.has_skill("explosive_kill") and randf() <= EXPLOSIVE_KILL_CHANCE:
			_trigger_chain_explosion()

# Наносит урон всем ещё живым камням в радиусе EXPLOSIVE_KILL_RADIUS от
# только что разрушенного камня. Использует Main.spawned_rocks (общий
# список камней текущего уровня, см. main.gd), а не сигналы/области, т.к.
# отдельного Area2D для взрыва у камня нет. Рекурсивен по своей природе:
# если взрыв убьёт ещё один камень со включённым скиллом, тот запустит
# свою собственную детонацию - и это осознанно совпадает с флейвором
# "цепной реакции", а не баг. Бесконечный цикл не грозит: список живых
# камней конечен и каждый камень удаляется из дерева сразу при своей
# смерти (queue_free() внутри take_damage()).
func _trigger_chain_explosion() -> void:
	var splash_damage: float = Main.damage * EXPLOSIVE_KILL_DAMAGE_FRACTION
	for other_rock in Main.spawned_rocks:
		if not is_instance_valid(other_rock) or other_rock == self:
			continue
		if other_rock.global_position.distance_to(global_position) <= EXPLOSIVE_KILL_RADIUS:
			if other_rock.has_method("take_damage"):
				other_rock.take_damage(splash_damage)

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
