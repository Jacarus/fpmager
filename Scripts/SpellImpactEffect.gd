class_name SpellImpactEffect
extends Node3D

const ELEMENT_COLORS: Dictionary = {
	"Fire": Color(1.0, 0.35, 0.05),
	"Water": Color(0.1, 0.55, 1.0),
	"Air": Color(0.75, 0.92, 1.0),
	"Spirit": Color(0.72, 0.3, 1.0),
	"Earth": Color(0.6, 0.4, 0.15),
	"Light": Color(1.0, 1.0, 0.35),
	"Void": Color(0.45, 0.1, 0.65),
}

var _spell: SpellDefinition
var _age: float = 0.0
var _lifetime: float = 1.6
var _radius: float = 1.0
var _damage_tick_timer: float = 0.2
var _damage_tick_interval: float = 0.45
var _blind_applied: bool = false
var _visual_only: bool = false
var _source: Node
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _light: OmniLight3D
var _label: Label3D


static func estimate_lifetime(spell: SpellDefinition) -> float:
	if spell == null:
		return 1.2
	var effect := spell.get_complex_effect()
	if effect.is_empty():
		return 1.2
	var stats: Dictionary = effect["stats"]
	var lifetime := 1.1 + float(stats.get("Area", 3)) * 0.12 + float(stats.get("Control", 0)) * 0.04
	if spell.is_blind_spell():
		lifetime = maxf(lifetime, 0.9)
	return lifetime


func initialize(spell: SpellDefinition, impact_position: Vector3, normal: Vector3 = Vector3.UP, source: Node = null, initial_age: float = 0.0) -> void:
	_spell = spell
	_source = source
	_age = maxf(0.0, initial_age)
	global_position = impact_position + normal.normalized() * 0.04

	var effect := spell.get_complex_effect()
	var effect_name := spell.get_base_display_name()
	if not effect.is_empty():
		effect_name = str(effect["name"])

	_radius = _calculate_radius(spell, effect)
	_lifetime = _calculate_lifetime(effect)

	_material = StandardMaterial3D.new()
	var col := _get_spell_color(spell)
	_material.albedo_color = col
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = col
	_material.emission_energy_multiplier = 1.4 + spell.intensity * 0.15
	_material.roughness = 0.55

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _create_effect_mesh(effect_name)
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)

	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.0 + spell.intensity * 0.25
	_light.omni_range = _radius * 2.5
	add_child(_light)

	_label = Label3D.new()
	_label.text = effect_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = _radius * 0.75
	_label.modulate = Color(1.0, 0.95, 0.8, 0.9)
	_label.font_size = 22
	add_child(_label)


func set_visual_only(value: bool) -> void:
	_visual_only = value


func _process(delta: float) -> void:
	_age += delta
	_damage_tick_timer -= delta
	if not _visual_only and not _blind_applied and _spell != null and _spell.is_blind_spell():
		_blind_applied = true
		_apply_blind_flash()
	if not _visual_only and _damage_tick_timer <= 0.0:
		_damage_tick_timer = _damage_tick_interval
		_apply_area_spell_tick()

	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var expand := lerpf(0.25, 1.0, ease(t, -1.5))
	var fade := 1.0 - t

	if _mesh_instance != null:
		_mesh_instance.scale = Vector3.ONE * _radius * expand
	if _material != null:
		_material.albedo_color.a = fade * 0.55
		_material.emission_energy_multiplier = (1.0 + _spell.intensity * 0.18) * fade
	if _light != null:
		_light.light_energy = (1.2 + _spell.intensity * 0.25) * fade
	if _label != null:
		_label.modulate.a = fade
		_label.position.y = _radius * (0.65 + t * 0.45)

	if _age >= _lifetime:
		queue_free()


func _calculate_radius(spell: SpellDefinition, effect: Dictionary) -> float:
	var area_score := 3
	if not effect.is_empty():
		var stats: Dictionary = effect["stats"]
		area_score = int(stats.get("Area", area_score))
	var radius := 0.7 + spell.spell_size * 0.18 + area_score * 0.16
	if spell.is_gravity_spell():
		radius *= 2.2
	if spell.is_blind_spell():
		radius = maxf(radius, spell.calculate_blind_radius())
	return radius


func _calculate_lifetime(effect: Dictionary) -> float:
	return estimate_lifetime(_spell)


func _apply_blind_flash() -> void:
	var duration := _spell.calculate_blind_duration(false)
	if duration <= 0.0:
		return
	for damageable in _get_damageable_nodes(get_tree().current_scene):
		var node_3d := damageable as Node3D
		if node_3d == null:
			continue
		if node_3d.global_position.distance_to(global_position) > _radius:
			continue
		if damageable.has_method("apply_blind"):
			damageable.apply_blind(duration)


func _apply_area_spell_tick() -> void:
	if _spell == null:
		return
	var is_healing := _spell.is_healing_spell()
	for damageable in _get_damageable_nodes(get_tree().current_scene):
		var node_3d := damageable as Node3D
		if node_3d == null:
			continue
		var distance := node_3d.global_position.distance_to(global_position)
		if distance > _radius:
			continue
		if _spell.is_blind_spell() and damageable.has_method("apply_blind"):
			damageable.apply_blind(_spell.calculate_blind_duration(true))
		if damageable.has_method("apply_gravity_pull"):
			damageable.apply_gravity_pull(global_position, _spell, _radius, true)
		damageable.apply_spell_hit(_spell, global_position, Vector3.UP, true)


func _get_damageable_nodes(root: Node) -> Array[Node]:
	var results: Array[Node] = []
	if root == null:
		return results
	_collect_damageable_nodes(root, results)
	return results


func _collect_damageable_nodes(node: Node, results: Array[Node]) -> void:
	if node.has_method("apply_spell_hit"):
		results.append(node)
	for child in node.get_children():
		_collect_damageable_nodes(child, results)


func _create_effect_mesh(effect_name: String) -> Mesh:
	match effect_name:
		"Lava", "Mud", "Singularity":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 1.0
			mesh.bottom_radius = 1.0
			mesh.height = 0.12
			return mesh
		"Laser", "Solar Flare":
			var mesh := SphereMesh.new()
			mesh.radius = 0.8
			mesh.height = 0.35
			return mesh
		_:
			var mesh := SphereMesh.new()
			mesh.radius = 0.75
			mesh.height = 1.5
			return mesh


func _get_spell_color(spell: SpellDefinition) -> Color:
	var weights := spell.get_base_weights()
	if weights.is_empty():
		return ELEMENT_COLORS.get(spell.base_element, Color(0.6, 0.4, 1.0))
	var total_weight := 0.0
	var color := Color.BLACK
	for element in weights.keys():
		var weight := float(weights[element])
		total_weight += weight
		color += ELEMENT_COLORS.get(str(element), Color(0.6, 0.4, 1.0)) * weight
	if total_weight <= 0.0:
		return Color(0.6, 0.4, 1.0)
	return color / total_weight
