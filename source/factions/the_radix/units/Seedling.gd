extends Unit

## Energy multiplier applied to the emission of the player-color material.
## Kept low so the underlying flat player color stays recognizable; the glow
## is just a soft halo, not a saturating bloom.
@export_range(0.0, 20.0, 0.1)
var player_color_emission_energy: float = RadixPlayerColor.DEFAULT_EMISSION_ENERGY

const MAX_PLAYER_COLOR_RETRIES := 60

var _player_color_retry_count: int = 0
var _player_color_materials: Array[StandardMaterial3D] = []


func _setup_color() -> void:
	# Skip the base Unit albedo-replace path; we apply our own flat
	# unshaded glow material directly to PlayerColor surfaces.
	_apply_player_color_glow()


func _apply_player_color_glow() -> void:
	if player == null:
		if _player_color_retry_count < MAX_PLAYER_COLOR_RETRIES:
			_player_color_retry_count += 1
			call_deferred("_apply_player_color_glow")
		return
	_player_color_retry_count = 0
	if not player.changed.is_connected(_on_player_changed):
		player.changed.connect(_on_player_changed)
	var geometry: Node = find_child("Geometry")
	if geometry == null:
		push_warning("Seedling: no 'Geometry' child found")
		return
	_player_color_materials = RadixPlayerColor.apply(
		geometry, player.color, player_color_emission_energy
	)
	if _player_color_materials.is_empty():
		push_warning("Seedling: no PlayerColor surfaces matched under 'Geometry'")


func _on_player_changed() -> void:
	if player == null:
		return
	RadixPlayerColor.refresh_materials(
		_player_color_materials, player.color, player_color_emission_energy
	)
