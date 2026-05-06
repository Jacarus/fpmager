extends Node

const WorldScene = preload("res://Scenes/World/World.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldScene.instantiate()
	add_child(world)

	var spawned: bool = world.spawn_boss({
		"display_name": "Test Colossus",
		"max_health": 1200,
		"avatar_scale": 0.8,
		"despawn_delay": 5.0,
		"blind_volley_enabled": false,
		"large_aoe_enabled": false,
		"singularity_enabled": false,
	})
	_assert_eq(spawned, true, "spawns boss")
	_assert_eq(world.get_boss_count(), 1, "tracks boss count")

	var boss := world.get_node_or_null("BossCaster_0")
	_assert_ne(boss, null, "boss node exists")
	var state: Dictionary = boss.get_state_data()
	_assert_eq(state["display_name"], "Test Colossus", "applies display name")
	_assert_eq(state["max_health"], 1200, "applies max health")
	_assert_eq((state["parts"] as Array).size(), 5, "creates destructible parts")
	var total_part_max := 0
	var feet_found := false
	for part in state["parts"]:
		var data := part as Dictionary
		total_part_max += int(data["max_health"])
		if str(data["id"]) == "feet":
			feet_found = true
			_assert_eq(str(data["ability"]), "movement", "feet controls movement")
	_assert_eq(feet_found, true, "creates movement feet part")
	_assert_eq(abs(total_part_max - 1200) <= 2, true, "part health scales with boss health")

	var spell := SpellDefinition.new()
	spell.spell_name = "Test Breaker"
	spell.base_element = "Fire"
	spell.base_weights = {"Fire": 100}
	spell.shape = "Sphere"
	spell.intensity = 20
	spell.spell_size = 20
	spell.spell_range = 1
	spell.spell_speed = 1
	for i in range(8):
		boss.apply_part_spell_hit("left_arm", spell, Vector3.ZERO, Vector3.UP, false)
	state = boss.get_state_data()
	var left_arm_destroyed := false
	for part in state["parts"]:
		var data := part as Dictionary
		if str(data["id"]) == "left_arm":
			left_arm_destroyed = bool(data["destroyed"])
	_assert_eq(left_arm_destroyed, true, "destroying a part is reflected in boss state")

	var target := Node3D.new()
	world.add_child(target)
	target.global_position = boss.global_position + Vector3(0, 0, -20)
	boss.target = target
	var start_position: Vector3 = boss.global_position
	boss._update_movement(0.5)
	var moved_with_feet: bool = boss.global_position.distance_to(start_position) > 0.01
	_assert_eq(moved_with_feet, true, "boss moves while feet are intact")
	boss.global_position = start_position
	for i in range(8):
		boss.apply_part_spell_hit("feet", spell, Vector3.ZERO, Vector3.UP, false)
	boss.target = target
	boss._update_movement(0.5)
	var moved_without_feet: bool = boss.global_position.distance_to(start_position) > 0.01
	_assert_eq(moved_without_feet, false, "destroyed feet prevent movement")

	for part_id in ["core", "head", "right_arm"]:
		for i in range(12):
			boss.apply_part_spell_hit(part_id, spell, Vector3.ZERO, Vector3.UP, false)
	state = boss.get_state_data()
	_assert_eq(state["is_dead"], true, "boss enters defeated state")
	_assert_eq(world.get_boss_count(), 1, "defeated boss remains world-owned during despawn grace")

	print("test_boss_spawn: OK")
	get_tree().quit(0)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])
		get_tree().quit(1)
		return


func _assert_ne(actual: Variant, unexpected: Variant, label: String) -> void:
	if actual == unexpected:
		push_error("%s: did not expect %s" % [label, str(unexpected)])
		get_tree().quit(1)
		return
