extends SceneTree

const BasicCasterScript = preload("res://Scenes/NPC/BasicCaster.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "BurnStatusTest"
	get_root().add_child(root)
	var caster := BasicCasterScript.new()
	root.add_child(caster)

	var burn_spell := _make_spell(true)
	caster.apply_spell_hit(burn_spell, Vector3.ZERO, Vector3.UP, true)
	var health_after_contact: int = caster._health
	_assert_eq(health_after_contact < BasicCasterScript.MAX_HEALTH, true, "contact applies active damage")
	_assert_eq(caster._burn_timer > 0.0, true, "contact applies burn status")

	caster._tick_burn_status(BasicCasterScript.BURN_TICK_INTERVAL)
	_assert_eq(caster._health < health_after_contact, true, "burn ticks after contact ends")
	var health_after_burn: int = caster._health

	var non_burn_spell := _make_spell(false)
	caster.apply_spell_hit(non_burn_spell, Vector3.ZERO, Vector3.UP, true)
	_assert_eq(caster._burn_timer > 0.0, true, "non-burn contact does not clear existing burn")

	var water_spell := _make_spell(false)
	water_spell.base_element = "Water"
	water_spell.base_weights = {"Water": 100}
	water_spell.cools = true
	caster.apply_spell_hit(water_spell, Vector3.ZERO, Vector3.UP, true)
	_assert_eq(caster._burn_timer, 0.0, "cooling contact clears burn")
	var health_after_cooling: int = caster._health
	caster._tick_burn_status(BasicCasterScript.BURN_TICK_INTERVAL)
	_assert_eq(caster._health, health_after_cooling, "cleared burn does not tick")
	_assert_eq(health_after_cooling <= health_after_burn, true, "cooling hit may deal active damage only once")

	print("test_burn_status: OK")
	root.queue_free()
	quit(0)


func _make_spell(burns: bool) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = "Burn Test" if burns else "Non Burn Test"
	spell.base_element = "Fire"
	spell.base_weights = {"Fire": 100}
	spell.shape = "Sphere"
	spell.intensity = 4
	spell.spell_size = 3
	spell.spell_range = 3
	spell.spell_speed = 2
	spell.burns = burns
	return spell


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])
		quit(1)
