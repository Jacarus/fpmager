class_name SpellNetworkCodec
extends RefCounted


static func to_dict(spell: SpellDefinition) -> Dictionary:
	return {
		"spell_name": spell.spell_name,
		"base_element": spell.base_element,
		"base_weights": spell.get_base_weights(),
		"shape": spell.shape,
		"intensity": spell.intensity,
		"spell_size": spell.spell_size,
		"spell_range": spell.spell_range,
		"spell_speed": spell.spell_speed,
		"has_charging": spell.has_charging,
		"burns": spell.burns,
		"cools": spell.cools,
		"pushes": spell.pushes,
		"blows": spell.blows,
		"heals": spell.heals,
		"has_density": spell.has_density,
		"density": spell.density,
		"has_illusion": spell.has_illusion,
		"has_pull": spell.has_pull,
		"pull_strength": spell.pull_strength,
	}


static func from_dict(data: Dictionary) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = str(data.get("spell_name", "Network Spell"))
	spell.base_element = str(data.get("base_element", ""))
	spell.base_weights = (data.get("base_weights", {}) as Dictionary).duplicate()
	spell.shape = str(data.get("shape", "Sphere"))
	spell.intensity = int(data.get("intensity", 1))
	spell.spell_size = int(data.get("spell_size", 1))
	spell.spell_range = int(data.get("spell_range", 1))
	spell.spell_speed = int(data.get("spell_speed", 1))
	spell.has_charging = bool(data.get("has_charging", false))
	spell.burns = bool(data.get("burns", false))
	spell.cools = bool(data.get("cools", false))
	spell.pushes = bool(data.get("pushes", false))
	spell.blows = bool(data.get("blows", false))
	spell.heals = bool(data.get("heals", false))
	spell.has_density = bool(data.get("has_density", false))
	spell.density = int(data.get("density", 1))
	spell.has_illusion = bool(data.get("has_illusion", false))
	spell.has_pull = bool(data.get("has_pull", false))
	spell.pull_strength = int(data.get("pull_strength", 1))
	return spell
