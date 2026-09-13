extends Node

# Раньше уровни лежали в отдельных сценах (res://levels/levelN.tscn) и
# load_level() переключал сцену через change_scene_to_file(). Теперь игра
# целиком живёт в одной сцене: "смена уровня" - это не смена сцены, а
# просьба к текущему level.gd пересобрать себя с новыми параметрами.
# level_controller - это и есть ссылка на активный level.gd, он
# регистрирует себя сам в своём _ready().
var level_controller: Node = null

# Единая точка оповещения "начался новый уровень" для всех остальных
# постоянных нод (игрок, HUD, карточки апгрейдов). Раньше они просто
# пересоздавались вместе со сценой уровня и сами подтягивали актуальные
# Main.max_health/Main.damage/и т.д. в своих _ready(). Теперь сцена одна,
# эти ноды живут всё время игры, и без такого сигнала они бы навсегда
# застряли на значениях, которые были на момент самого первого запуска.
#
# Сигнал висит именно на Main (autoload), а не на level.gd, потому что
# автозагрузки Godot гарантированно готовы ДО _ready() любой ноды на
# сцене - значит, подписка на Main.level_changed в _ready() игрока/HUD/
# карточки сработает всегда, независимо от порядка их создания в дереве.
signal level_changed(level_num: int)

var current_level = 1

# --- Базовые значения статов и их накопленные множители.
#
# Раньше "УРОН" и "ЗДОРОВЬЕ" прибавлялись прямым умножением (damage =
# damage*(1+value/100)) без всякого убывающей полезности, в отличие от
# chance_crit/crit_multiplier/money_multiplier. На дистанции игры это
# делало их СТРОГО сильнее остальных баффов той же редкости: компаунд без
# потолка всегда обгоняет компаунд с убыванием. Теперь оба стата работают
# по той же схеме "база * накопленный множитель" с той же формулой
# apply_diminishing_multiplier(), что и money_multiplier/crit_multiplier.
#
# base_damage/base_max_health - точка отсчёта (соответствует множителю
# 1.0), damage/max_health - то, что по-прежнему читает весь остальной
# код (rock.gd, player.gd) - их семантика для потребителей не изменилась,
# менять нужно было только то, ЧТО их увеличивает (см. upgrade_card.gd).
var base_damage = 00.0
var damage = 10.0
var damage_mult = 1.0

var base_max_health = 30.0
var max_health = 30.0
var health_mult = 1.0

var chance_crit = 0.025
var crit_multiplier = 1.25

# Раньше move_speed была объявлена, но нигде не использовалась - у
# player.gd была своя независимая @export move_speed, и баффа скорости
# передвижения не существовало вовсе. move_speed_mult - реальный
# накопленный бонус к скорости; player.gd умножает на него свою базовую
# скорость в _sync_stats().
var move_speed_mult = 1.0

var money_multiplier = 1.0
var money = 0.0

# --- Новые статы для новых баффов (см. upgrade_card.gd). Та же логика
# убывающей полезности, что и у остальных процентных баффов выше:
# lifesteal/dodge_chance - "честный потолок" (это вероятности/доли),
# attack_speed_mult/regen_mult - множители без потолка через
# apply_diminishing_multiplier(), как money_multiplier/crit_multiplier.
var attack_speed_mult = 1.0   # делит damage_cooldown игрока - чем выше, тем чаще бьём
var lifesteal = 0.0           # доля нанесённого урона, возвращаемая игроку здоровьем
var dodge_chance = 0.0        # шанс полностью избежать входящего урона
var regen_mult = 1.0          # множитель силы пассивной регенерации (см. HealTimer в player.gd)

# --- Убывающая полезность для процентных баффов (шанс крита, урон
# крита, доход). Раньше каждый бафф прибавлял/умножал на фиксированный
# номинальный %, из-за чего поздние покупки были так же сильны, как
# первые, а сами значения после многих сложений/умножений float
# расползались в "мусорные" хвосты вроде 1.158289417941.
#
# CRIT_CHANCE_CAP - шанс крита не может расти бесконечно (это
# вероятность), поэтому у него честный потолок, и прирост тем меньше,
# чем ближе текущий шанс к этому потолку (асимптота).
#
# *_DIMINISH_K - для множителей без потолка (money_multiplier,
# crit_multiplier) используем другую идею: чем больше бонус уже
# накоплен сверх базового значения (1.0), тем слабее по факту
# срабатывает очередной такой же номинальный %. K регулирует, насколько
# быстро наступает "убывание" - чем больше K, тем быстрее.
#
# STAT_ROUND_STEP - шаг округления результата. Не влияет на сам смысл
# формулы, а просто не даёт float-погрешностям накапливаться в дробях
# на 12+ знаков после запятой.
const CRIT_CHANCE_CAP: float = 0.75
const CRIT_DAMAGE_DIMINISH_K: float = 1.0
const MONEY_MULT_DIMINISH_K: float = 1.0

# Новые K/CAP для баффов, введённых вместе со скиллами (см. комментарий
# у damage_mult/health_mult выше и у apply_diminishing_* ниже).
const DAMAGE_DIMINISH_K: float = 1.0
const HEALTH_DIMINISH_K: float = 1.0
const ATTACK_SPEED_DIMINISH_K: float = 1.0
const REGEN_DIMINISH_K: float = 1.0
const MOVE_SPEED_DIMINISH_K: float = 1.0
const LIFESTEAL_CAP: float = 0.20     # честный потолок: макс. 20% урона возвращается здоровьем
const DODGE_CHANCE_CAP: float = 0.40  # честный потолок: макс. 40% шанс полностью избежать урона

const STAT_ROUND_STEP: float = 0.0001

# Применяется к величинам с честным потолком (сейчас - только chance_crit).
# raw_fraction - номинальный прирост в долях (например, 0.10 для +10%).
# Чем ближе current к cap, тем меньше реальный прирост - на самом cap
# прирост равен нулю, значение никогда его не превышает.
func apply_diminishing_bonus_capped(current: float, cap: float, raw_fraction: float) -> float:
	var new_value = current + raw_fraction * (cap - current)
	new_value = clamp(new_value, 0.0, cap)
	return snappedf(new_value, STAT_ROUND_STEP)

# Применяется к множителям без потолка вида "1.0 + бонус" (money_multiplier,
# crit_multiplier). Реальный прирост делится на (1 + уже_накопленный_бонус * k),
# так что один и тот же номинальный % даёт всё меньше пользы по мере роста
# характеристики - первая покупка почти не отличается от старой формулы,
# а десятая уже ощутимо слабее.
func apply_diminishing_multiplier(current: float, raw_fraction: float, k: float) -> float:
	var current_bonus = current - 1.0
	var increment = raw_fraction / (1.0 + current_bonus * k)
	var new_bonus = current_bonus + increment
	return snappedf(1.0 + new_bonus, STAT_ROUND_STEP)


# --- Скиллы: уникальные пассивки, в отличие от баффов выше их нельзя
# купить больше одного раза за игру (список и описания эффектов - в
# upgrade_card.gd, здесь только сам факт "куплен/не куплен", потому что
# это общее игровое состояние: его должны видеть и player.gd (second_wind,
# thorns), и rock.gd (explosive_kill, money_magnet), и upgrade_card.gd
# (чтобы не предлагать уже купленный скилл повторно).
var unlocked_skills: Dictionary = {}
var second_wind_used: bool = false

func has_skill(skill_id: String) -> bool:
	return unlocked_skills.has(skill_id)

func unlock_skill(skill_id: String) -> void:
	unlocked_skills[skill_id] = true


# --- Параметры "ощущения" уровня, которые задаёт level.gd в start_level()
# ПЕРЕД generate_rocks(). Раньше единственным способом менять сложность
# уровня было количество камней (rock_count) - отсюда и ощущение
# "+1 камень каждый уровень". Теперь level.gd может для каждого уровня
# задать СОСТАВ камней (кто чаще выпадает) и их "жирность", не трогая
# количество - боссовый уровень с 1-3 камнями и уровень-"рой" из 20+
# слабых камней используют ровно один и тот же механизм.
#
# current_type_weights - веса для randi_range-замены: индексы
# соответствуют type_rock в rock.gd (["default","strong","big",
# "alive_chaser","alive_thrower","alive_tank"]).
# Вес 0 значит "тип не выпадает вообще", не обязательно все 6 весов ненулевые.
# Значение по умолчанию ниже фактически не используется - level.gd
# перезаписывает current_type_weights в start_level() ДО первого спавна
# камней на каждом уровне (см. LEVELS/generate_procedural_level в level.gd).
var current_type_weights: Array = [1, 1, 1, 0, 0, 0]

# Множитель поверх ОБЫЧНОЙ формулы прироста HP от уровня (см. rock.gd).
# 1.0 - без изменений. Боссовые/элитные уровни задают тут значение выше
# 1.0, чтобы конкретно этот уровень ощущался как "стена", даже если по
# номеру уровня обычные камни ещё не должны были так закалиться.
var level_hp_multiplier_extra: float = 1.0

# Множитель поверх денежной награды за разрушенный камень (см. rock.gd::
# take_damage()). 1.0 - без изменений. Боссовые уровни (см. level.gd::
# is_boss_level()/_apply_boss_overrides()) поднимают это значение, чтобы
# повышенный риск боя с боссом компенсировался ощутимо большей добычей,
# а не только "жирным" HP.
var level_money_multiplier_extra: float = 1.0

# Взвешенный выбор индекса типа камня. Если все веса нулевые (на всякий
# случай, чтобы не сломать генерацию), откатываемся к равномерному выбору.
func weighted_random_index(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += w

	if total <= 0.0:
		return randi_range(0, weights.size() - 1)

	var r: float = randf_range(0.0, total)
	var cumulative: float = 0.0
	for i in weights.size():
		cumulative += weights[i]
		if r <= cumulative:
			return i

	return weights.size() - 1

var need_rocks = 15
var left_rocks = 15
var destroyed_rocks = 0
var getted_money = 0

var game_active = true

var debugstats_label := Label.new()

# variables for generate rocks
const rock_scene: PackedScene = preload("res://objects/rock.tscn")

var rocks_positions: Array[Vector2] = []
var max_attempts: int = 30

var rock_size_px: float = 32.0
var rock_scale: float = 2.375
var rock_radius: float = (rock_size_px * rock_scale) / 2.0
var min_distance: float = rock_radius * 2.0

# Список заспавненных камней текущего уровня. Раньше он был не нужен,
# потому что смена/перезапуск уровня перезагружала сцену и Godot сам
# уничтожал все ноды. Теперь сцена одна и живёт постоянно, поэтому перед
# генерацией нового набора камней старые нужно удалять руками -
# см. clear_rocks().
var spawned_rocks: Array[Node] = []

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart_level()

# level_num здесь - не путь к файлу, а просто номер уровня "сюжета".
# Реального перехода между сценами больше нет: мы обновляем current_level
# и просим level_controller (level.gd на сцене) пересобрать уровень на
# месте - обнулить прогресс и заспавнить новый набор камней под новую
# сложность.
func load_level(level_num: int) -> void:
	if level_controller == null:
		print("Ошибка: level_controller не назначен - level.gd не зарегистрировался в Main")
		return

	current_level = level_num
	# Новый уровень должен стартовать "активным" - иначе HUD увидит
	# game_active == false (оставшееся от прошлого уровня) и сразу
	# покажет экран завершения уровня, а игрок будет заморожен
	# (player.gd двигается только пока Main.game_active == true).
	game_active = true

	level_controller.start_level(current_level)
	level_changed.emit(current_level)

func load_next_level() -> void:
	load_level(current_level + 1)

func restart_level() -> void:
	# Раньше рестарт делал reload_current_scene(), сейчас сцена не
	# перезагружается - вместо этого просто пересобираем текущий уровень
	# с тем же номером (game_active выставляется внутри load_level()).
	load_level(current_level)

# Удаляет все камни прошлого уровня перед генерацией новых. Обязательно
# вызывать перед generate_rocks(), иначе камни будут копиться со сцены на
# сцену (когда сцена больше не перезагружается сама).
#
# ВАЖНО: queue_free() удаляет ноду только в КОНЦЕ текущего кадра, а не
# сразу. Если после clear_rocks() в этом же кадре тут же вызвать
# generate_rocks(), новые камни на мгновение окажутся в сцене
# ОДНОВРЕМЕННО со старыми (те технически ещё не удалены и всё ещё
# участвуют в физике) - в тесной SpawnZone это даёт наложение коллайдеров
# друг на друга, и когда игрок в этот момент задевает сразу два
# перекрывшихся камня, move_and_slide() выталкивает его гораздо резче,
# чем при обычном столкновении с одним камнем (ощущается как "слишком
# резкий" отскок). Поэтому убираем камень из дерева НЕМЕДЛЕННО через
# remove_child() (это сразу выключает его физику), а queue_free() только
# освобождает память чуть позже.
func clear_rocks() -> void:
	for rock in spawned_rocks:
		if is_instance_valid(rock):
			var rock_parent := rock.get_parent()
			if rock_parent:
				rock_parent.remove_child(rock)
			rock.queue_free()
	spawned_rocks.clear()
	rocks_positions.clear()

func generate_rocks(count: int, parent: Node2D, zone: ReferenceRect) -> void:

	# Список позиций - переменная автозагрузки Main, она переживает
	# смену/перезапуск уровня. Если не чистить её перед новой генерацией,
	# камни прошлого уровня будут "мешать" новым и генерация со временем
	# сломается. Очищаем перед каждым вызовом (также чистится в
	# clear_rocks(), но оставляем и здесь на случай прямого вызова).
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
		spawned_rocks.append(rock)
