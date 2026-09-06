extends PanelContainer

signal upgrade_click

@onready var card = $"."
@onready var rarity_label = $CardMargin/CardVBox/RarityLabel
@onready var name_label = $CardMargin/CardVBox/NameLabel
@onready var desc_label = $CardMargin/CardVBox/DescriptionLabel
@onready var icon = $CardMargin/CardVBox/IconCenter/Icon

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

var rarity = null
var buff = null

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
	print(raritys[rarity])
	print(buffs[buff])

func reroll():
	roll()
	print("reroll")

func description_buff(buff: int, rarity: int):
	var desc_text
	var value
	match buff:
		0:
			value = plus_damage*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К УРОНУ"
		1:
			value = plus_crit_chance*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К ШАНСУ КРИТ. УДАРА"
		2:
			value = plus_crit_damage*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К УРОНУ КРИТ. УДАРА"
		3:
			value = plus_money_multiplier*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К КОЛИЧЕСТВУ ПОЛУЧАЕМЫХ МОНЕТ"
		4:
			value = plus_health*rarity_multiplier[rarity]
			desc_label.text = "+" + str(value) + "% К ЗДОРОВЬЮ ИГРОКА"


func _on_button_pressed() -> void:
	var value
	match buff:
		0:
			value = plus_damage*rarity_multiplier[rarity]
			Main.damage = Main.damage*(value/100+1)
			print("+" + str(value) + "% К УРОНУ\nТекущий урон: " + str(Main.damage))
		1:
			value = plus_crit_chance*rarity_multiplier[rarity]
			Main.chance_crit = Main.chance_crit+(value/100)
			print("+" + str(value) + "% К ШАНСУ КРИТА\nТекущий шанс крита: " + str(Main.chance_crit))
		2:
			value = plus_crit_damage*rarity_multiplier[rarity]
			Main.crit_multiplier = Main.crit_multiplier+(value/100)
			print("+" + str(value) + "% К КРИТ УРОНУ\nТекущий крит урон: " + str(Main.crit_multiplier))
		3:
			value = plus_money_multiplier*rarity_multiplier[rarity]
			Main.money_multiplier = Main.money_multiplier+(value/100)
			print("+" + str(value) + "% К КОЛИЧЕСТВУ МОНЕТ\nТекущий money multiplier: " + str(Main.money_multiplier))
		4:
			value = plus_health*rarity_multiplier[rarity]
			Main.max_health = Main.max_health*(value/100+1)
			print("+" + str(value) + "% К ЗДОРОВЬЮ ИГРОКА\nЗдоровье игрока: " + str(Main.max_health))
	upgrade_click.emit()
