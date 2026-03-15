extends Node3D

## Projectile singleton. Manages all projectile visuals and traveling projectiles
## using MultiMeshInstance3D for performance.
##
## Usage:
##   Projectile.fire(Enums.Projectile.LASER, from, to, { "damage": 1.0, "target_unit": unit })
##
## Config dictionary keys:
##   damage         : float   – damage to apply (default 0.0)
##   target_unit    : Node3D  – target reference (required for homing and damage)
##   homing         : bool    – track target each frame (default true, forced false when arc > 0)
##   arc            : float   – parabolic arc height (default 0.0 = straight line)
##   speed          : float   – travel speed in m/s (default 12.0)
##   color          : Color   – visual color (default per type)
##   size           : float   – visual scale multiplier (default 1.0)
##   laser_count    : int     – rapid-fire pulse count for LASER (default 1)
##   laser_width    : float   – beam width for LASER (default 0.06)
##   laser_duration : float   – how long each pulse is visible (default 0.12)
##   sound_start    : AudioStream – sound played at fire position (optional)
##   sound_end      : AudioStream – sound played at impact position (optional; if omitted, no impact sound)
##   aoe_radius     : float   – area of effect radius; damages all enemies within range (default 0.0 = single target)

const LASER_SHADER = preload("res://source/match/units/projectiles/laser_beam.gdshader")
const IMPACT_SHADER = preload("res://source/match/units/projectiles/laser_impact.gdshader")

const SOUND_POOL_SIZE: int = 16

# ── active data ──────────────────────────────────────────────────────────────

var _lasers: Array[Dictionary] = []
var _traveling: Array[Dictionary] = []

# ── MultiMesh nodes ──────────────────────────────────────────────────────────

var _laser_mmi: MultiMeshInstance3D
var _cannon_mmi: MultiMeshInstance3D
var _rocket_mmi: MultiMeshInstance3D
var _bullets_mmi: MultiMeshInstance3D

# ── impact particles ─────────────────────────────────────────────────────────

var _impact_particles: GPUParticles3D

# ── audio pool ───────────────────────────────────────────────────────────────

var _audio_pool: Array[AudioStreamPlayer3D] = []
var _audio_pool_index: int = 0

# ── default visuals ──────────────────────────────────────────────────────────

var _laser_material: ShaderMaterial
var _cannon_material: StandardMaterial3D
var _rocket_material: StandardMaterial3D
var _bullets_material: StandardMaterial3D

# ── lifecycle ────────────────────────────────────────────────────────────────


func _ready() -> void:
	_setup_laser_multimesh()
	_setup_impact_particles()
	_setup_cannon_multimesh()
	_setup_rocket_multimesh()
	_setup_bullets_multimesh()
	_setup_audio_pool()


func _process(delta: float) -> void:
	_update_lasers(delta)
	_update_traveling(delta)


# ── public API ───────────────────────────────────────────────────────────────


func fire(type: Enums.Projectile, from: Vector3, to: Vector3, config: Dictionary = {}) -> void:
	match type:
		Enums.Projectile.LASER:
			_fire_laser(from, to, config)
		Enums.Projectile.CANNON:
			_fire_traveling(Enums.Projectile.CANNON, from, to, config)
		Enums.Projectile.ROCKET:
			_fire_traveling(Enums.Projectile.ROCKET, from, to, config)
		Enums.Projectile.BULLETS:
			_fire_traveling(Enums.Projectile.BULLETS, from, to, config)


# ── laser (instant hit, shader quad) ─────────────────────────────────────────


func _fire_laser(from: Vector3, to: Vector3, config: Dictionary) -> void:
	var target_unit: Node3D = config.get("target_unit")
	var damage: float = config.get("damage", 0.0)
	var aoe_radius: float = config.get("aoe_radius", 0.0)
	var source_player: Node = config.get("source_player")
	if damage > 0.0:
		_apply_damage(target_unit, to, damage, aoe_radius, source_player)

	_spawn_impact(to + Vector3(0, 0.15, 0), config.get("color", Color(0.3, 0.6, 1.0)))

	var sound_start: AudioStream = config.get("sound_start")
	if sound_start:
		_play_sound(sound_start, from)
	var sound_end: AudioStream = config.get("sound_end")
	if sound_end:
		_play_sound(sound_end, to)

	var laser_count: int = config.get("laser_count", 1)
	var duration: float = config.get("laser_duration", 0.25)
	var color: Color = config.get("color", Color(0.3, 0.6, 1.0))
	var width: float = config.get("laser_width", 0.15)

	for i in laser_count:
		var beam_from: Vector3 = from + Vector3(0, 0.15, 0)
		var beam_to: Vector3 = to + Vector3(0, 0.15, 0)
		(
			_lasers
			. append(
				{
					"from": beam_from,
					"to": beam_to,
					"color": color,
					"width": width,
					"duration": duration,
					"delay": i * 0.04,
					"elapsed": 0.0,
				}
			)
		)


func _update_lasers(delta: float) -> void:
	var i: int = _lasers.size() - 1
	while i >= 0:
		var l: Dictionary = _lasers[i]
		if l.delay > 0.0:
			l.delay -= delta
			i -= 1
			continue
		l.elapsed += delta
		if l.elapsed >= l.duration:
			_lasers.remove_at(i)
		i -= 1
	_rebuild_laser_multimesh()


func _rebuild_laser_multimesh() -> void:
	var visible_lasers: Array[Dictionary] = []
	for l: Dictionary in _lasers:
		if l.delay <= 0.0:
			visible_lasers.append(l)

	var mm: MultiMesh = _laser_mmi.multimesh
	if visible_lasers.size() == 0:
		mm.instance_count = 0
		return

	mm.instance_count = visible_lasers.size()
	for i: int in visible_lasers.size():
		var l: Dictionary = visible_lasers[i]
		var render_width: float = l.width * 4.0
		var t: Transform3D = _beam_transform(l.from, l.to, render_width)
		mm.set_instance_transform(i, t)
		var fade: float = 1.0 - clampf(l.elapsed / l.duration, 0.0, 1.0)
		var c: Color = l.color
		c.a = fade
		mm.set_instance_custom_data(i, c)


# ── traveling projectiles ────────────────────────────────────────────────────


func _fire_traveling(
	type: Enums.Projectile, from: Vector3, to: Vector3, config: Dictionary
) -> void:
	var homing: bool = config.get("homing", true)
	var arc: float = config.get("arc", 0.0)
	if arc > 0.0:
		homing = false

	var total_dist: float = from.distance_to(to)
	if total_dist < 0.01:
		total_dist = 0.01

	(
		_traveling
		. append(
			{
				"type": type,
				"from": from,
				"to": to,
				"current_pos": from,
				"target_unit": config.get("target_unit"),
				"source_player": config.get("source_player"),
				"speed": config.get("speed", 12.0),
				"arc": arc,
				"homing": homing,
				"damage": config.get("damage", 0.0),
				"aoe_radius": config.get("aoe_radius", 0.0),
				"progress": 0.0,
				"total_distance": total_dist,
				"color": config.get("color", _default_color_for(type)),
				"size": config.get("size", 1.0),
				"sound_end": config.get("sound_end"),
			}
		)
	)

	var sound_start: AudioStream = config.get("sound_start")
	if sound_start:
		_play_sound(sound_start, from)


func _update_traveling(delta: float) -> void:
	var i: int = _traveling.size() - 1
	while i >= 0:
		var p: Dictionary = _traveling[i]
		var hit: bool = false

		if (
			p.homing
			and p.target_unit
			and is_instance_valid(p.target_unit)
			and p.target_unit.is_inside_tree()
		):
			p.to = p.target_unit.global_position

		if p.arc > 0.0:
			# Progress-based movement for arc (non-homing)
			var travel_time: float = p.total_distance / p.speed
			p.progress += delta / travel_time
			var t: float = clampf(p.progress, 0.0, 1.0)
			p.current_pos = p.from.lerp(p.to, t)
			p.current_pos.y += sin(t * PI) * p.arc
			hit = t >= 1.0
		else:
			# Direction-based movement (homing or straight)
			var dir: Vector3 = p.to - p.current_pos
			var dist: float = dir.length()
			var step: float = p.speed * delta
			if step >= dist:
				p.current_pos = p.to
				hit = true
			else:
				p.current_pos += dir.normalized() * step

		if hit:
			_on_projectile_arrival(p)
			_traveling.remove_at(i)

		i -= 1

	_rebuild_traveling_multimeshes()


func _on_projectile_arrival(p: Dictionary) -> void:
	var damage: float = p.get("damage", 0.0)
	if damage > 0.0:
		_apply_damage(
			p.get("target_unit"),
			p.current_pos,
			damage,
			p.get("aoe_radius", 0.0),
			p.get("source_player")
		)
	var sound_end: AudioStream = p.get("sound_end")
	if sound_end:
		_play_sound(sound_end, p.current_pos)


func _apply_damage(
	primary_target,
	impact_pos: Vector3,
	damage: float,
	aoe_radius: float,
	source_player = null,
) -> void:
	if aoe_radius > 0.0:
		for unit: Node3D in get_tree().get_nodes_in_group("units"):
			if not is_instance_valid(unit) or unit.hp <= 0:
				continue
			if source_player and unit.player == source_player:
				continue
			var dist: float = unit.global_position.distance_to(impact_pos)
			if dist <= aoe_radius:
				unit.hp -= damage
				MatchSignals.unit_damaged.emit(unit)
	else:
		if primary_target and is_instance_valid(primary_target) and damage > 0.0:
			primary_target.hp -= damage
			MatchSignals.unit_damaged.emit(primary_target)


func _rebuild_traveling_multimeshes() -> void:
	_rebuild_type_multimesh(_cannon_mmi, Enums.Projectile.CANNON, 0.08)
	_rebuild_type_multimesh(_rocket_mmi, Enums.Projectile.ROCKET, 0.05)
	_rebuild_type_multimesh(_bullets_mmi, Enums.Projectile.BULLETS, 0.03)


func _rebuild_type_multimesh(
	mmi: MultiMeshInstance3D, type: Enums.Projectile, base_scale: float
) -> void:
	var subset: Array[Dictionary] = []
	for p: Dictionary in _traveling:
		if p.type == type:
			subset.append(p)

	var mm: MultiMesh = mmi.multimesh
	if subset.size() == 0:
		mm.instance_count = 0
		return

	mm.instance_count = subset.size()
	for i: int in subset.size():
		var p: Dictionary = subset[i]
		var dir: Vector3 = (p.to - p.current_pos).normalized()
		if dir.is_zero_approx():
			dir = Vector3.FORWARD
		var t: Transform3D = Transform3D()
		t = (
			t.looking_at(dir, Vector3.UP)
			if not dir.is_equal_approx(Vector3.UP)
			else t.looking_at(dir, Vector3.FORWARD)
		)
		t.origin = p.current_pos
		var s: float = base_scale * p.size
		t.basis = t.basis.scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, t)


# ── setup helpers ────────────────────────────────────────────────────────────


func _setup_laser_multimesh() -> void:
	_laser_material = ShaderMaterial.new()
	_laser_material.shader = LASER_SHADER

	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = 0

	_laser_mmi = MultiMeshInstance3D.new()
	_laser_mmi.multimesh = mm
	_laser_mmi.material_override = _laser_material
	_laser_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser_mmi.extra_cull_margin = 10000.0
	add_child(_laser_mmi)


func _setup_impact_particles() -> void:
	_impact_particles = GPUParticles3D.new()
	_impact_particles.emitting = false
	_impact_particles.amount = 12
	_impact_particles.lifetime = 0.4
	_impact_particles.one_shot = true
	_impact_particles.explosiveness = 1.0
	_impact_particles.fixed_fps = 0

	var particle_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0.0, 1.0, 0.0)
	particle_mat.spread = 90.0
	particle_mat.initial_velocity_min = 1.0
	particle_mat.initial_velocity_max = 3.0
	particle_mat.gravity = Vector3(0.0, -4.0, 0.0)
	particle_mat.scale_min = 0.15
	particle_mat.scale_max = 0.35
	particle_mat.color = Color(0.3, 0.6, 1.0, 1.0)

	var fade_curve: CurveTexture = CurveTexture.new()
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	fade_curve.curve = curve
	particle_mat.alpha_curve = fade_curve

	_impact_particles.process_material = particle_mat

	var impact_mesh: QuadMesh = QuadMesh.new()
	impact_mesh.size = Vector2(0.3, 0.3)
	var impact_draw_mat: ShaderMaterial = ShaderMaterial.new()
	impact_draw_mat.shader = IMPACT_SHADER
	impact_draw_mat.set_shader_parameter("spark_color", Color(0.3, 0.6, 1.0, 1.0))
	impact_draw_mat.set_shader_parameter("intensity", 4.0)
	impact_mesh.material = impact_draw_mat
	_impact_particles.draw_pass_1 = impact_mesh

	_impact_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_impact_particles)


func _spawn_impact(pos: Vector3, color: Color) -> void:
	_impact_particles.global_position = pos
	var mat: ParticleProcessMaterial = _impact_particles.process_material
	mat.color = color
	_impact_particles.restart()
	_impact_particles.emitting = true


func _setup_cannon_multimesh() -> void:
	_cannon_material = StandardMaterial3D.new()
	_cannon_material.albedo_color = Color(0.9, 0.7, 0.2)
	_cannon_material.emission_enabled = true
	_cannon_material.emission = Color(0.9, 0.7, 0.2)
	_cannon_material.emission_energy_multiplier = 1.5

	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0

	_cannon_mmi = MultiMeshInstance3D.new()
	_cannon_mmi.multimesh = mm
	_cannon_mmi.material_override = _cannon_material
	_cannon_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cannon_mmi)


func _setup_rocket_multimesh() -> void:
	_rocket_material = StandardMaterial3D.new()
	_rocket_material.albedo_color = Color(0.8, 0.3, 0.1)
	_rocket_material.emission_enabled = true
	_rocket_material.emission = Color(1.0, 0.4, 0.1)
	_rocket_material.emission_energy_multiplier = 2.0

	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 2

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0

	_rocket_mmi = MultiMeshInstance3D.new()
	_rocket_mmi.multimesh = mm
	_rocket_mmi.material_override = _rocket_material
	_rocket_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rocket_mmi)


func _setup_bullets_multimesh() -> void:
	_bullets_material = StandardMaterial3D.new()
	_bullets_material.albedo_color = Color(1.0, 0.9, 0.3)
	_bullets_material.emission_enabled = true
	_bullets_material.emission = Color(1.0, 0.9, 0.3)
	_bullets_material.emission_energy_multiplier = 2.0

	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0

	_bullets_mmi = MultiMeshInstance3D.new()
	_bullets_mmi.multimesh = mm
	_bullets_mmi.material_override = _bullets_material
	_bullets_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bullets_mmi)


func _setup_audio_pool() -> void:
	for i: int in SOUND_POOL_SIZE:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.max_db = 0.0
		player.unit_size = 10.0
		player.max_distance = 80.0
		player.bus = &"Master"
		add_child(player)
		_audio_pool.append(player)


func _play_sound(stream: AudioStream, pos: Vector3) -> void:
	var player: AudioStreamPlayer3D = _audio_pool[_audio_pool_index]
	_audio_pool_index = (_audio_pool_index + 1) % SOUND_POOL_SIZE
	player.stream = stream
	player.global_position = pos
	player.play()


# ── utility ──────────────────────────────────────────────────────────────────


func _beam_transform(from: Vector3, to: Vector3, width: float) -> Transform3D:
	var dir: Vector3 = to - from
	var length: float = dir.length()
	if length < 0.001:
		return Transform3D()
	var beam_dir: Vector3 = dir / length
	var mid: Vector3 = (from + to) * 0.5

	# X = beam direction * length, Y = perpendicular * width (billboard overrides in shader)
	var up: Vector3 = Vector3.UP
	if absf(beam_dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var perp: Vector3 = beam_dir.cross(up).normalized()

	var b: Basis = Basis(beam_dir * length, beam_dir.cross(perp).normalized(), perp * width)
	return Transform3D(b, mid)


func _default_color_for(type: Enums.Projectile) -> Color:
	match type:
		Enums.Projectile.CANNON:
			return Color(0.9, 0.7, 0.2)
		Enums.Projectile.ROCKET:
			return Color(0.8, 0.3, 0.1)
		Enums.Projectile.BULLETS:
			return Color(1.0, 0.9, 0.3)
		_:
			return Color.WHITE
