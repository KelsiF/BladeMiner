extends CanvasLayer

signal reroll_signal

var on_continue = false

@onready var card_hbox: HBoxContainer = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox

func _ready() -> void:
	$LevelCompleteUI.hide()
	$UpgradeScreen.hide()
	
	for card in card_hbox.get_children():
		if card.has_signal("upgrade_click"):
			card.upgrade_click.connect(_on_upgradeclick.bind(card))
	
	#$UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox/UpgradeCard.upgrade_click.connect(_on_upgradeclick)
	#$UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox/UpgradeCard2.upgrade_click.connect(_on_upgradeclick)
	#$UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox/UpgradeCard3.upgrade_click.connect(_on_upgradeclick)

func _process(delta: float) -> void:
	$HUD/HBoxContainer/VBoxContainer3/Money.text = "Монет: " + str(Main.money) + " (+" + str((Main.money_multiplier-1)*100) + "%)"
	$HUD/HBoxContainer/VBoxContainer3/Damage.text = "Урон: " + str(Main.damage)
	$HUD/HBoxContainer/VBoxContainer2/Rocks.text = "Осталось камней: " + str(Main.need_rocks)
	
	$HUD/HBoxContainer/VBoxContainer/LevelProgress.max_value = Main.need_rocks
	$HUD/HBoxContainer/VBoxContainer/LevelProgress.value = Main.destroyed_rocks
	$HUD/HBoxContainer/VBoxContainer/LevelProgress_Label.text = str(Main.current_level) + " Уровень" 
	
	see_levelcomplete()

func see_levelcomplete():
	if Main.game_active == false:
		if on_continue == false:
			$LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/RocksDestroyed/ValueLabel.text = str(Main.destroyed_rocks)
			$LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/MoneyGet/ValueLabel.text = "1"
			$LevelCompleteUI.show()


func _on_continue_button_pressed() -> void:
	$LevelCompleteUI.hide()
	$UpgradeScreen.show()
	on_continue = true


func _on_reroll_button_pressed() -> void:
	reroll_signal.emit()

func _on_upgradeclick(card: Node):
	$UpgradeScreen.hide()
	print(card)
	Main.load_next_level()
