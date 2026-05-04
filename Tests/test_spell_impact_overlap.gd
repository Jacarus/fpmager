extends SceneTree

const SpellImpactEffectScript = preload("res://Scripts/SpellImpactEffect.gd")


class DamageProbe:
	extends Node3D

	var hit_count: int = 0
	var blind_count: int = 0
	var gravity_count: int = 0

	func apply_spell_hit(_spell: SpellDefinition, _hit_position: Vector3, _hit_normal: Vector3, _is_beam_tick: bool = false) -> void:
		hit_count += 1

	func apply_blind(_duration: float) -> void:
		blind_count += 1

	func apply_gravity_pull(_center: Vector3, _spell: SpellDefinition, _radius: float, _is_beam_tick: bool = false) -> void:
		gravity_count += 1

	func is_damageable() -> bool:
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "SpellImpactOverlapTest"
	get_root().add_child(root)
	current_scene = root

	var spell := _make_area_spell()
	var effect := SpellImpactEffectScript.new()
	root.add_child(effect)
	effect.initialize(spell, Vector3.ZERO, Vector3.UP, null)

	var final_radius: float = effect._radius
	var early_radius: float = effect._get_current_effect_radius()
	_assert_eq(early_radius < final_radius, true, "effect starts smaller than final radius")

	var probe := DamageProbe.new()
	root.add_child(probe)
	probe.global_position = Vector3(early_radius + 0.25, 0.04, 0.0)
	_assert_eq(probe.global_position.distance_to(effect.global_position) < final_radius, true, "probe is inside final area")
	_assert_eq(probe.global_position.distance_to(effect.global_position) > early_radius, true, "probe is outside visible early area")

	effect._apply_area_spell_tick()
	_assert_eq(probe.hit_count, 0, "outside visible effect does not take area damage")

	effect._age = effect._lifetime
	effect._apply_area_spell_tick()
	_assert_eq(probe.hit_count, 1, "inside visible effect takes area damage")

	probe.global_position = Vector3(final_radius + 0.75, 0.04, 0.0)
	effect._apply_area_spell_tick()
	_assert_eq(probe.hit_count, 1, "outside final effect takes no damage")

	var source_probe := DamageProbe.new()
	root.add_child(source_probe)
	source_probe.global_position = Vector3(0.0, 0.04, 0.0)
	var self_damage_effect := SpellImpactEffectScript.new()
	root.add_child(self_damage_effect)
	self_damage_effect.initialize(spell, Vector3.ZERO, Vector3.UP, source_probe)
	self_damage_effect._age = self_damage_effect._lifetime
	self_damage_effect._apply_area_spell_tick()
	_assert_eq(source_probe.hit_count, 1, "spell source takes self damage from overlapping impact")

	var blocked_effect := SpellImpactEffectScript.new()
	root.add_child(blocked_effect)
	blocked_effect.initialize(spell, Vector3.ZERO, Vector3.UP, null)
	blocked_effect._age = blocked_effect._lifetime
	blocked_effect.set_blocking_plane(Vector3.ZERO, Vector3.FORWARD)

	probe.hit_count = 0
	probe.global_position = Vector3(0.0, 0.04, 1.0)
	blocked_effect._apply_area_spell_tick()
	_assert_eq(probe.hit_count, 0, "blocked wall side takes no reaction damage")

	probe.global_position = Vector3(0.0, 0.04, -1.0)
	blocked_effect._apply_area_spell_tick()
	_assert_eq(probe.hit_count, 1, "front side takes reaction damage")

	probe.global_position = Vector3(1.0, 0.04, 0.0)
	blocked_effect._apply_area_spell_tick()
	_assert_eq(probe.hit_count, 2, "side of wall takes reaction damage")

	print("test_spell_impact_overlap: OK")
	quit(0)


func _make_area_spell() -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = "Test Cataclysm"
	spell.base_element = "Fire"
	spell.base_weights = {"Fire": 50, "Earth": 50}
	spell.shape = "Sphere"
	spell.intensity = 6
	spell.spell_size = 26
	spell.spell_range = 8
	spell.spell_speed = 1
	spell.burns = true
	spell.has_density = true
	spell.density = 6
	return spell


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])
		quit(1)
