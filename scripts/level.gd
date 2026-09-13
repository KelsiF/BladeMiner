extends Node

# Раньше этот скрипт висел на каждой отдельной сцене уровня и запускал
# генерацию камней один раз в _ready(), а следующий уровень грузился
# заново как отдельная .tscn-сцена. Теперь сцена одна, поэтому этот же
# Node живёт всё время игры, а "уровень" - это просто число и набор
# параметров, которые пересобираются заново в start_level().

# "alive" в 12-уровневом сюжете ниже - это уже не один враг, а ТРИ класса
# ожившего камня (см. rock.gd::type_rock: alive_chaser/alive_thrower/
# alive_tank), которые вводятся постепенно и привязаны к номеру уровня,
# а не выпадают все сразу с самого начала:
#   alive_chaser - как и раньше, первый враг игры (уровень 5+);
#   alive_thrower - дальнобойный, вводится позже, когда игрок уже умеет
#                   обращаться с chaser (уровень 8+);
#   alive_tank    - медленный, но очень живучий и больно бьющий "мини-босс",
#                   появляется последним (уровень 9+) и доминирует в составе
#                   финального 12-го уровня - закрывает TODO про полноценный
#                   боссовый уровень: полноценной уникальной боевой механики
#                   у tank по-прежнему нет, но именно он теперь играет роль
#                   "стены", ради которой изначально заводился этот TODO.
signal level_started(level_num: int)
signal level_finished(level_num: int)

var rock_count: int = 15

# --- "Сюжет" - 12 уровней (укладываемся в требуемые 10-15), каждый со
# своим характером, а не просто "+1 камень к прошлому". Меняются три
# независимых рычага:
#   rock_count - сколько камней всего на уровне (не обязательно растёт -
#                см. уровень 3, он компактнее уровня 2);
#   weights    - состав типов камней, индексы как в rock.type_rock:
#                [default, strong, big, alive_chaser, alive_thrower, alive_tank];
#   hp_extra   - множитель ПОВЕРХ обычного роста HP от номера уровня
#                (см. rock.gd), которым можно сделать уровень ощутимо
#                "жирнее" или "мягче", не трогая rock_count. Этот же
#                рычаг в будущем пригодится для боссовых уровней -
#                пока используется только для лёгкой подкрутки "элиты".
const LEVELS: Array[Dictionary] = [
	# 1: обучение - только самый слабый и самый частый тип камня.
	{"rock_count": 8,  "weights": [1, 0, 0, 0, 0, 0], "hp_extra": 1.0},
	# 2: появляется "strong" - камни чуть крепче, но всё ещё простые.
	{"rock_count": 10, "weights": [3, 1, 0, 0, 0, 0], "hp_extra": 1.0},
	# 3: появляется "big" - визуально крупные камни, камней МЕНЬШЕ,
	# чем на уровне 2, но каждый ощутимо весомее.
	{"rock_count": 9,  "weights": [2, 2, 1, 0, 0, 0], "hp_extra": 1.0},
	# 4: тот же состав, но заметно больше камней - "разгон" перед тем,
	# как ввести врага-камень.
	{"rock_count": 12, "weights": [2, 2, 1, 0, 0, 0], "hp_extra": 1.0},
	# 5: первое знакомство с alive_chaser - враждебным камнем, но в
	# небольшой пропорции, чтобы не пугать сразу. Thrower/tank ещё не
	# введены - это исключительно "ближник".
	{"rock_count": 14, "weights": [3, 2, 1, 1, 0, 0], "hp_extra": 1.0},
	# 6: "засада" - камней заметно меньше, но почти все - alive_chaser.
	# Первый уровень, где враг преобладает, но всё ещё не боссовый режим.
	{"rock_count": 6,  "weights": [0, 0, 1, 2, 0, 0], "hp_extra": 1.0},
	# 7: "рой" - много слабых камней, упор на скорость и потоковый клир,
	# а не на выносливость каждого отдельного камня. Ожившие камни
	# намеренно убраны - игрок здесь тренирует клир толпы, а не бой с ними.
	{"rock_count": 20, "weights": [5, 1, 0, 0, 0, 0], "hp_extra": 1.0},
	# 8: возврат к плотному опасному миксу после разгрузочного роя и
	# знакомство с alive_thrower - на этом уровне игрок впервые должен
	# следить одновременно за ближней и дальней угрозой.
	{"rock_count": 12, "weights": [1, 3, 2, 1, 1, 0], "hp_extra": 1.0},
	# 9: "элита" - слабых камней нет вообще, каждый враг требует внимания.
	# Появляется alive_tank - первый медленный, но очень живучий враг.
	{"rock_count": 10, "weights": [0, 2, 3, 1, 2, 1], "hp_extra": 1.1},
	# 10: плотный микс со всеми тремя классами ожившых камней сразу -
	# игроку нужно одновременно уклоняться от чейзера, следить за
	# броском thrower'а и не залипать рядом с танком.
	{"rock_count": 16, "weights": [1, 2, 2, 2, 2, 1], "hp_extra": 1.1},
	# 11: большой рой перед финалом - количество ощутимо больше уровня 7,
	# но состав уже не только слабаки, а полный микс с лёгким присутствием
	# всех ожившых типов (без перегруза - это разгрузка перед финалом).
	{"rock_count": 24, "weights": [3, 3, 2, 1, 1, 1], "hp_extra": 1.0},
	# 12: финал "сюжета" - упор на alive_tank ("мини-босс" уровня, самый
	# живучий и больно бьющий тип) при поддержке chaser/thrower, заметно
	# выше обычного HP.
	{"rock_count": 14, "weights": [0, 1, 1, 2, 2, 3], "hp_extra": 1.3},
]

# Уровни за пределами "сюжета" (LEVELS.size()) генерируются процедурно:
# количество растёт по старой формуле, а доля ожившых камней в составе
# плавно увеличивается с каждым уровнем, вместо жёсткого порога по номеру
# уровня. Три класса ожившых камней разблокируются постепенно, друг за
# другом (а не все сразу с первого же эндлесс-уровня), в том же порядке,
# что и в "сюжете" выше: chaser -> thrower -> tank.
func generate_procedural_level(level_num: int) -> Dictionary:
	var extra: int = level_num - LEVELS.size()

	# (5+level)*1.25 - та же база, что была раньше единственной формулой
	# сложности игры целиком, теперь это только ветка для эндлесс-уровней
	# за пределами "сюжета".
	var count: int = int(round((5 + level_num) * 1.25))

	# chaser доступен сразу же (extra == 0, как и раньше), thrower
	# подключается через 3 эндлесс-уровня, tank - ещё через 3. У каждого
	# свой потолок веса (2), поэтому суммарная "плотность" ожившых камней
	# растёт медленнее, чем количество камней на уровне, а не взрывается
	# резко в момент разблокировки нового класса.
	var chaser_weight: int = min(1 + int(extra / 3), 2)
	var thrower_weight: int = max(0, min(1 + int((extra - 3) / 3), 2))
	var tank_weight: int = max(0, min(1 + int((extra - 6) / 3), 2))
	var weights: Array = [2, 2, 2, chaser_weight, thrower_weight, tank_weight]

	return {"rock_count": count, "weights": weights, "hp_extra": 1.0 + extra * 0.05}

# --- Боссовые уровни: каждый BOSS_LEVEL_INTERVAL-й уровень (5, 10, 15,
# 20, ...) - это не толпа камней, а маленький "отряд" из 1-4 очень
# живучих ожившых камней с сильно повышенной денежной наградой за их
# разрушение. Срабатывает НАД результатом get_level_data() - то есть
# и для "сюжетных" уровней 5/10 из LEVELS выше, и для процедурных
# эндлесс-уровней 15+, одним и тем же механизмом, без дублирования кода.
const BOSS_LEVEL_INTERVAL: int = 5

func is_boss_level(level_num: int) -> bool:
	return level_num > 0 and level_num % BOSS_LEVEL_INTERVAL == 0

# Веса типов для боссового уровня: выбираем ТОЛЬКО самый сильный из уже
# разблокированных на этот номер уровня ожившых типов camня - те же
# пороги, что и в "сюжете" выше (chaser с 5 уровня, thrower с 8, tank
# с 9). Первый босс возможен только на 5 уровне (см. is_boss_level()),
# поэтому ветка "else" ниже недостижима и оставлена лишь как подстраховка.
func _boss_type_weights(level_num: int) -> Array:
	if level_num >= 9:
		return [0, 0, 0, 0, 0, 1] # alive_tank
	elif level_num >= 8:
		return [0, 0, 0, 0, 1, 0] # alive_thrower
	elif level_num >= 5:
		return [0, 0, 0, 1, 0, 0] # alive_chaser
	return [0, 0, 1, 0, 0, 0]

# Накладывает боссовые параметры поверх обычного "рецепта" уровня (data
# уже скопирован в get_level_data() ниже, так что константы LEVELS этим
# не портятся):
#   rock_count  - маленький отряд вместо толпы: 1 на первом боссе (ур. 5),
#                 +1 камень каждые два боссовых уровня, потолок 4;
#   weights     - только сильнейший разблокированный ожившый тип;
#   hp_extra    - заметно выше обычного и растёт с номером боссового
#                 уровня, чтобы 25-й босс не ощущался так же легко, как 5-й;
#   money_extra - множитель денежной награды (Main.level_money_multiplier_extra,
#                 см. rock.gd::take_damage()), растёт вместе с hp_extra,
#                 чтобы повышенная сложность боя окупалась добычей.
func _apply_boss_overrides(data: Dictionary, level_num: int) -> Dictionary:
	var boss_index: int = level_num / BOSS_LEVEL_INTERVAL # 5->1, 10->2, 15->3, ...

	data.rock_count = min(1 + int((boss_index - 1) / 2), 4)
	data.weights = _boss_type_weights(level_num)
	data.hp_extra = 2.5 + 0.3 * (boss_index - 1)
	data.money_extra = 3.0 + 0.5 * (boss_index - 1)

	return data

# Возвращает параметры уровня level_num: из ручной таблицы LEVELS, если
# уровень входит в "сюжет", иначе - процедурно сгенерированные. Если
# level_num - боссовый (is_boss_level()), эти базовые параметры
# дополнительно переопределяются _apply_boss_overrides() выше.
func get_level_data(level_num: int) -> Dictionary:
	var data: Dictionary
	if level_num >= 1 and level_num <= LEVELS.size():
		data = LEVELS[level_num - 1].duplicate(true)
	else:
		data = generate_procedural_level(level_num)

	if is_boss_level(level_num):
		data = _apply_boss_overrides(data, level_num)

	return data

func _ready() -> void:
	# Регистрируем себя в Main, чтобы Main.load_level()/load_next_level()/
	# restart_level() могли попросить нас пересобрать уровень на месте,
	# не трогая сцену.
	Main.level_controller = self
	start_level(Main.current_level)

func _process(delta: float) -> void:
	finish_level()

# Пересобирает уровень с номером level_num прямо в текущей сцене:
# считает сложность, обнуляет прогресс, чистит старые камни и спавнит
# новые. Вызывается и при обычном переходе на следующий уровень, и при
# рестарте текущего (см. Main.load_level()/restart_level()).
func start_level(level_num: int) -> void:
	Main.current_level = level_num

	var level_data: Dictionary = get_level_data(level_num)
	rock_count = level_data.rock_count

	# level.gd задаёт "рецепт" уровня в Main ДО generate_rocks(), а сами
	# камни (rock.gd) читают эти значения в своём _ready(), чтобы выбрать
	# себе тип (weighted_random_index) и посчитать HP (level_hp_multiplier_extra).
	Main.current_type_weights = level_data.weights
	Main.level_hp_multiplier_extra = level_data.get("hp_extra", 1.0)
	Main.level_money_multiplier_extra = level_data.get("money_extra", 1.0)

	Main.destroyed_rocks = 0
	Main.getted_money = 0
	Main.left_rocks = rock_count
	Main.need_rocks = rock_count

	# Раньше эти камни удалялись сами при перезагрузке/смене сцены.
	# Теперь сцена одна и живёт постоянно, поэтому старые камни нужно
	# убрать явно перед тем, как спавнить новые под новый уровень.
	Main.clear_rocks()
	Main.generate_rocks(rock_count, get_tree().current_scene, $SpawnZone)

	level_started.emit(level_num)

func finish_level() -> void:
	if not Main.game_active:
		return

	var destroyed_rocks = Main.destroyed_rocks

	if destroyed_rocks >= rock_count:
		Main.game_active = false
		level_finished.emit(Main.current_level)
