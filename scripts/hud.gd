extends CanvasLayer

signal reroll_signal

var on_continue = false

# Сколько рероллов даётся игроку на один экран улучшений.
#
# Раньше Hud пересоздавался при смене уровня вместе со сценой, поэтому
# rerolls_left (и on_continue ниже) сами возвращались к значению по
# умолчанию. Теперь Hud живёт всю игру, поэтому оба сбрасываются вручную
# в _on_level_changed() при старте каждого нового уровня - см. подписку
# на Main.level_changed в _ready().
const MAX_REROLLS := 3
var rerolls_left := MAX_REROLLS

@onready var card_hbox: HBoxContainer = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox
@onready var reroll_button: Button = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/RerollCenter/ActionsHBox/RerollButton

func _ready() -> void:
	$LevelCompleteUI.hide()
	$UpgradeScreen.hide()
	
	for card in card_hbox.get_children():
		if card.has_signal("upgrade_click"):
			card.upgrade_click.connect(_on_upgradeclick.bind(card))
	
	#$UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox/UpgradeCard.upgrade_click.connect(_on_upgradeclick)
	#$UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox/UpgradeCard2.upgrade_click.connect(_on_upgradeclick)
	#$UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox/UpgradeCard3.upgrade_click.connect(_on_upgradeclick)
	
	_update_reroll_button()
	Main.level_changed.connect(_on_level_changed)

func _on_level_changed(_level_num: int) -> void:
	# Без этого сброса после первого же пройденного уровня on_continue
	# остался бы true навсегда, и see_levelcomplete() перестал бы вообще
	# показывать экран завершения уровня - игра выглядела бы "зависшей"
	# сразу после уничтожения последнего камня на 2-м уровне.
	on_continue = false
	rerolls_left = MAX_REROLLS
	_update_reroll_button()

func _process(delta: float) -> void:
	Main.money = snappedf(Main.money, 0.1)
	Main.damage = snappedf(Main.damage, 0.01)
	$HUD/HBoxContainer/VBoxContainer3/Money.text = "Монет: " + str(Main.money) + " (+" + str((Main.money_multiplier-1)*100) + "%)"
	$HUD/HBoxContainer/VBoxContainer3/Damage.text = "Урон: " + str(Main.damage)
	$HUD/HBoxContainer/VBoxContainer2/Rocks.text = "Осталось камней: " + str(Main.need_rocks-Main.destroyed_rocks)
	
	$HUD/HBoxContainer/VBoxContainer/LevelProgress.max_value = Main.need_rocks
	$HUD/HBoxContainer/VBoxContainer/LevelProgress.value = Main.destroyed_rocks
	$HUD/HBoxContainer/VBoxContainer/LevelProgress_Label.text = str(Main.current_level) + " Уровень" 
	
	see_levelcomplete()
	
	$DebugLabel.text = "max_health: "+str(Main.max_health)+"\nchance_crit: "+str(Main.chance_crit)+" -> "+str(Main.chance_crit*100)+"%"+"\ncrit_multiplier: "+str(Main.crit_multiplier)+" ->"+str((Main.crit_multiplier-1)*100)+"%"+"\natk_speed_mult: x"+str(Main.attack_speed_mult)+"\nlifesteal: "+str(Main.lifesteal*100)+"%"+"\ndodge_chance: "+str(Main.dodge_chance*100)+"%"+"\nregen_mult: x"+str(Main.regen_mult)+"\nmove_speed_mult: x"+str(Main.move_speed_mult)+"\nskills: "+str(Main.unlocked_skills.keys())

func see_levelcomplete():
	if Main.game_active == false:
		if on_continue == false:
			$LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/RocksDestroyed/ValueLabel.text = str(Main.destroyed_rocks)
			# Было захардкожено "1" вместо реально заработанных за уровень
			# монет (Main.getted_money уже считается в rock.gd).
			$LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/MoneyGet/ValueLabel.text = str(Main.getted_money)
			$LevelCompleteUI.show()


func _on_continue_button_pressed() -> void:
	if Main.game_active == false:
		$LevelCompleteUI.hide()
		$UpgradeScreen.show()
		on_continue = true


func _on_reroll_button_pressed() -> void:
	if rerolls_left <= 0:
		return
	
	rerolls_left -= 1
	reroll_signal.emit()
	_update_reroll_button()

func _update_reroll_button() -> void:
	reroll_button.text = "⟲ REROLL (" + str(rerolls_left) + ")"
	reroll_button.disabled = rerolls_left <= 0

# Игрок может застрять на экране улучшений, если ни одна карточка ему
# не по карману (и рероллы уже кончились) - улучшения теперь платные,
# а раньше единственным способом уйти с экрана была покупка. Кнопка
# "ПРОПУСТИТЬ" просто закрывает экран и пускает на следующий уровень
# без применения баффа, деньги при этом не тратятся.
func _on_skip_button_pressed() -> void:
	$UpgradeScreen.hide()
	Main.load_next_level()

func _on_upgradeclick(card: Node):
	$UpgradeScreen.hide()
	print(card)
	Main.load_next_level()
