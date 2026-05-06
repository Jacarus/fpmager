extends SceneTree

const SpellProjectileScript = preload("res://Scenes/SpellProjectile/SpellProjectile.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "WallBlockingTest"
	get_root().add_child(root)
	current_scene = root

	var fire_wall := _make_wall("Fire", 5, 4)
	fire_wall.wall_time = 7
	var same_wall := _spawn_wall(root, fire_wall)
	_assert_eq(is_equal_approx(same_wall._max_lifetime, 7.0), true, "wall lifetime uses wall time")
	_assert_eq(_count_visible_cracks(same_wall), 0, "fresh wall starts without cracks")
	var start_alpha: float = same_wall._material.albedo_color.a
	same_wall._lifetime = same_wall._max_lifetime * 0.9
	same_wall._update_wall_visuals()
	_assert_eq(same_wall._material.albedo_color.a < start_alpha, true, "wall fades as timeout approaches")
	same_wall._lifetime = 0.0
	same_wall._update_wall_visuals()
	var same_hit: Dictionary = same_wall.apply_wall_block(_make_sphere("Fire", 5, 4))
	var same_damage := float(same_hit.get("damage", 0.0))
	_assert_eq(same_damage > 0.0, true, "same-type hit damages wall")
	_assert_eq(_count_visible_cracks(same_wall) > 0, true, "damaged wall shows cracks")

	var opposed_wall := _spawn_wall(root, fire_wall)
	var opposed_hit: Dictionary = opposed_wall.apply_wall_block(_make_sphere("Water", 5, 4))
	var opposed_damage := float(opposed_hit.get("damage", 0.0))
	_assert_eq(opposed_damage > same_damage, true, "opposed element damages wall more")
	_assert_ne(opposed_hit.get("reaction_spell"), null, "opposed element creates a reaction spell")

	var strong_wall := _spawn_wall(root, _make_wall("Earth", 8, 6))
	var weak_wall := _spawn_wall(root, _make_wall("Light", 8, 6))
	_assert_eq(strong_wall.get_wall_max_health() > weak_wall.get_wall_max_health(), true, "wall type affects health")
	_assert_ne(strong_wall._wall_physical_body, null, "earth wall creates a physical body")
	_assert_ne(strong_wall._wall_collision_shape, null, "earth wall creates a collision shape")
	var earth_shape := strong_wall._wall_collision_shape.shape as BoxShape3D
	_assert_eq(earth_shape != null and earth_shape.size.z > strong_wall._wall_size.z, true, "earth wall has solid collision thickness")
	_assert_eq(strong_wall.get_spell_definition().calculate_damage(), 0, "earth wall deals no direct damage")
	_assert_eq(weak_wall._wall_physical_body, null, "non-earth wall remains non-physical")
	var one_second_wall_spell := _make_wall("Earth", 2, 2)
	one_second_wall_spell.wall_time = 1
	var default_wall_spell := _make_wall("Earth", 2, 2)
	default_wall_spell.wall_time = 4
	var long_wall_spell := _make_wall("Earth", 2, 2)
	long_wall_spell.wall_time = 8
	var early_cost_growth: int = default_wall_spell.calculate_credits() - one_second_wall_spell.calculate_credits()
	var late_cost_growth: int = long_wall_spell.calculate_credits() - default_wall_spell.calculate_credits()
	_assert_eq(late_cost_growth > early_cost_growth * 2, true, "wall time cost scales exponentially")

	var hit_data: Dictionary = strong_wall.get_wall_segment_hit(Vector3(0.0, 1.0, -3.0), Vector3(0.0, 1.0, 3.0), 0.2)
	_assert_eq(hit_data.is_empty(), false, "moving spell segment hits wall face")
	var miss_data: Dictionary = strong_wall.get_wall_segment_hit(Vector3(6.0, 1.0, -3.0), Vector3(6.0, 1.0, 3.0), 0.2)
	_assert_eq(miss_data.is_empty(), true, "moving spell segment misses beside wall")

	var break_wall := _spawn_wall(root, _make_wall("Fire", 1, 1))
	var breaker := _make_sphere("Water", 25, 12)
	var break_result: Dictionary = break_wall.apply_wall_block(breaker)
	_assert_eq(bool(break_result.get("destroyed", false)), true, "wall disappears when health is depleted")

	print("test_wall_blocking: OK")
	root.queue_free()
	quit(0)


func _spawn_wall(root: Node, spell: SpellDefinition) -> Node:
	var wall := SpellProjectileScript.new()
	root.add_child(wall)
	wall.initialize(spell, Vector3.ZERO, Vector3.FORWARD, null)
	return wall


func _make_wall(base: String, intensity: int, size: int) -> SpellDefinition:
	var spell := _make_sphere(base, intensity, size)
	spell.spell_name = "%s Wall" % base
	spell.shape = "Wall"
	spell.wall_time = 4
	return spell


func _make_sphere(base: String, intensity: int, size: int) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = "%s Sphere" % base
	spell.base_element = base
	spell.base_weights = {base: 100}
	spell.shape = "Sphere"
	spell.intensity = intensity
	spell.spell_size = size
	spell.spell_range = 3
	spell.spell_speed = 3
	if base == "Fire":
		spell.burns = true
	if base == "Water":
		spell.cools = true
	return spell


func _count_visible_cracks(wall: Node) -> int:
	var visible_count := 0
	for crack in wall._wall_cracks:
		var crack_node := crack as MeshInstance3D
		if crack_node != null and crack_node.visible:
			visible_count += 1
	return visible_count


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])
		quit(1)


func _assert_ne(actual: Variant, unexpected: Variant, label: String) -> void:
	if actual == unexpected:
		push_error("%s: did not expect %s" % [label, str(unexpected)])
		quit(1)
