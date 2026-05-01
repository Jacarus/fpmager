class_name SpellDefinition
extends Resource

const MAX_CREDITS := 100
const SIMPLE_THRESHOLD := 50
const BEAM_SPEED_COST_SCALE := 2.78
const MANA_COST_SCALE := 0.6
const MIN_MANA_COST := 5
const SPIRIT_MANA_SURCHARGE := 1.65
const BEAM_MANA_PER_SECOND_SCALE := 0.42
const CHARGE_MANA_BONUS_SCALE := 0.35
const BASE_DAMAGE_MULTIPLIER := 5.0
const BEAM_DAMAGE_TICK_SCALE := 0.35
const BASE_PUSH_MULTIPLIER := 3.2
const BASE_GRAVITY_MULTIPLIER := 4.6
const BASE_BLIND_DURATION := 1.4
const BASE_BLIND_RADIUS := 5.0
const SOLAR_FLARE_DAMAGE_SCALE := 0.30
const KNOWN_SYNERGIES := {
	"Air+Fire": "Wildfire",
	"Fire+Water": "Steam",
	"Earth+Fire": "Lava",
	"Fire+Light": "Solar Flare",
	"Air+Water": "Frost",
	"Earth+Water": "Mud",
	"Spirit+Water": "Healing Mist",
	"Air+Light": "Laser",
	"Air+Earth": "Dust Storm",
	"Earth+Light": "Crystal",
	"Light+Spirit": "Radiant Aura",
	"Earth+Void": "Singularity",
}
const COMPLEX_EFFECTS := {
	"Fire+Water": {
		"name": "Steam",
		"description": "Scalding vapor cloud. Burns enemies in an area over time and obscures vision.",
		"stats": {"Burn": 7, "Force": 1, "Area": 8, "Control": 4, "Support": 0},
	},
	"Earth+Fire": {
		"name": "Lava",
		"description": "Molten mass. Slow, heavy impact with lingering ground burn.",
		"stats": {"Burn": 9, "Force": 6, "Area": 5, "Control": 3, "Support": 0},
	},
	"Air+Fire": {
		"name": "Wildfire",
		"description": "Fast spreading flame. Lower impact, high spread and repeated burn ticks.",
		"stats": {"Burn": 8, "Force": 2, "Area": 7, "Control": 2, "Support": 0},
	},
	"Fire+Light": {
		"name": "Solar Flare",
		"description": "Radiant heat burst. Applies burn and blinding glare.",
		"stats": {"Burn": 7, "Force": 1, "Area": 5, "Control": 8, "Support": 0},
	},
	"Air+Water": {
		"name": "Frost",
		"description": "Freezing mist. Chills and can freeze wet targets.",
		"stats": {"Burn": 0, "Force": 2, "Area": 6, "Control": 8, "Support": 0},
	},
	"Earth+Water": {
		"name": "Mud",
		"description": "Dense mire. Snares targets and softens movement in an area.",
		"stats": {"Burn": 0, "Force": 4, "Area": 5, "Control": 8, "Support": 0},
	},
	"Spirit+Water": {
		"name": "Healing Mist",
		"description": "Restorative vapor. Heals allies over time in an area.",
		"stats": {"Burn": 0, "Force": 0, "Area": 7, "Control": 1, "Support": 9},
	},
	"Air+Light": {
		"name": "Laser",
		"description": "Focused radiant line. Extreme speed and range with blinding precision.",
		"stats": {"Burn": 4, "Force": 1, "Area": 1, "Control": 7, "Support": 0},
	},
	"Air+Earth": {
		"name": "Dust Storm",
		"description": "Abrasive dust cloud. Blinds and deals chip damage across an area.",
		"stats": {"Burn": 0, "Force": 3, "Area": 8, "Control": 8, "Support": 0},
	},
	"Earth+Light": {
		"name": "Crystal",
		"description": "Refracting solid magic. Defensive refraction and piercing shard behavior.",
		"stats": {"Burn": 1, "Force": 6, "Area": 3, "Control": 5, "Support": 3},
	},
	"Light+Spirit": {
		"name": "Radiant Aura",
		"description": "Protective radiance. Passive healing with illusion-breaking light.",
		"stats": {"Burn": 1, "Force": 0, "Area": 6, "Control": 4, "Support": 9},
	},
	"Earth+Void": {
		"name": "Singularity",
		"description": "Crushing inward gravity. Pulls targets into a dense impact point.",
		"stats": {"Burn": 0, "Force": 9, "Area": 5, "Control": 9, "Support": 0},
	},
}
const VOID_COMPLEX_EFFECT := {
	"name": "Null Rift",
	"description": "Hostile void blend. Consumes the other base and creates a cold destabilizing field.",
	"stats": {"Burn": 0, "Force": 7, "Area": 5, "Control": 8, "Support": 0},
}

@export var spell_name: String = "New Spell"
@export var base_element: String = ""
@export var base_weights: Dictionary = {}
@export var shape: String = ""
@export var intensity: int = 1
@export var spell_size: int = 1
@export var spell_range: int = 1
@export var spell_speed: int = 1
@export var has_charging: bool = false

@export var burns: bool = false
@export var cools: bool = false
@export var pushes: bool = false
@export var blows: bool = false
@export var heals: bool = false
@export var has_density: bool = false
@export var density: int = 1
@export var has_illusion: bool = false
@export var has_pull: bool = false
@export var pull_strength: int = 1


func calculate_credits() -> int:
	var cost := 0
	var base_count := get_base_elements().size()
	cost += base_count * 10
	match shape:
		"Beam": cost += 15
		"Sphere": cost += 10
		"Wall": cost += 12
	if has_charging and shape == "Sphere":
		cost += 5
	cost += (intensity - 1) * 3
	cost += (spell_size - 1) * 2
	if shape == "Beam":
		cost += int(pow(float(spell_speed - 1), 1.5) * BEAM_SPEED_COST_SCALE)
	elif shape == "Sphere":
		cost += (spell_speed - 1) * 2
	if shape == "Beam":
		cost += int(pow(float(spell_range - 1), 1.5) * 3)
	else:
		cost += (spell_range - 1) * 2
	if burns: cost += 5
	if cools: cost += 4
	if pushes: cost += 4
	if blows: cost += 4
	if is_healing_spell(): cost += 8
	if has_density: cost += 3 + (density - 1) * 2
	if has_illusion: cost += 10
	if has_pull: cost += 4 + (pull_strength - 1) * 2
	if base_count == 2:
		cost = int(ceil(cost * 1.15))
	elif base_count == 3:
		cost = int(ceil(cost * 1.35))
	if is_known_synergy():
		cost = int(ceil(cost * 0.9))
	return cost


func calculate_mana_cost() -> int:
	var mana_cost := float(calculate_credits()) * MANA_COST_SCALE
	if get_base_elements().has("Spirit"):
		mana_cost *= SPIRIT_MANA_SURCHARGE
	return max(MIN_MANA_COST, int(ceil(mana_cost)))


func calculate_beam_mana_per_second() -> float:
	return max(2.0, float(calculate_mana_cost()) * BEAM_MANA_PER_SECOND_SCALE)


func calculate_charged_mana_cost(charged_size: int) -> int:
	var extra_size: int = max(0, charged_size - spell_size)
	var charge_multiplier := 1.0 + float(extra_size) * CHARGE_MANA_BONUS_SCALE
	return max(MIN_MANA_COST, int(ceil(float(calculate_mana_cost()) * charge_multiplier)))


func calculate_damage(is_beam_tick: bool = false) -> int:
	if is_healing_spell():
		return 0
	var base_damage := float(intensity) * BASE_DAMAGE_MULTIPLIER
	base_damage += float(spell_size - 1) * 2.5
	base_damage += float(spell_speed - 1) * (1.4 if shape != "Wall" else 0.4)
	base_damage += float(max(0, get_base_elements().size() - 1)) * 2.0
	if burns:
		base_damage += 3.0
	if has_density:
		base_damage += float(density) * 1.2
	if has_pull:
		base_damage += float(pull_strength) * 0.8
	if get_blend_key() == "Fire+Light":
		base_damage *= SOLAR_FLARE_DAMAGE_SCALE
	if shape == "Beam" or is_beam_tick:
		base_damage *= BEAM_DAMAGE_TICK_SCALE
	elif shape == "Wall":
		base_damage *= 0.55
	return max(1, int(round(base_damage)))


func calculate_healing(is_beam_tick: bool = false) -> int:
	if not is_healing_spell():
		return 0
	var weights := get_base_weights()
	var spirit_weight := float(weights.get("Spirit", 0)) / 100.0
	var support_bonus := 1.0
	var effect := get_complex_effect()
	if not effect.is_empty():
		var stats: Dictionary = effect["stats"]
		support_bonus += float(stats.get("Support", 0)) * 0.08
	var heal_amount := (float(intensity) * 4.0 + float(spell_size) * 2.0) * maxf(0.5, spirit_weight) * support_bonus
	if is_beam_tick:
		heal_amount *= BEAM_DAMAGE_TICK_SCALE
	return max(1, int(round(heal_amount)))


func calculate_push_force(is_beam_tick: bool = false) -> float:
	if not is_push_spell():
		return 0.0
	var weights := get_base_weights()
	var water_weight := float(weights.get("Water", 0)) / 100.0
	var force := float(intensity) * BASE_PUSH_MULTIPLIER
	force += float(spell_size) * 1.8
	force += float(spell_speed) * 1.1
	force *= maxf(0.35, water_weight)
	if is_beam_tick:
		force *= 0.45
	if shape == "Wall":
		force *= 0.35
	return force


func calculate_gravity_force(distance_from_center: float, radius: float, is_beam_tick: bool = false) -> float:
	if not is_gravity_spell():
		return 0.0
	var weights := get_base_weights()
	var void_weight := float(weights.get("Void", 0)) / 100.0
	var earth_weight := float(weights.get("Earth", 0)) / 100.0
	var gravity_weight := maxf(0.35, (void_weight + earth_weight) * 0.5)
	var pull_value := float(pull_strength if has_pull else 1)
	var force := float(intensity) * BASE_GRAVITY_MULTIPLIER
	force += float(spell_size) * 2.1
	force += pull_value * 2.4
	var effect := get_complex_effect()
	if not effect.is_empty():
		var stats: Dictionary = effect["stats"]
		force += float(stats.get("Control", 0)) * 0.7
	force *= gravity_weight
	var safe_radius := maxf(radius, 0.1)
	var normalized_distance := clampf(distance_from_center / safe_radius, 0.0, 1.0)
	force *= exp(-3.2 * normalized_distance)
	if is_beam_tick:
		force *= 0.45
	if shape == "Wall":
		force *= 0.55
	return force


func calculate_blind_duration(is_beam_tick: bool = false) -> float:
	if not is_blind_spell():
		return 0.0
	var weights := get_base_weights()
	var light_weight := float(weights.get("Light", 0)) / 100.0
	var duration := BASE_BLIND_DURATION
	duration += float(intensity) * 0.22
	duration += float(spell_size) * 0.12
	duration *= maxf(0.45, light_weight)
	if has_illusion:
		duration += 0.65
	var effect := get_complex_effect()
	if not effect.is_empty():
		var stats: Dictionary = effect["stats"]
		duration += float(stats.get("Control", 0)) * 0.08
	if is_beam_tick:
		duration *= 0.45
	return clampf(duration, 0.4, 4.5)


func calculate_blind_radius() -> float:
	if not is_blind_spell():
		return 0.0
	var radius := BASE_BLIND_RADIUS
	radius += float(spell_size) * 0.75
	radius += float(spell_range) * 0.18
	var effect := get_complex_effect()
	if not effect.is_empty():
		var stats: Dictionary = effect["stats"]
		radius += float(stats.get("Area", 0)) * 0.28
		radius += float(stats.get("Control", 0)) * 0.18
	return radius


func is_push_spell() -> bool:
	return pushes and get_base_elements().has("Water")


func is_gravity_spell() -> bool:
	var elements := get_base_elements()
	return elements.has("Void") and elements.has("Earth")


func is_blind_spell() -> bool:
	var elements := get_base_elements()
	if not elements.has("Light"):
		return false
	if has_illusion:
		return true
	var key := get_blend_key()
	return key == "Fire+Light" or key == "Air+Light" or elements.size() == 1


func is_healing_spell() -> bool:
	if heals:
		return true
	var elements := get_base_elements()
	if not elements.has("Spirit") or elements.has("Void"):
		return false
	if elements.size() == 1:
		return true
	var effect := get_complex_effect()
	if effect.is_empty():
		return false
	var stats: Dictionary = effect["stats"]
	return int(stats.get("Support", 0)) >= 7


func is_valid() -> bool:
	return not get_base_elements().is_empty() and shape != ""


func get_spell_type() -> String:
	return "Simple" if calculate_credits() < SIMPLE_THRESHOLD else "Complex"


func get_base_weights() -> Dictionary:
	if not base_weights.is_empty():
		return base_weights
	if base_element != "":
		return {base_element: 100}
	return {}


func get_base_elements() -> Array[String]:
	var elements: Array[String] = []
	for element in get_base_weights().keys():
		elements.append(str(element))
	return elements


func get_dominant_base() -> String:
	var best_element := base_element
	var best_weight := -1
	for element in get_base_weights().keys():
		var weight := int(get_base_weights()[element])
		if weight > best_weight:
			best_element = str(element)
			best_weight = weight
	return best_element


func get_blend_key() -> String:
	var elements := get_base_elements()
	elements.sort()
	return "+".join(elements)


func is_known_synergy() -> bool:
	return KNOWN_SYNERGIES.has(get_blend_key()) or get_base_elements().has("Void") and get_base_elements().size() > 1


func get_base_display_name() -> String:
	var elements := get_base_elements()
	if elements.is_empty():
		return ""
	if elements.size() == 1:
		return elements[0]
	var key := get_blend_key()
	if COMPLEX_EFFECTS.has(key):
		return COMPLEX_EFFECTS[key]["name"]
	if elements.has("Void"):
		var non_void: Array[String] = []
		for element in elements:
			if element != "Void":
				non_void.append(element)
		non_void.sort()
		return "Void-" + non_void[0] if not non_void.is_empty() else "Void"
	elements.sort()
	return " ".join(elements)


func get_complex_effect() -> Dictionary:
	var elements := get_base_elements()
	if elements.size() <= 1:
		return {}
	var key := get_blend_key()
	if COMPLEX_EFFECTS.has(key):
		return COMPLEX_EFFECTS[key]
	if elements.has("Void"):
		return VOID_COMPLEX_EFFECT
	return {
		"name": get_base_display_name(),
		"description": "Unstable hybrid spell. Uses blended properties to create a custom mixed effect.",
		"stats": {"Burn": 2, "Force": 2, "Area": 4, "Control": 4, "Support": 1},
	}
