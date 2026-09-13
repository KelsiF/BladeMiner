extends CharacterBody2D

signal player_died

@export var move_speed: float = 300.0      # скорость перемещения к курсору
@export var rotation_speed: float = 10.0   # скорость вращения спрайта (рад/сек)
@export var stop_distance: float = 5.0     # дистанция, при которой персонаж останавливается

@export var knockback_force: float = 400.0
@export var knockback_duration: float = 0.2
@export var damage_cooldown: float = 0.5   # чтобы урон не наносился каждый кадр

@onready var sprite: Sprite2D = $Sprite2D

var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0
var damage_timers: Dictionary = {} # instance_id камня -> оставшееся время кулдауна

var health: float
var max_health: float

func _ready() -> void:
	# Ожившие камни (rock.gd) ищут игрока через
	# get_tree().get_first_node_in_group("player") - без этой регистрации
	# им было бы не за кем гнаться и некого атаковать.
	add_to_group("player")

	# Раньше игрок пересоздавался вместе со сценой на каждом уровне, и
	# эти строки в _ready() выполнялись заново, каждый раз подхватывая
	# актуальные Main.max_health (с учётом уже купленных апгрейдов) и
	# полностью восстанавливая здоровье. Теперь игрок один на всю игру,
	# поэтому вынесли это в отдельный метод и подписались на
	# Main.level_changed, чтобы синхронизация происходила при СТАРТЕ
	# КАЖДОГО уровня, а не только один раз при запуске игры.
	Main.level_changed.connect(_on_level_changed)
	_sync_stats()

func _on_level_changed(_level_num: int) -> void:
	_sync_stats()

func _sync_stats() -> void:
	max_health = Main.max_health
	health = max_health

	$HealthBar.max_value = max_health
	$HealthBar.value = health

func _process(delta: float) -> void:
	$HealthBar.value = health

func _physics_process(delta: float) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var direction: Vector2 = global_position.direction_to(mouse_pos)
	var distance: float = global_position.distance_to(mouse_pos)

	if Main.game_active:
		# Пока идёт отскок — управление временно отключено
		if knockback_timer > 0.0:
			knockback_timer -= delta
			velocity = knockback_velocity
		else:
			if distance > stop_distance:
				velocity = direction * move_speed
			else:
				velocity = Vector2.ZERO
	
		move_and_slide()

		_update_damage_cooldowns(delta)
		_handle_collisions()

		# Постоянное вращение спрайта (эффект спиннера)
		sprite.rotation += rotation_speed * delta


# Раньше health/max_health существовали только "для галочки" - HealthBar
# отображал их, а карточка апгрейда "ЗДОРОВЬЕ" (upgrade_card.gd) увеличивала
# max_health, но ничего в игре реально не наносило игроку урон, поэтому
# здоровье никогда не тратилось. Теперь ожившие камни (rock.gd) зовут этот
# метод при атаке, и здоровье игрока действительно становится ресурсом.
func take_damage(amount: float) -> void:
	if not Main.game_active:
		return

	health -= amount
	health = clamp(health, 0.0, max_health)
	$HealthBar.value = health

	_flash_damage()

	if health <= 0.0:
		_die()

# Короткая вспышка цвета спрайта, чтобы удар от "ожившего" камня был
# заметен, а не просто тихо утекал из полоски здоровья.
func _flash_damage() -> void:
	sprite.modulate = Color(1.0, 0.35, 0.35)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.2)

func _die() -> void:
	player_died.emit()
	Main.game_active = false

	# Полноценного экрана поражения пока нет (см. TODO про босса в
	# level.gd) - перезапускаем текущий уровень так же, как это уже
	# делает Main.restart_level() по ручному нажатию "restart". Рестарт
	# откладываем через call_deferred, чтобы не пересобирать камни (в том
	# числе тот, что только что атаковал) прямо посреди его собственного
	# _physics_process().
	Main.call_deferred("restart_level")

func _update_damage_cooldowns(delta: float) -> void:
	for id in damage_timers.keys():
		damage_timers[id] -= delta
		if damage_timers[id] <= 0.0:
			damage_timers.erase(id)


func _handle_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		if collider == null:
			continue

		# Оживший камень наносит урон именно в момент физического касания -
		# без этого вызова attack_range в rock.gd мог никогда не
		# сработать: knockback ниже расталкивает игрока и камень раньше,
		# чем дистанция между ними успевает опуститься до attack_range.
		if collider.has_method("notify_player_contact"):
			collider.notify_player_contact()

		if collider.has_method("take_damage"):
			var id: int = collider.get_instance_id()
			if not damage_timers.has(id):
				# Раньше здесь стояла переменная damage_to_rock, которая
				# считывала Main.damage только один раз при создании
				# игрока (при перезапуске сцены - заново). Теперь читаем
				# Main.damage прямо в момент удара, иначе купленные в
				# апгрейд-магазине бонусы к урону не доходили бы до боя.
				collider.take_damage(Main.damage)
				damage_timers[id] = damage_cooldown

				# Отскок в сторону от точки столкновения
				var push_dir: Vector2 = (global_position - collision.get_position()).normalized()
				if push_dir == Vector2.ZERO:
					push_dir = -collision.get_normal()
				print("push_dir: ", push_dir, " | force: ", knockback_force, " | итоговая скорость: ", (push_dir * knockback_force).length())
				knockback_velocity = push_dir * knockback_force
				knockback_timer = knockback_duration


func _on_heal_timer_timeout() -> void:
	if health < max_health:
		health = health+(max_health*0.05)
		print("heal! "+str(health+(max_health*0.05)))
		if health > max_health:
			health = max_health
	else:
		print("хп полное!")
	$HealTimer.start()
