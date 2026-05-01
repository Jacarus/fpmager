extends SceneTree

var _failures := 0


func _init() -> void:
	_test_single_element_spell_costs_and_mana()
	_test_known_synergy_healing_spell_behavior()
	_test_void_earth_gravity_spell_behavior()
	_test_solar_flare_damage_is_reduced_for_blind_spell()
	if _failures > 0:
		quit(1)
		return
	print("test_spell_definition: OK")
	quit(0)


func _test_single_element_spell_costs_and_mana() -> void:
	var spell := SpellDefinition.new()
	spell.spell_name = "Fireball"
	spell.base_element = "Fire"
	spell.shape = "Sphere"
	spell.intensity = 3
	spell.spell_size = 2
	spell.spell_range = 5
	spell.spell_speed = 4
	spell.burns = true

	_assert_eq(spell.calculate_credits(), 47, "single-element spell credit cost")
	_assert_eq(spell.calculate_mana_cost(), 29, "single-element spell mana cost")
	_assert_eq(spell.get_spell_type(), "Simple", "single-element spell type")
	_assert_eq(spell.calculate_damage(), 25, "single-element spell damage")
	_assert_eq(spell.is_valid(), true, "single-element spell is valid")


func _test_known_synergy_healing_spell_behavior() -> void:
	var spell := SpellDefinition.new()
	spell.spell_name = "Healing Mist"
	spell.base_weights = {"Spirit": 50.0, "Water": 50.0}
	spell.shape = "Sphere"
	spell.intensity = 4
	spell.spell_size = 3
	spell.spell_range = 4
	spell.spell_speed = 2

	_assert_eq(spell.get_blend_key(), "Spirit+Water", "healing synergy blend key")
	_assert_eq(spell.is_known_synergy(), true, "healing synergy is known")
	_assert_eq(spell.get_base_display_name(), "Healing Mist", "healing synergy display name")
	_assert_eq(spell.is_healing_spell(), true, "healing synergy counts as healing")
	_assert_eq(spell.calculate_credits(), 62, "healing synergy credit cost")
	_assert_eq(spell.calculate_mana_cost(), 62, "spirit healing synergy mana surcharge")
	_assert_eq(spell.calculate_damage(), 0, "healing spell deals no damage")
	_assert_eq(spell.calculate_healing(), 19, "healing synergy heal amount")


func _test_void_earth_gravity_spell_behavior() -> void:
	var spell := SpellDefinition.new()
	spell.spell_name = "Singularity"
	spell.base_weights = {"Earth": 50.0, "Void": 50.0}
	spell.shape = "Sphere"
	spell.intensity = 5
	spell.spell_size = 4
	spell.has_pull = true
	spell.pull_strength = 3

	_assert_eq(spell.get_blend_key(), "Earth+Void", "gravity synergy blend key")
	_assert_eq(spell.get_base_display_name(), "Singularity", "gravity synergy display name")
	_assert_eq(spell.is_gravity_spell(), true, "earth void spell is gravity spell")
	_assert_almost_eq(spell.calculate_gravity_force(0.0, 10.0), 22.45, 0.001, "gravity force at center")
	_assert_almost_eq(spell.calculate_gravity_force(10.0, 10.0), 0.915, 0.001, "gravity force at edge")


func _test_solar_flare_damage_is_reduced_for_blind_spell() -> void:
	var spell := SpellDefinition.new()
	spell.spell_name = "Solar Flare"
	spell.base_weights = {"Fire": 50.0, "Light": 50.0}
	spell.shape = "Sphere"
	spell.intensity = 6
	spell.spell_size = 2
	spell.spell_speed = 3
	spell.burns = true

	_assert_eq(spell.get_base_display_name(), "Solar Flare", "solar flare display name")
	_assert_eq(spell.is_blind_spell(), true, "solar flare blinds")
	_assert_eq(spell.calculate_damage(), 12, "solar flare damage reduction")
	_assert_almost_eq(spell.calculate_blind_duration(), 2.12, 0.001, "solar flare blind duration")
	_assert_almost_eq(spell.calculate_blind_radius(), 9.52, 0.001, "solar flare blind radius")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_almost_eq(actual: float, expected: float, tolerance: float, label: String) -> void:
	if abs(actual - expected) > tolerance:
		_failures += 1
		push_error("%s: expected %s +/- %s, got %s" % [label, str(expected), str(tolerance), str(actual)])
