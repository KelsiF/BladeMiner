extends CharacterBody2D

@export var move_speed: float = 300.0      # скорость перемещения к курсору
@export var rotation_speed: float = 10.0   # скорость вращения спрайта (рад/сек)
@export var stop_distance: float = 5.0     # дистанция, при которой персонаж останавливается

var damage_to_rock = Main.damage
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


func _update_damage_cooldowns(delta: float) -> void:
	for id in damage_timers.keys():
		damage_timers[id] -= delta
		if damage_timers[id] <= 0.0:
			damage_timers.erase(id)


func _handle_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		if collider and collider.has_method("take_damage"):
			var id: int = collider.get_instance_id()
			if not damage_timers.has(id):
				collider.take_damage(damage_to_rock)
				damage_timers[id] = damage_cooldown

				# Отскок в сторону от точки столкновения
				var push_dir: Vector2 = (global_position - collision.get_position()).normalized()
				if push_dir == Vector2.ZERO:
					push_dir = -collision.get_normal()
				knockback_velocity = push_dir * knockback_force
				knockback_timer = knockback_duration
