extends RigidBody3D

const PUSH_IMPULSE_MULTIPLIER := 2.4
const WATER_TEST_IMPULSE := 10.0
const DIRECT_GRAVITY_RADIUS := 3.0
const GRAVITY_IMPULSE_MULTIPLIER := 1.7
const NETWORK_SYNC_RATE := 0.05

var _label: Label3D
var _sync_timer: float = 0.0


func _ready() -> void:
	mass = 1.2
	linear_damp = 0.45
	angular_damp = 0.6
	can_sleep = false
	if _is_network_client():
		freeze = true
	_build_body()


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if _is_network_client():
		return
	if not multiplayer.is_server():
		return
	_sync_timer -= delta
	if _sync_timer > 0.0:
		return
	_sync_timer = NETWORK_SYNC_RATE
	var world := get_tree().current_scene
	if world != null and world.has_method("broadcast_push_test_target_state"):
		world.broadcast_push_test_target_state(global_position, global_rotation, linear_velocity, angular_velocity)
		return
	_client_receive_state.rpc(global_position, global_rotation, linear_velocity, angular_velocity)


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape = shape
	add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.55, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.04, 0.25, 0.55)
	mat.emission_energy_multiplier = 0.35
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	_label = Label3D.new()
	_label.text = "PUSH TEST"
	_label.position = Vector3(0.0, 0.9, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.modulate = Color(0.7, 0.9, 1.0)
	add_child(_label)


func apply_spell_hit(spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool = false) -> void:
	if spell == null:
		return
	if _is_network_client():
		return
	_apply_gravity_pull(hit_position, spell, DIRECT_GRAVITY_RADIUS, is_beam_tick)
	if not spell.get_base_elements().has("Water"):
		return
	var force := maxf(WATER_TEST_IMPULSE, spell.calculate_push_force(is_beam_tick) * PUSH_IMPULSE_MULTIPLIER)

	var push_dir := global_position - hit_position
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.01:
		push_dir = -hit_normal
	push_dir.y = 0.18
	if push_dir.length_squared() < 0.01:
		push_dir = -global_basis.z

	var impulse := push_dir.normalized() * force
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3.UP.cross(impulse) * 0.18)


func apply_gravity_pull(center: Vector3, spell: SpellDefinition, radius: float, is_beam_tick: bool = false) -> void:
	if spell == null:
		return
	if _is_network_client():
		return
	_apply_gravity_pull(center, spell, radius, is_beam_tick)


func _apply_gravity_pull(center: Vector3, spell: SpellDefinition, radius: float, is_beam_tick: bool) -> void:
	var pull_dir := center - global_position
	pull_dir.y = 0.0
	var distance := pull_dir.length()
	if distance < 0.05:
		return
	var force := spell.calculate_gravity_force(distance, radius, is_beam_tick) * GRAVITY_IMPULSE_MULTIPLIER
	if force <= 0.0:
		return
	apply_central_impulse(pull_dir.normalized() * force)


@rpc("any_peer", "unreliable")
func _client_receive_state(pos: Vector3, rot: Vector3, lin_vel: Vector3, ang_vel: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if multiplayer.is_server():
		return
	global_position = pos
	global_rotation = rot
	linear_velocity = lin_vel
	angular_velocity = ang_vel


func _is_network_client() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.is_server()
