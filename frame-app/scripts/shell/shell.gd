extends Node3D
## App entry point. Puts the app in a dark room:
##   - browsing: the catalog is a curved movie wall around you, with a small
##     control deck (service tabs, status, Refresh, Settings) below it;
##   - playing / settings: the 2D UI on a big curved screen in front, the
##     wall dimmed and pushed back. Picking a poster flies it into the screen.
## How you look at it:
##   - OpenXR headset when a runtime is available (the Steam Frame),
##   - a desktop 3D preview otherwise (the view follows the mouse),
##   - plain 2D with --flat / STREAM_FRAME_FLAT=1, for quick UI work.

const UiScene := preload("res://main.tscn")
## Head height for the desktop preview; in XR the headset reports the real one.
const EYE_HEIGHT := 1.6
const UI_SIZE := Vector2i(1920, 1080)
const SCREEN_RADIUS := 2.4
const SCREEN_WIDTH := 2.8
const DECK_RADIUS := 1.9
const DECK_WIDTH := 2.3
## How far below eye height the deck sits (about 25° down: easy to glance at).
const DECK_DROP := 0.85
const FLIGHT_SECONDS := 0.55

var ui: Control
var ui_viewport := SubViewport.new()
var screen: CurvedScreen
var deck: CurvedScreen
var wall: MovieWall
var router := PointerRouter.new()
var xr_active := false
var _flight: Tween


func _ready() -> void:
	ui = UiScene.instantiate()
	if "--flat" in OS.get_cmdline_user_args() or OS.get_environment("STREAM_FRAME_FLAT") == "1":
		add_child(ui)
		return

	_build_room()
	ui_viewport.size = UI_SIZE
	ui_viewport.disable_3d = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui_viewport.gui_embed_subwindows = true
	add_child(ui_viewport)
	ui_viewport.add_child(ui)  # runs the app's _ready: it starts connecting

	screen = CurvedScreen.new(ui_viewport, SCREEN_RADIUS, SCREEN_WIDTH)
	screen.position.y = EYE_HEIGHT
	screen.set_opacity(0.0)
	add_child(screen)
	deck = CurvedScreen.new(ui_viewport, DECK_RADIUS, DECK_WIDTH, Rect2(0, 0, UI_SIZE.x, BrowseView.HEADER_HEIGHT))
	deck.position.y = EYE_HEIGHT - DECK_DROP
	add_child(deck)
	wall = MovieWall.new(ui.images)
	wall.position.y = EYE_HEIGHT
	add_child(wall)
	router.targets = [deck, screen, wall]

	var browse: BrowseView = ui.browse
	browse.set_wall_mode(true)
	browse.loading_started.connect(func(keep_content: bool) -> void:
		if not keep_content:
			wall.show_loading())
	browse.catalog_shown.connect(wall.show_catalog)
	browse.sources_shown.connect(wall.show_sources)
	browse.load_failed.connect(wall.show_error)
	wall.tile_chosen.connect(_on_tile_chosen)
	ui.view_changed.connect(_on_view_changed)
	# The app already showed its home before we were listening.
	wall.show_sources(ui.sources)
	_on_view_changed(ui.current_view)

	var openxr := XRServer.find_interface("OpenXR")
	xr_active = openxr != null and openxr.is_initialized()
	if xr_active:
		get_viewport().use_xr = true
		add_child(XrRig.new(router))
	else:
		var camera := DesktopRig.new(router)
		camera.position.y = EYE_HEIGHT
		add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard and gamepad go straight to the UI; pointer input is routed by
	# the rigs via ray hits.
	if ui_viewport.is_inside_tree() and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		ui_viewport.push_input(event)


func _on_view_changed(view: String) -> void:
	match view:
		"browse":
			wall.set_dimmed(false)
			deck.fade(1.0)
			screen.fade(0.0, 0.2)
		"player", "extensions", "info":
			wall.set_dimmed(true)
			deck.fade(0.0, 0.15)
			# While a poster is flying in, the flight reveals the screen.
			if not (_flight and _flight.is_running()):
				screen.fade(1.0)


func _on_tile_chosen(tile: WallTile) -> void:
	if tile.item.get("kind") == "source":
		ui.open_source(tile.item["source"])
	else:
		_fly_into_screen(tile)
		ui.play_item(tile.item)


## The poster flies from the wall into the big screen, which then takes over.
func _fly_into_screen(tile: WallTile) -> void:
	var flyer := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	flyer.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = tile.texture()
	if tile.texture() == null:
		material.albedo_color = UiTheme.BORDER
	flyer.material_override = material
	add_child(flyer)
	var start := tile.art.global_transform
	flyer.global_transform = Transform3D(start.basis * Basis.from_scale(Vector3(WallTile.SIZE.x, WallTile.SIZE.y, 1.0)), start.origin)
	var target := Transform3D(Basis.from_scale(Vector3(screen.width, screen.height, 1.0)),
		Vector3(0, EYE_HEIGHT, -SCREEN_RADIUS))

	if _flight:
		_flight.kill()
	_flight = create_tween()
	_flight.tween_property(flyer, "global_transform", target, FLIGHT_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_flight.tween_callback(func() -> void:
		if ui.current_view != "browse":
			screen.fade(1.0, 0.2))
	_flight.tween_interval(0.2)
	_flight.tween_callback(flyer.queue_free)


func _build_room() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("07080a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("1a1c22")
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40, 40)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("101217")
	floor_material.roughness = 0.6
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_material
	add_child(floor_node)

	# The wall "lights" the floor in front of it.
	var spill := OmniLight3D.new()
	spill.position = Vector3(0, 0.6, -2.4)
	spill.light_color = Color("c9d4ff")
	spill.light_energy = 0.8
	spill.omni_range = 4.5
	add_child(spill)
