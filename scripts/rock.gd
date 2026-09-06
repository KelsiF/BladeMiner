extends StaticBody2D
class_name Rock

signal rock_destroyed

@export var shake_strength: float = 8.0
@export var shake_duration: float = 0.4
@export var shake_count: int = 8

var original_position: Vector2
var current_tween: Tween

# игрок в среднем один камень должен ломать около 2х секунд
const type_rock = ["default", "strong", "big", "alive"]
const rock_hp = [25, 30, 37, 45]
const rock_size = [2.0, 2.25, 2.5, 2.75]
const rock_reward = [1.0, 1.5, 3.0, 5.0]
const hp_multiplier = [1.0, 1.1, 1.2, 1.3, 1.4] # множитель в зависимости от уровня

var forced_type: int = -1
var type



@export var max_health: float = 10
var health: float

func _ready() -> void:
	
	original_position = position
	
	type = forced_type if forced_type != -1 else randi_range(0, 2)

	max_health = rock_hp[type]+Main.damage*2
	#print(max_health)
	scale = Vector2(rock_size[type], rock_size[type])
	
	#print("type: " + str(type) + "\nscale: " + str(scale))
	
	health = max_health

func _process(delta: float) -> void:
	#$HealthLabel.text = str(health) + "/" + str(max_health)
	$HealthBar.max_value = max_health
	$HealthBar.value = health

func take_damage(amount: int) -> void:
	
	var chance = randf_range(0.00, 1.00)
	
	if chance <= Main.chance_crit:
		health -= amount*Main.crit_multiplier
		health = max(health, 0)
		print("CRIT")
	else:
		health -= amount
		health = max(health, 0)
	shake()
	

	#print("Rock health: ", health, " / ", max_health)

	if health <= 0:
		
		var particles = $CPUParticles2D
		
		remove_child(particles)
		get_parent().add_child(particles)
		
		particles.global_position = global_position
		particles.emitting = true
		
		var timer = get_tree().create_timer(particles.lifetime)
		timer.timeout.connect(particles.queue_free)
		
		rock_destroyed.emit()
		queue_free()
		Main.money += rock_reward[type]*Main.money_multiplier
		Main.left_rocks -= 1
		Main.destroyed_rocks += 1
		Main.getted_money += rock_reward[type]*Main.money_multiplier

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
