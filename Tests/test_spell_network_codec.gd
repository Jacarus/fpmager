extends SceneTree

const SpellNetworkCodecScript = preload("res://Scripts/SpellNetworkCodec.gd")


func _init() -> void:
	var spell := SpellDefinition.new()
	spell.spell_name = "Steam Push"
	spell.base_element = "Fire"
	spell.base_weights = {"Fire": 50.0, "Water": 50.0}
	spell.shape = "Sphere"
	spell.intensity = 7
	spell.spell_size = 3
	spell.spell_range = 4
	spell.spell_speed = 5
	spell.has_charging = true
	spell.burns = true
	spell.cools = true
	spell.pushes = true
	spell.blows = false
	spell.heals = false
	spell.has_density = true
	spell.density = 6
	spell.has_illusion = true
	spell.has_pull = true
	spell.pull_strength = 4

	var data := SpellNetworkCodecScript.to_dict(spell)
	_assert_eq(data["spell_name"], "Steam Push", "serializes spell name")
	_assert_eq(data["base_weights"], {"Fire": 50.0, "Water": 50.0}, "serializes base weights")
	_assert_eq(data["pull_strength"], 4, "serializes pull strength")

	var copy := SpellNetworkCodecScript.from_dict(data)
	_assert_eq(copy.spell_name, spell.spell_name, "round-trips spell name")
	_assert_eq(copy.base_element, spell.base_element, "round-trips base element")
	_assert_eq(copy.get_base_weights(), spell.get_base_weights(), "round-trips base weights")
	_assert_eq(copy.shape, spell.shape, "round-trips shape")
	_assert_eq(copy.intensity, spell.intensity, "round-trips intensity")
	_assert_eq(copy.spell_size, spell.spell_size, "round-trips size")
	_assert_eq(copy.spell_range, spell.spell_range, "round-trips range")
	_assert_eq(copy.spell_speed, spell.spell_speed, "round-trips speed")
	_assert_eq(copy.has_charging, spell.has_charging, "round-trips charging")
	_assert_eq(copy.burns, spell.burns, "round-trips burns")
	_assert_eq(copy.cools, spell.cools, "round-trips cools")
	_assert_eq(copy.pushes, spell.pushes, "round-trips pushes")
	_assert_eq(copy.blows, spell.blows, "round-trips blows")
	_assert_eq(copy.heals, spell.heals, "round-trips heals")
	_assert_eq(copy.has_density, spell.has_density, "round-trips density flag")
	_assert_eq(copy.density, spell.density, "round-trips density")
	_assert_eq(copy.has_illusion, spell.has_illusion, "round-trips illusion")
	_assert_eq(copy.has_pull, spell.has_pull, "round-trips pull flag")
	_assert_eq(copy.pull_strength, spell.pull_strength, "round-trips pull strength")

	var fallback := SpellNetworkCodecScript.from_dict({})
	_assert_eq(fallback.spell_name, "Network Spell", "uses default network spell name")
	_assert_eq(fallback.shape, "Sphere", "uses default shape")
	_assert_eq(fallback.intensity, 1, "uses default intensity")

	print("test_spell_network_codec: OK")
	quit(0)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])
		quit(1)
