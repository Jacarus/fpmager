extends Node3D

const BEAM_SOURCE_KEY := "npc:beam_test"
const BODY_COLOR := Color(0.08, 0.08, 0.1)
const BEAM_COLOR := Color(1.0, 0.38, 0.08)
const LABEL_COLOR := Color(1.0, 0.55, 0.28)
const BEAM_DIRECTION := Vector3.RIGHT

var _spell: SpellDefinition
var _beam_core: MeshInstance3D
var _beam_tip: MeshInstance3D
var _beam_light: OmniLight3D
var _label: Label3D
var _body: StaticBody3D
var _beam_impact_timer: float = 0.0


func _ready() -> void:
	_spell = _create_test_beam_spell()
	_build_body()
	_build_beam_visual()


func _process(delta: float) -> void:
	if _beam_impact_timer > 0.0:
		_beam_impact_timer -= delta
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	_update_beam()


func _exit_tree() -> void:
	var world := get_tree().current_scene
	if world != null and world.has_method("unregister_beam_segment"):
		world.unregister_beam_segment(BEAM_SOURCE_KEY)


func _build_body() -> void:
	_body = StaticBody3D.new()
	add_child(_body)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.4
	col.shape = shape
	col.position.y = 0.7
	_body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.34
	mesh.height = 1.4
	mesh_inst.mesh = mesh
	mesh_inst.position.y = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BODY_COLOR
	mat.emission_enabled = true
	mat.emission = BEAM_COLOR
	mat.emission_energy_multiplier = 0.18
	mesh_inst.material_override = mat
	_body.add_child(mesh_inst)

	_label = Label3D.new()
	_label.text = "BEAM TEST"
	_label.position = Vector3(0.0, 1.85, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 34
	_label.modulate = LABEL_COLOR
	add_child(_label)


func _build_beam_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BEAM_COLOR
	mat.emission_enabled = true
	mat.emission = BEAM_COLOR
	mat.emission_energy_multiplier = 2.0

	_beam_core = MeshInstance3D.new()
	_beam_core.mesh = CylinderMesh.new()
	_beam_core.material_override = mat
	add_child(_beam_core)

	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.18
	tip_mesh.height = 0.36
	_beam_tip = MeshInstance3D.new()
	_beam_tip.mesh = tip_mesh
	_beam_tip.material_override = mat
	add_child(_beam_tip)

	_beam_light = OmniLight3D.new()
	_beam_light.light_color = BEAM_COLOR
	_beam_light.light_energy = 1.6
	_beam_light.omni_range = 4.0
	add_child(_beam_light)


func _update_beam() -> void:
	if _spell == null or _beam_core == null:
		return
	var origin := global_position + Vector3(0.0, 1.2, 0.0)
	var direction := global_transform.basis * BEAM_DIRECTION
	direction = direction.normalized()
	var max_distance := 7.0 + _spell.spell_range * 3.0
	var target := origin + direction * max_distance

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [_body] if _body != null else []
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_target := target
	var hit_normal := Vector3.UP
	var hit_collider: Object = null
	if not hit.is_empty():
		hit_target = hit["position"] as Vector3
		hit_normal = hit["normal"] as Vector3
		hit_collider = hit.get("collider")
		target = hit_target

	var blocked_by_spell := false
	var world := get_tree().current_scene
	if world != null and world.has_method("resolve_beam_segment") and (multiplayer.multiplayer_peer == null or multiplayer.is_server()):
		var result: Dictionary = world.resolve_beam_segment(BEAM_SOURCE_KEY, _spell, origin, target, self)
		target = result.get("target", target) as Vector3
		blocked_by_spell = bool(result.get("blocked", false))
	if not blocked_by_spell and hit_collider != null and origin.distance_to(target) + 0.05 >= origin.distance_to(hit_target):
		_apply_beam_hit(hit_collider, hit_target, hit_normal)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_client_update_test_beam.rpc(origin, target)

	_apply_beam_transform(origin, target)


@rpc("authority", "unreliable")
func _client_update_test_beam(origin: Vector3, target: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if multiplayer.is_server():
		return
	_apply_beam_transform(origin, target)


func _apply_beam_transform(origin: Vector3, target: Vector3) -> void:
	var length := maxf(0.1, origin.distance_to(target))
	var midpoint := origin.lerp(target, 0.5)
	var thickness := 0.08 + (_spell.spell_size - 1) * 0.025
	var mesh := _beam_core.mesh as CylinderMesh
	mesh.top_radius = thickness
	mesh.bottom_radius = thickness
	mesh.height = length
	_beam_core.global_position = midpoint
	_beam_core.look_at(target, Vector3.UP)
	_beam_core.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.14
	_beam_core.scale = Vector3(pulse, 1.0, pulse)
	_beam_tip.global_position = target
	_beam_tip.scale = Vector3.ONE * (0.7 + thickness * 4.0)
	_beam_light.global_position = target


func _create_test_beam_spell() -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = "Test Fire Beam"
	spell.base_element = "Fire"
	spell.base_weights = {"Fire": 100}
	spell.shape = "Beam"
	spell.intensity = 3
	spell.spell_size = 3
	spell.spell_range = 8
	spell.spell_speed = 8
	spell.burns = true
	return spell


func _apply_beam_hit(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _beam_impact_timer > 0.0:
		return
	var damageable := _find_damageable_node(collider)
	if damageable == null:
		return
	damageable.apply_spell_hit(_spell, hit_position, hit_normal, true)
	_beam_impact_timer = 0.35


func _find_damageable_node(value: Object) -> Node:
	var node := value as Node
	while node != null:
		if node.has_method("apply_spell_hit"):
			return node
		node = node.get_parent()
	return null
