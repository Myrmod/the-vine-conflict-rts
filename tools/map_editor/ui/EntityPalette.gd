class_name EntityPalette

extends TabContainer

## Automatically generates and manages the entity palette for the map editor

signal entity_selected(scene_path: String)
signal spawn_selected
signal height_level_selected(level: int)  ## -1 = water, 0 = ground, 1 = high ground
signal slope_selected
signal water_slope_selected
signal collision_selected(value: int)  ## 1 = block, 0 = unblock
signal slope_angle_changed(angle: float)

# Environment Container
@onready var objects_container = $Environment/EnvironmentPalette/ObjectsContainer/VBoxContainer
@onready
var high_ground_container = $Environment/EnvironmentPalette/HighGroundContainer/VBoxContainer
@onready
var normal_ground_container = $Environment/EnvironmentPalette/NormalGroundContainer/VBoxContainer
@onready var water_container = $Environment/EnvironmentPalette/WaterContainer/VBoxContainer
@onready var environment_palette = $Environment/EnvironmentPalette

# Faction container
@onready var neutral_container = $Factions/EntityPalette/NeutralContainer/VBoxContainer
@onready var the_amuns_container = $Factions/EntityPalette/TheAmunsContainer/VBoxContainer


func _ready() -> void:
	populate_objects()
	populate_neutral()
	populate_the_amuns()
	populate_height_levels()
	_populate_collision()
	_add_slope_angle_control()


func populate_height_levels() -> void:
	"""Populate the Environment tab height containers with real buttons."""
	_populate_high_ground()
	_populate_normal_ground()
	_populate_water()


func _populate_high_ground() -> void:
	if not high_ground_container:
		push_warning("HighGroundContainer VBoxContainer not found")
		return

	# Clear placeholder buttons
	for c: Node in high_ground_container.get_children():
		c.queue_free()

	# Paint high ground button
	var paint_btn: Button = Button.new()
	paint_btn.text = "▲ Paint High Ground"
	paint_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	paint_btn.pressed.connect(func() -> void: height_level_selected.emit(1))
	high_ground_container.add_child(paint_btn)

	# Slope button
	var slope_btn: Button = Button.new()
	slope_btn.text = "⟋ Slope"
	slope_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	slope_btn.pressed.connect(func() -> void: slope_selected.emit())
	high_ground_container.add_child(slope_btn)


func _populate_normal_ground() -> void:
	if not normal_ground_container:
		push_warning("NormalGroundContainer VBoxContainer not found")
		return

	# Clear placeholder buttons
	for c: Node in normal_ground_container.get_children():
		c.queue_free()

	var paint_btn: Button = Button.new()
	paint_btn.text = "■ Paint Normal Ground"
	paint_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	paint_btn.pressed.connect(func() -> void: height_level_selected.emit(0))
	normal_ground_container.add_child(paint_btn)


func _populate_water() -> void:
	if not water_container:
		push_warning("WaterContainer VBoxContainer not found")
		return

	# Clear placeholder buttons
	for c: Node in water_container.get_children():
		c.queue_free()

	var paint_btn: Button = Button.new()
	paint_btn.text = "▼ Paint Water"
	paint_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	paint_btn.pressed.connect(func() -> void: height_level_selected.emit(-1))
	water_container.add_child(paint_btn)

	# Water slope — separate group/identifier for passability rules
	var slope_btn: Button = Button.new()
	slope_btn.text = "↗ Water Slope"
	slope_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	slope_btn.pressed.connect(func() -> void: water_slope_selected.emit())
	water_container.add_child(slope_btn)


func populate_objects() -> void:
	if not objects_container:
		push_error("The objects_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c: Node in objects_container.get_children():
		c.queue_free()

	populate_container_with_scenes("res://source/decorations/", objects_container)


func populate_neutral() -> void:
	if not neutral_container:
		push_error("The neutral_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c: Node in neutral_container.get_children():
		c.queue_free()

	# Add spawn point button at the top
	var spawn_btn: Button = Button.new()
	spawn_btn.text = "⚑ Spawn Point"
	spawn_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	spawn_btn.pressed.connect(_on_spawn_button_pressed)
	neutral_container.add_child(spawn_btn)

	populate_container_with_scenes(
		"res://source/factions/neutral/structures/ResourceNode/", neutral_container
	)
	populate_container_with_scenes("res://source/factions/neutral/structures/", neutral_container)


func populate_the_amuns() -> void:
	if not the_amuns_container:
		push_error("The the_amuns_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c: Node in the_amuns_container.get_children():
		c.queue_free()

	populate_container_with_scenes(
		"res://source/factions/the_amuns/structures/", the_amuns_container
	)
	populate_container_with_scenes("res://source/factions/the_amuns/units/", the_amuns_container)


func populate_container_with_scenes(scenes_path: String, container: Node) -> void:
	var dir: DirAccess = DirAccess.open(scenes_path)
	if dir == null:
		push_error("Cannot open path: " + scenes_path)
		return

	dir.list_dir_begin()

	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break

		if dir.current_is_dir():
			continue

		if file_name.ends_with(".tscn"):
			create_scene_button(file_name, scenes_path, container)

	dir.list_dir_end()


func create_scene_button(file_name: String, scenes_path: String, container: Node) -> void:
	var btn: Button = Button.new()

	var scene_path: String = scenes_path + file_name
	btn.text = file_name.get_basename()
	btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)

	btn.pressed.connect(_on_scene_button_pressed.bind(scene_path))

	container.add_child(btn)


func _on_scene_button_pressed(scene_path: String) -> void:
	entity_selected.emit(scene_path)


func _on_spawn_button_pressed() -> void:
	spawn_selected.emit()


func _populate_collision() -> void:
	"""Add a Collision section to the Environment palette for manual collision painting."""
	if not environment_palette:
		push_warning("EnvironmentPalette VBoxContainer not found")
		return

	var foldable: FoldableContainer = FoldableContainer.new()
	foldable.title = "Collision"
	foldable.name = "CollisionContainer"

	var vbox: VBoxContainer = VBoxContainer.new()

	var block_btn: Button = Button.new()
	block_btn.text = "■ Block"
	block_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	block_btn.pressed.connect(func() -> void: collision_selected.emit(1))
	vbox.add_child(block_btn)

	var unblock_btn: Button = Button.new()
	unblock_btn.text = "□ Unblock"
	unblock_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	unblock_btn.pressed.connect(func() -> void: collision_selected.emit(0))
	vbox.add_child(unblock_btn)

	foldable.add_child(vbox)
	environment_palette.add_child(foldable)


func _add_slope_angle_control() -> void:
	"""Add a slope-angle spinner to the Environment palette."""
	if not environment_palette:
		return

	var foldable: FoldableContainer = FoldableContainer.new()
	foldable.title = "Slope Settings"
	foldable.name = "SlopeSettingsContainer"

	var vbox: VBoxContainer = VBoxContainer.new()

	var angle_box: HBoxContainer = HBoxContainer.new()
	var angle_label: Label = Label.new()
	angle_label.text = "Angle:"
	angle_box.add_child(angle_label)

	var angle_spin: SpinBox = SpinBox.new()
	angle_spin.min_value = 10
	angle_spin.max_value = 85
	angle_spin.step = 1
	angle_spin.value = 60
	angle_spin.suffix = "°"
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.value_changed.connect(func(v: float) -> void: slope_angle_changed.emit(v))
	angle_box.add_child(angle_spin)

	vbox.add_child(angle_box)
	foldable.add_child(vbox)
	environment_palette.add_child(foldable)
