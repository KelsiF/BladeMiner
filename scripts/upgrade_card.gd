extends PanelContainer

signal upgrade_click

@onready var card = $"."
@onready var rarity_label = $CardMargin/CardVBox/RarityLabel
@onready var name_label = $CardMargin/CardVBox/NameLabel
@onready var desc_label = $CardMargin/CardVBox/DescriptionLabel
@onready var icon = $CardMargin/CardVBox/IconCenter/Icon
@onready var price_label = $CardMargin/CardVBox/PriceLabel

var style: StyleBoxFlat = $".".get_theme_stylebox("panel").duplicate()

# Номиналы урона/здоровья снижены с 10 до 8: раньше они прибавлялись
# БЕЗ убывающей полезности, поэтому 10% выглядели сопоставимо с 5%
# крита. Теперь damage/health идут через ту же apply_diminishing_multiplier(),
# что и money_multiplier/crit_multiplier (см. main.gd) - при старом
# номинале 10% они стали бы куда сильнее остальных диминишащих баффов
# на первых нескольких покупках, а не только "не слабее" их на дистанции.
var plus_damage = 8
var plus_crit_chance = 5
var plus_crit_damage = 5
var plus_money_multiplier = 10
var plus_health = 8

# Новые баффы. Номиналы подобраны так, чтобы РЕАЛЬНЫЙ прирост (после
# убывающей полезности) первой покупки был в одной весовой категории с
# уже существующими баффами:
#   attack_speed - K=1.0, номинал заметно выше damage/crit_damage, т.к.
#                  прирост DPS от ускорения атаки ниже, чем кажется на
#                  первый взгляд (кулдаун и так может упираться в скорость
#                  сближения с камнями), поэтому баф "дешевле" по эффекту
#                  и должен быть щедрее номинально;
#   lifesteal     - честный потолок 20% (LIFESTEAL_CAP), номинал ниже
#                   crit_chance, т.к. эффективность лечения сильно зависит
#                   от урона за удар, который и так растёт от других баффов;
#   dodge_chance  - честный потолок 40%, номинал в духе crit_chance -
#                   тоже "вероятность полностью избежать события";
#   regen         - не имеет мгновенной боевой ценности (реген раз в тик
#                   HealTimer), поэтому номинал самый высокий из всех -
#                   иначе бафф не будет иметь смысла покупать;
#   move_speed    - чисто QoL-бафф (не даёт ни урона, ни выживаемости
#                   напрямую), поэтому самый дешёвый и с высоким номиналом.
var plus_attack_speed = 6
var plus_lifesteal = 4
var plus_dodge_chance = 4
var plus_regen = 15
var plus_move_speed = 6

var raritys = ["Обычный", "Редкий", "Эпический", "Легендарный"]
var raritys_colors = ["#ffffff", "#53cfbd", "#cfa3e9", "#e9aa46"]
var rarity_multiplier = [1.0, 1.25, 1.5, 2.0]

var buffs = ["damage", "crit_chance", "crit_damage", "money_multiplier", "health", "attack_speed", "lifesteal", "dodge_chance", "regen", "move_speed"]
var buffs_label = ["УРОН", "ШАНС КРИТ. УДАРА", "УРОН КРИТ. УДАРА", "БОГАТСТВО", "ЗДОРОВЬЕ", "СКОРОСТЬ АТАКИ", "ВАМПИРИЗМ", "УКЛОНЕНИЕ", "РЕГЕНЕРАЦИЯ", "СКОРОСТЬ"]

# --- Скиллы: уникальные пассивки, в отличие от buffs выше их можно
# купить только один раз за игру (Main.has_skill()/unlock_skill()).
# Как только скилл куплен, он больше не выпадает в roll() - см. ниже.
# Цены фиксированные (без rarity_multiplier - у скиллов нет редкости),
# подобраны заметно дороже одиночного баффа: это разовая мощная
# инвестиция, а не стакающийся процент.
var skills = ["second_wind", "thorns", "explosive_kill", "money_magnet"]
var skills_label = {
	"second_wind": "ВТОРОЕ ДЫХАНИЕ",
	"thorns": "ШИПЫ",
	"explosive_kill": "ЦЕПНАЯ РЕАКЦИЯ",
	"money_magnet": "ЖАДНОСТЬ",
}
var skills_desc = {
	"second_wind": "Один раз за игру смертельный урон оставляет вас в живых с 30% здоровья",
	"thorns": "20% урона от ожившего камня возвращается ему же при попадании",
	"explosive_kill": "25% шанс, что разрушенный камень взорвётся и заденет соседние",
	"money_magnet": "+1 монета за каждый разрушенный камень (не зависит от богатства)",
}
var skills_price = {
	"second_wind": 60,
	"thorns": 40,
	"explosive_kill": 45,
	"money_magnet": 35,
}
const SKILL_COLOR = "#ff6b6b"
# Шанс, что карточка окажется скиллом, а не обычным баффом - только пока
# остались ещё не купленные скиллы (см. roll()).
const SKILL_CHANCE: float = 0.18

var is_skill_card: bool = false
var skill_id: String = ""

# Базовая цена (за обычную/"Обычный" редкость) для каждого баффа, индексы
# соответствуют массиву buffs. Ориентируемся на rock_reward из rock.gd:
# камни типов 0-2 (только они выпадают случайно) дают в среднем ~1.83
# монеты за камень, а на уровне обычно 15 камней -> около 27 монет за
# уровень при money_multiplier = 1.0. Цены подобраны так, чтобы одно
# улучшение common-редкости было почти всегда по карману, а прокачанная
# легендарная редкость (x2) требовала откладывать деньги через уровень-два.
# money_multiplier оценён дороже остальных, т.к. это "снежный ком" экономики.
var base_prices = {
	"damage": 10,
	"crit_chance": 12,
	"crit_damage": 14,
	"money_multiplier": 15,
	"health": 8,
	"attack_speed": 13,
	"lifesteal": 12,
	"dodge_chance": 13,
	"regen": 9,
	"move_speed": 7,
}

var rarity = null
var buff = null
var price: int = 0

func _ready() -> void:
	get_tree().current_scene.get_node("Hud").reroll_signal.connect(reroll)

	# Раньше карточка (как часть сцены уровня) пересоздавалась на каждом
	# новом уровне, и roll() в _ready() автоматически давал свежий набор
	# баффов на выбор. Теперь карточка одна на всю игру, поэтому без
	# этой подписки игрок видел бы один и тот же бафф/редкость/цену на
	# всех уровнях подряд, пока сам не нажмёт reroll (а рероллы к тому же
	# ограничены).
	Main.level_changed.connect(_on_level_changed)
	roll()

func _on_level_changed(_level_num: int) -> void:
	roll()
	

func roll():
	# Скилл может выпасть только пока есть хотя бы один ещё не купленный -
	# без этой проверки после покупки всех скиллов SKILL_CHANCE продолжал
	# бы иногда "пустым" срабатывать.
	var available_skills: Array = []
	for s in skills:
		if not Main.has_skill(s):
			available_skills.append(s)

	is_skill_card = available_skills.size() > 0 and randf() < SKILL_CHANCE

	if is_skill_card:
		skill_id = available_skills[randi_range(0, available_skills.size() - 1)]
		rarity = -1
		buff = -1

		name_label.text = skills_label[skill_id]
		desc_label.text = skills_desc[skill_id]
		rarity_label.text = "[color=" + SKILL_COLOR + "]СКИЛЛ"
		style.border_color = Color(SKILL_COLOR)
		$".".add_theme_stylebox_override("panel", style)

		# У скиллов нет редкости/множителя - цена фиксированная и
		# заметно выше одиночного баффа (см. комментарий у skills_price).
		price = skills_price[skill_id]
		price_label.text = "Цена: " + str(price)

		print("SKILL: " + skill_id)
		print("price: " + str(price))
	else:
		skill_id = ""
		rarity = randi_range(0, 3)
		buff = randi_range(0, buffs.size() - 1)

		name_label.text = buffs_label[buff]
		description_buff(buff, rarity)
		rarity_label.text = "[color=" + raritys_colors[rarity] + "]" + raritys[rarity]
		style.border_color = Color(raritys_colors[rarity])
		$".".add_theme_stylebox_override("panel", style)

		# Цена зависит от типа баффа и множителя редкости (те же
		# rarity_multiplier, что уже используются для силы баффа).
		price = int(round(base_prices[buffs[buff]] * rarity_multiplier[rarity]))
		price_label.text = "Цена: " + str(price)

		print(raritys[rarity])
		print(buffs[buff])
		print("price: " + str(price))

	update_affordability()

func reroll():
	roll()
	print("reroll")

func _process(_delta: float) -> void:
	update_affordability()

# Подсвечивает карточку в зависимости от того, хватает ли денег, но
# НЕ трогает Button.disabled - отключённая (disabled) кнопка в Godot
# вообще не получает клики, из-за чего карточка выглядела "нерабочей"
# ещё до того, как игрок успевал что-то нажать. Проверка денег теперь
# только внутри _on_button_pressed(), а кнопка всегда кликабельна.
func update_affordability() -> void:
	var can_afford = Main.money >= price
	
	if can_afford:
		modulate = Color(1, 1, 1, 1)
		price_label.add_theme_color_override("font_color", Color(0.9411765, 0.7411765, 0.16862746, 1))
	else:
		modulate = Color(0.7, 0.7, 0.7, 1)
		price_label.add_theme_color_override("font_color", Color(0.9137255, 0.3529412, 0.3529412, 1))

# Небольшая встряска карточки, чтобы дать понять игроку, что клик
# зарегистрирован, но покупка не прошла - денег не хватает.
func _shake_not_enough_money() -> void:
	var tween := create_tween()
	var base_pos := position
	tween.tween_property(self, "position", base_pos + Vector2(8, 0), 0.04)
	tween.tween_property(self, "position", base_pos - Vector2(8, 0), 0.08)
	tween.tween_property(self, "position", base_pos, 0.04)

func description_buff(buff: int, rarity: int):
	var desc_text
	var value
	match buff:
		0:
			# Раньше показывался голый номинальный %, потому что damage
			# рос без убывающей полезности. Теперь считается так же, как
			# у crit_damage/money_multiplier ниже - через накопленный
			# damage_mult, иначе описание карточки будет врать, если у
			# игрока уже куплены прошлые уровни этого баффа.
			value = plus_damage*rarity_multiplier[rarity]
			var new_dmg_mult = Main.apply_diminishing_multiplier(Main.damage_mult, value/100, Main.DAMAGE_DIMINISH_K)
			var real_gain0 = snappedf((new_dmg_mult - Main.damage_mult)*100, 0.01)
			desc_label.text = "+" + str(real_gain0) + "% К УРОНУ"
		1:
			# Показываем не номинальный %, а реальный прирост с учётом
			# убывающей полезности - иначе описание карточки будет врать,
			# если у игрока уже есть накопленный шанс крита.
			value = plus_crit_chance*rarity_multiplier[rarity]
			var new_chance = Main.apply_diminishing_bonus_capped(Main.chance_crit, Main.CRIT_CHANCE_CAP, value/100)
			var real_gain = snappedf((new_chance - Main.chance_crit)*100, 0.01)
			desc_label.text = "+" + str(real_gain) + "% К ШАНСУ КРИТ. УДАРА"
		2:
			value = plus_crit_damage*rarity_multiplier[rarity]
			var new_crit_mult = Main.apply_diminishing_multiplier(Main.crit_multiplier, value/100, Main.CRIT_DAMAGE_DIMINISH_K)
			var real_gain2 = snappedf((new_crit_mult - Main.crit_multiplier)*100, 0.01)
			desc_label.text = "+" + str(real_gain2) + "% К УРОНУ КРИТ. УДАРА"
		3:
			value = plus_money_multiplier*rarity_multiplier[rarity]
			var new_money_mult = Main.apply_diminishing_multiplier(Main.money_multiplier, value/100, Main.MONEY_MULT_DIMINISH_K)
			var real_gain3 = snappedf((new_money_mult - Main.money_multiplier)*100, 0.01)
			desc_label.text = "+" + str(real_gain3) + "% К КОЛИЧЕСТВУ ПОЛУЧАЕМЫХ МОНЕТ"
		4:
			# См. комментарий у case 0 - та же смена формулы для здоровья.
			value = plus_health*rarity_multiplier[rarity]
			var new_hp_mult = Main.apply_diminishing_multiplier(Main.health_mult, value/100, Main.HEALTH_DIMINISH_K)
			var real_gain4 = snappedf((new_hp_mult - Main.health_mult)*100, 0.01)
			desc_label.text = "+" + str(real_gain4) + "% К ЗДОРОВЬЮ ИГРОКА"
		5:
			value = plus_attack_speed*rarity_multiplier[rarity]
			var new_as = Main.apply_diminishing_multiplier(Main.attack_speed_mult, value/100, Main.ATTACK_SPEED_DIMINISH_K)
			var real_gain5 = snappedf((new_as - Main.attack_speed_mult)*100, 0.01)
			desc_label.text = "+" + str(real_gain5) + "% К СКОРОСТИ АТАКИ"
		6:
			value = plus_lifesteal*rarity_multiplier[rarity]
			var new_ls = Main.apply_diminishing_bonus_capped(Main.lifesteal, Main.LIFESTEAL_CAP, value/100)
			var real_gain6 = snappedf((new_ls - Main.lifesteal)*100, 0.01)
			desc_label.text = "+" + str(real_gain6) + "% ВАМПИРИЗМА (лечение от нанесённого урона)"
		7:
			value = plus_dodge_chance*rarity_multiplier[rarity]
			var new_dc = Main.apply_diminishing_bonus_capped(Main.dodge_chance, Main.DODGE_CHANCE_CAP, value/100)
			var real_gain7 = snappedf((new_dc - Main.dodge_chance)*100, 0.01)
			desc_label.text = "+" + str(real_gain7) + "% К ШАНСУ УКЛОНЕНИЯ"
		8:
			value = plus_regen*rarity_multiplier[rarity]
			var new_rg = Main.apply_diminishing_multiplier(Main.regen_mult, value/100, Main.REGEN_DIMINISH_K)
			var real_gain8 = snappedf((new_rg - Main.regen_mult)*100, 0.01)
			desc_label.text = "+" + str(real_gain8) + "% К СИЛЕ РЕГЕНЕРАЦИИ"
		9:
			value = plus_move_speed*rarity_multiplier[rarity]
			var new_ms = Main.apply_diminishing_multiplier(Main.move_speed_mult, value/100, Main.MOVE_SPEED_DIMINISH_K)
			var real_gain9 = snappedf((new_ms - Main.move_speed_mult)*100, 0.01)
			desc_label.text = "+" + str(real_gain9) + "% К СКОРОСТИ ПЕРЕДВИЖЕНИЯ"


func _on_button_pressed() -> void:
	if Main.money < price:
		_shake_not_enough_money()
		return
	
	Main.money -= price

	if is_skill_card:
		Main.unlock_skill(skill_id)
		print("Скилл получен: " + skill_id)
		upgrade_click.emit()
		return
	
	var value
	match buff:
		0:
			# Раньше: прямое умножение без потолка полезности (см.
			# комментарий у plus_damage выше). Теперь копит damage_mult
			# точно так же, как money_multiplier/crit_multiplier, и
			# base_damage*damage_mult пересчитывается в Main.damage -
			# весь остальной код по-прежнему читает просто Main.damage.
			value = plus_damage*rarity_multiplier[rarity]
			var old_dmg_mult = Main.damage_mult
			Main.damage_mult = Main.apply_diminishing_multiplier(Main.damage_mult, value/100, Main.DAMAGE_DIMINISH_K)
			Main.damage = Main.base_damage * Main.damage_mult
			print("+" + str(snappedf((Main.damage_mult-old_dmg_mult)*100, 0.01)) + "% К УРОНУ (реальный прирост)\nТекущий урон: " + str(Main.damage))
		1:
			value = plus_crit_chance*rarity_multiplier[rarity]
			var old_chance = Main.chance_crit
			Main.chance_crit = Main.apply_diminishing_bonus_capped(Main.chance_crit, Main.CRIT_CHANCE_CAP, value/100)
			print("+" + str(snappedf((Main.chance_crit-old_chance)*100, 0.01)) + "% К ШАНСУ КРИТА (реальный прирост)\nТекущий шанс крита: " + str(Main.chance_crit))
		2:
			value = plus_crit_damage*rarity_multiplier[rarity]
			var old_crit_mult = Main.crit_multiplier
			Main.crit_multiplier = Main.apply_diminishing_multiplier(Main.crit_multiplier, value/100, Main.CRIT_DAMAGE_DIMINISH_K)
			print("+" + str(snappedf((Main.crit_multiplier-old_crit_mult)*100, 0.01)) + "% К КРИТ УРОНУ (реальный прирост)\nТекущий крит урон: " + str(Main.crit_multiplier))
		3:
			value = plus_money_multiplier*rarity_multiplier[rarity]
			var old_money_mult = Main.money_multiplier
			Main.money_multiplier = Main.apply_diminishing_multiplier(Main.money_multiplier, value/100, Main.MONEY_MULT_DIMINISH_K)
			print("+" + str(snappedf((Main.money_multiplier-old_money_mult)*100, 0.01)) + "% К КОЛИЧЕСТВУ МОНЕТ (реальный прирост)\nТекущий money multiplier: " + str(Main.money_multiplier))
		4:
			# См. комментарий у case 0 - та же смена формулы для здоровья.
			value = plus_health*rarity_multiplier[rarity]
			var old_hp_mult = Main.health_mult
			Main.health_mult = Main.apply_diminishing_multiplier(Main.health_mult, value/100, Main.HEALTH_DIMINISH_K)
			Main.max_health = Main.base_max_health * Main.health_mult
			print("+" + str(snappedf((Main.health_mult-old_hp_mult)*100, 0.01)) + "% К ЗДОРОВЬЮ (реальный прирост)\nЗдоровье игрока: " + str(Main.max_health))
		5:
			value = plus_attack_speed*rarity_multiplier[rarity]
			var old_as = Main.attack_speed_mult
			Main.attack_speed_mult = Main.apply_diminishing_multiplier(Main.attack_speed_mult, value/100, Main.ATTACK_SPEED_DIMINISH_K)
			print("+" + str(snappedf((Main.attack_speed_mult-old_as)*100, 0.01)) + "% К СКОРОСТИ АТАКИ\nТекущий множитель: " + str(Main.attack_speed_mult))
		6:
			value = plus_lifesteal*rarity_multiplier[rarity]
			var old_ls = Main.lifesteal
			Main.lifesteal = Main.apply_diminishing_bonus_capped(Main.lifesteal, Main.LIFESTEAL_CAP, value/100)
			print("+" + str(snappedf((Main.lifesteal-old_ls)*100, 0.01)) + "% ВАМПИРИЗМА\nТекущий вампиризм: " + str(Main.lifesteal))
		7:
			value = plus_dodge_chance*rarity_multiplier[rarity]
			var old_dc = Main.dodge_chance
			Main.dodge_chance = Main.apply_diminishing_bonus_capped(Main.dodge_chance, Main.DODGE_CHANCE_CAP, value/100)
			print("+" + str(snappedf((Main.dodge_chance-old_dc)*100, 0.01)) + "% К УКЛОНЕНИЮ\nТекущий шанс уклонения: " + str(Main.dodge_chance))
		8:
			value = plus_regen*rarity_multiplier[rarity]
			var old_rg = Main.regen_mult
			Main.regen_mult = Main.apply_diminishing_multiplier(Main.regen_mult, value/100, Main.REGEN_DIMINISH_K)
			print("+" + str(snappedf((Main.regen_mult-old_rg)*100, 0.01)) + "% К РЕГЕНЕРАЦИИ\nТекущий множитель: " + str(Main.regen_mult))
		9:
			value = plus_move_speed*rarity_multiplier[rarity]
			var old_ms = Main.move_speed_mult
			Main.move_speed_mult = Main.apply_diminishing_multiplier(Main.move_speed_mult, value/100, Main.MOVE_SPEED_DIMINISH_K)
			print("+" + str(snappedf((Main.move_speed_mult-old_ms)*100, 0.01)) + "% К СКОРОСТИ ПЕРЕДВИЖЕНИЯ\nТекущий множитель: " + str(Main.move_speed_mult))
	upgrade_click.emit()
