extends PanelContainer

signal upgrade_click

@onready var card = $"."
@onready var rarity_label = $CardMargin/CardVBox/RarityLabel
@onready var name_label = $CardMargin/CardVBox/NameLabel
@onready var desc_label = $CardMargin/CardVBox/DescriptionLabel
@onready var icon = $CardMargin/CardVBox/IconCenter/Icon
@onready var price_label = $CardMargin/CardVBox/PriceLabel

var style: StyleBoxFlat = $".".get_theme_stylebox("panel").duplicate()

var plus_damage = 10
var plus_crit_chance = 5
var plus_crit_damage = 5
var plus_money_multiplier = 10
var plus_health = 10

var raritys = ["Обычный", "Редкий", "Эпический", "Легендарный"]
var raritys_colors = ["#ffffff", "#53cfbd", "#cfa3e9", "#e9aa46"]
var rarity_multiplier = [1.0, 1.25, 1.5, 2.0]

var buffs = ["damage", "crit_chance", "crit_damage", "money_multiplier", "health"]
var buffs_label = ["УРОН", "ШАНС КРИТ. УДАРА", "УРОН КРИТ. УДАРА", "БОГАТСТВО", "ЗДОРОВЬЕ"]

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
}

var rarity = null
var buff = null
var price: int = 0

func _ready() -> void:
	get_tree().current_scene.get_node("Hud").reroll_signal.connect(reroll)
	roll()
	

func roll():
	rarity = randi_range(0, 3)
	buff = randi_range(0, 4)
	
	name_label.text = buffs_label[buff]
	description_buff(buff, rarity)
	rarity_label.text = "[color=" + raritys_colors[rarity] + "]" + raritys[rarity]
	style.border_color = Color(raritys_colors[rarity])
	$".".add_theme_stylebox_override("panel", style)
	
	# Цена зависит от типа баффа и множителя редкости (те же
	# rarity_multiplier, что уже используются для силы баффа).
	price = int(round(base_prices[buffs[buff]] * rarity_multiplier[rarity]))
	price_label.text = "Цена: " + str(price)
	
	update_affordability()
	
	print(raritys[rarity])
	print(buffs[buff])
	print("price: " + str(price))

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
			value = plus_damage*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К УРОНУ"
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
			value = plus_health*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К ЗДОРОВЬЮ ИГРОКА"


func _on_button_pressed() -> void:
	if Main.money < price:
		_shake_not_enough_money()
		return
	
	Main.money -= price
	
	var value
	match buff:
		0:
			value = plus_damage*rarity_multiplier[rarity]
			Main.damage = Main.damage*(value/100+1)
			print("+" + str(value) + "% К УРОНУ\nТекущий урон: " + str(Main.damage))
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
			value = plus_health*rarity_multiplier[rarity]
			Main.max_health = Main.max_health*(value/100+1)
			print("+" + str(value) + "% К ЗДОРОВЬЮ ИГРОКА\nЗдоровье игрока: " + str(Main.max_health))
	upgrade_click.emit()
