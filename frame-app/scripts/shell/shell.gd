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
## Below the UI's screen area: the strip where the film's title and
## controls sit, shown on their own panel under the screen (controls_bar).
const CONTROLS_STRIP := 380
## That panel: its width, how far away (nearer than the screen), and the
## gap under the screen's lower edge as you see it (radians).
const CONTROLS_WIDTH := 1.6
const CONTROLS_RADIUS := 1.9
const CONTROLS_GAP := deg_to_rad(3.0)
const SCREEN_RADIUS := 2.4
const SCREEN_WIDTH := 2.8
const DECK_RADIUS := 1.9
const DECK_WIDTH := 2.3
## How far below eye height the deck sits (about 25° down: easy to glance at).
const DECK_DROP := 0.85
const FLIGHT_SECONDS := 0.55
## Screen sizes while watching: name -> width (same distance).
const SIZES := {"tv": 1.9, "cinema": 2.8, "imax": 4.2}
const SIZE_ORDER := ["tv", "cinema", "imax"]
const LEAN_ANGLE := 0.45
## Glow around the screen: off / subtle / strong.
const GLOW_LEVELS := [0.0, 0.35, 0.7]
const GLOW_LABELS := ["Glow: off", "Glow: subtle", "Glow: strong"]
## In menus the effects stay on, quieter: the screen's glow (relative to a
## film's) for menus and for a film's poster while it starts, the light the
## menus give off (soft, cool), the posters' light.
const MENU_GLOW := 0.3
const POSTER_GLOW := 0.65
const MENU_LIGHT := Color("8a96b8")
const TILE_LIGHT_LEVELS := [0.0, 1.0, 1.6]
const SPILL_COLOR := Color("c9d4ff")
## One press of Turn left / right.
const SNAP_TURN := deg_to_rad(45.0)
## Headset refresh rate to ask for (see _choose_refresh_rate).
const PREFERRED_HZ := 90.0
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const FLOOR_SHADER := preload("res://shaders/night_floor.gdshader")
## The floor reaches this far (metres) each way, well into the haze.
const FLOOR_SIZE := 800.0
## The night while watching (fraction of full), and how long the dimming takes.
const NIGHT_DIMMED := 0.12
const NIGHT_SECONDS := 3.0

var ui: Control
var ui_viewport := SubViewport.new()
var screen: CurvedScreen
var deck: CurvedScreen
var controls_bar: CurvedScreen
var wall: MovieWall
var router := PointerRouter.new()
var xr_active := false
var rig: Node3D
var _flight: Tween
var _environment: Environment
var _spill: OmniLight3D
var _lights: Tween
var _sky_material := ShaderMaterial.new()
var _floor_material := ShaderMaterial.new()
var _night := 1.0
var glow := ScreenGlow.new()
var reflection := FloorReflection.new()
var wall_reflection := WallReflection.new()
var _menu_light: ImageTexture
var _settings: Settings
var _size := "cinema"
var _lean := false
var _glow_level := 1
var _effects := 0.0
var _screen_motion: Tween
var _glow_button: Button


func _ready() -> void:
	ui = UiScene.instantiate()
	if "--flat" in OS.get_cmdline_user_args() or OS.get_environment("STREAM_FRAME_FLAT") == "1":
		add_child(ui)
		return

	_build_room()
	ui_viewport.size = UI_SIZE + Vector2i(0, CONTROLS_STRIP)
	ui_viewport.disable_3d = true
	# Transparent where the UI doesn't draw, so a film on the screen shows
	# through under the controls.
	ui_viewport.transparent_bg = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui_viewport.gui_embed_subwindows = true
	add_child(ui_viewport)
	ui_viewport.add_child(ui)  # runs the app's _ready: it starts connecting
	# The app keeps the screen's area; the strip below is for the controls.
	ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ui.size = UI_SIZE

	_settings = ui.settings
	_size = _settings.extension_value("device", "screen_size", "cinema")
	_lean = _settings.extension_value("device", "lean_back", false)
	_glow_level = _settings.extension_value("device", "glow", 1)
	screen = CurvedScreen.new(ui_viewport, SCREEN_RADIUS, SIZES.get(_size, SCREEN_WIDTH), Rect2(Vector2.ZERO, UI_SIZE))
	screen.position.y = EYE_HEIGHT
	screen.set_opacity(0.0)
	add_child(screen)
	screen.add_child(glow)
	glow.build(SCREEN_RADIUS, screen.width, screen.height)
	add_child(reflection)
	reflection.build(SCREEN_RADIUS, screen.width)
	var player: PlayerView = ui.player
	player.video_on_screen = true
	player.set_screen_controls(true, _size)
	player.set_lean_back(_lean)
	player.screen_size_requested.connect(_next_size)
	player.lean_back_requested.connect(func() -> void: _set_lean(not _lean))
	_glow_button = UiTheme.button(GLOW_LABELS[_glow_level], _next_glow)
	player.add_option(_glow_button)
	# The film's controls: their own panel just below the screen, so they
	# never cover the picture. A child of the screen: it leans back with it.
	player.place_controls_below(UI_SIZE.y, CONTROLS_STRIP)
	controls_bar = CurvedScreen.new(ui_viewport, CONTROLS_RADIUS, CONTROLS_WIDTH, Rect2(0, UI_SIZE.y, UI_SIZE.x, CONTROLS_STRIP))
	controls_bar.set_floating(true)
	controls_bar.set_opacity(0.0)
	screen.add_child(controls_bar)
	_place_controls_bar()
	deck = CurvedScreen.new(ui_viewport, DECK_RADIUS, DECK_WIDTH, Rect2(0, 0, UI_SIZE.x, BrowseView.HEADER_HEIGHT))
	deck.position.y = EYE_HEIGHT - DECK_DROP
	deck.set_floating(true)
	add_child(deck)
	wall = MovieWall.new(ui.images)
	wall.position.y = EYE_HEIGHT
	add_child(wall)
	wall_reflection.position.y = 0.004
	add_child(wall_reflection)
	wall_reflection.build(MovieWall.RADIUS, MovieWall.ARC, wall.floor_light)
	WallTile.light_level = TILE_LIGHT_LEVELS[_glow_level]
	_menu_light = ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_RGB8,
		PackedByteArray([MENU_LIGHT.r8, MENU_LIGHT.g8, MENU_LIGHT.b8])))
	router.targets = [deck, controls_bar, screen, wall]

	var browse: BrowseView = ui.browse
	browse.set_wall_mode(true)
	browse.loading_started.connect(func(keep_content: bool) -> void:
		if not keep_content:
			wall.show_loading())
	browse.catalog_shown.connect(func(catalog: Dictionary) -> void:
		wall.show_catalog(catalog, catalog.get("_paging", false)))
	browse.items_appended.connect(wall.append_items)
	wall.row_end_reached.connect(ui.load_more)
	browse.sources_shown.connect(wall.show_sources)
	browse.load_failed.connect(wall.show_error)
	wall.tile_chosen.connect(_on_tile_chosen)
	ui.view_changed.connect(_on_view_changed)
	# The app already showed its home before we were listening.
	wall.show_sources(ui.sources, ui.continue_watching())
	_on_view_changed(ui.current_view)

	var openxr := XRServer.find_interface("OpenXR")
	xr_active = openxr != null and openxr.is_initialized()
	if xr_active:
		get_viewport().use_xr = true
		_choose_refresh_rate(openxr)
		rig = XrRig.new(router)
	else:
		rig = DesktopRig.new(router)
		rig.position.y = EYE_HEIGHT
	add_child(rig)


func _process(delta: float) -> void:
	if screen == null:
		return
	# While a film plays with its controls faded, the UI shows nothing: stop
	# redrawing it (a full-HD layer every frame) until something changes.
	var ui_idle: bool = ui.current_view == "player" and ui.player.is_idle()
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if ui_idle else SubViewport.UPDATE_ALWAYS
	# Turning (once per press: a held stick turns once, not round and round).
	if rig and Input.is_action_just_pressed(InputActions.TURN_LEFT):
		rig.turn(SNAP_TURN)
	if rig and Input.is_action_just_pressed(InputActions.TURN_RIGHT):
		rig.turn(-SNAP_TURN)
	# The film on the screen, and the light it casts around it.
	var player: PlayerView = ui.player
	var playing_here: bool = ui.current_view == "player" and ui._playback == ui.local and player.is_showing_video()
	var reveal: float = player.video_reveal if playing_here else 0.0
	var video: Texture2D = ui.local.video_texture() if playing_here else null
	var content: Rect2 = ui.local.content_rect()
	screen.set_video(video, reveal, player.stereo, content)
	if video:
		var picture := video.get_size() * content.size
		picture.x /= 2.0 if player.stereo == 1 else 1.0
		picture.y /= 2.0 if player.stereo == 2 else 1.0
		glow.set_picture_aspect(picture.x / maxf(picture.y, 1.0))
	# Browsing, the deck's controls float in the room: no panel behind them.
	ui.background.modulate.a = 0.0 if ui.current_view == "browse" else 1.0 - reveal

	# Outside the film, the screen glows with the menus' own light, or the
	# film's poster while it's starting; the film takes over as it appears.
	var menu: Texture2D = _menu_light
	var menu_colour := MENU_LIGHT
	var menu_glow := MENU_GLOW
	if ui.current_view == "player" and player.backdrop_url() != "":
		var poster: Dictionary = ui.images.ambient(player.backdrop_url())
		if not poster.is_empty():
			menu = poster["grid"]
			menu_colour = poster["color"]
			menu_glow = POSTER_GLOW
	var opacity := screen.opacity()
	if video == null:
		glow.set_picture_aspect(screen.width / screen.height)
	_effects = move_toward(_effects, maxf(reveal, menu_glow * opacity), delta * 1.5)
	var ambient: Texture2D = ui.local.ambient_texture() if reveal > 0.0 else null
	var glowing := 1.0 if _glow_level > 0 else 0.0
	glow.set_light(ambient, menu, 1.0 - reveal, _effects, GLOW_LEVELS[_glow_level])
	reflection.set_light(ambient, menu, 1.0 - reveal, _effects * (0.0 if _lean else 1.0) * glowing)
	wall_reflection.set_fade(TILE_LIGHT_LEVELS[_glow_level])
	var k := 1.0 - exp(-4.0 * delta)
	if _glow_level == 0:
		_spill.light_color = _spill.light_color.lerp(SPILL_COLOR, k)
		return

	# The room takes on the colour of what's in front: the wall, the screen,
	# the film (fully, and brighter for bright scenes).
	var colour := wall.light_color().lerp(menu_colour, opacity)
	if reveal > 0.0:
		colour = colour.lerp(ui.local.average_color(), reveal)
	var peak := maxf(colour.r, maxf(colour.g, colour.b))
	var tint := Color(colour / peak, 1.0) if peak > 0.02 else SPILL_COLOR
	_spill.light_color = _spill.light_color.lerp(SPILL_COLOR.lerp(tint, lerpf(0.5, 1.0, reveal)), k)
	if reveal > 0.0:
		var target_energy: float = (0.1 + 1.1 * colour.get_luminance()) * reveal * GLOW_LEVELS[_glow_level] / 0.35
		_spill.light_energy = lerpf(_spill.light_energy, target_energy, k)


func _next_size() -> void:
	_size = SIZE_ORDER[(SIZE_ORDER.find(_size) + 1) % SIZE_ORDER.size()]
	_settings.set_extension_value("device", "screen_size", _size)
	_settings.save()
	ui.player.set_screen_controls(true, _size)
	var from := screen.width
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(w: float) -> void:
		screen.set_width(w)
		_place_controls_bar()
		glow.build(SCREEN_RADIUS, screen.width, screen.height)
		reflection.build(SCREEN_RADIUS, screen.width), from, SIZES[_size], 0.5)


## The controls panel sits just below the screen's lower edge as you see
## it, whatever the screen's size.
func _place_controls_bar() -> void:
	var below := atan2(screen.height / 2.0, SCREEN_RADIUS) + CONTROLS_GAP
	controls_bar.set_rest_y(-tan(below) * CONTROLS_RADIUS - controls_bar.height / 2.0)


## Tilts the screen up around the viewer, for watching while reclining.
func _set_lean(on: bool) -> void:
	_lean = on
	_settings.set_extension_value("device", "lean_back", on)
	_settings.save()
	ui.player.set_lean_back(on)
	if _screen_motion:
		_screen_motion.kill()
	_screen_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_screen_motion.tween_property(screen, "rotation:x", LEAN_ANGLE if on and ui.current_view == "player" else 0.0, 0.8)


func _next_glow() -> void:
	_glow_level = (_glow_level + 1) % GLOW_LEVELS.size()
	_glow_button.text = GLOW_LABELS[_glow_level]
	_settings.set_extension_value("device", "glow", _glow_level)
	WallTile.light_level = TILE_LIGHT_LEVELS[_glow_level]
	wall.refresh_light()
	_settings.save()


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard, gamepad and app actions (e.g. a mouse back button, a VR
	# controller's B) go straight to the UI; pointing is routed by the rigs
	# via ray hits.
	if ui_viewport.is_inside_tree() and (event is InputEventKey or event is InputEventJoypadButton \
			or event is InputEventJoypadMotion or InputActions.is_app_event(event)):
		ui_viewport.push_input(event)


func _on_view_changed(view: String) -> void:
	# Watching a film is its own state: nothing else around, lights down,
	# pointers hidden until you reach for them.
	var watching := view == "player"
	_set_lights(not watching)
	if rig:
		rig.set_quiet(watching)
	# Lean back applies while watching; menus are always upright.
	if screen:
		if _screen_motion:
			_screen_motion.kill()
		_screen_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_screen_motion.tween_property(screen, "rotation:x", LEAN_ANGLE if watching and _lean else 0.0, 0.8)
	match view:
		"browse":
			wall.set_faded(0.0)
			deck.fade(1.0)
			screen.fade(0.0, 0.2)
			controls_bar.fade(0.0, 0.2)
		"player", "extensions", "info":
			wall.set_faded(MovieWall.HIDDEN if watching else MovieWall.DIMMED)
			deck.fade(0.0, 0.15)
			# While a poster is flying in, the flight reveals the screen.
			if not (_flight and _flight.is_running()):
				screen.fade(1.0)
			controls_bar.fade(1.0 if view == "player" else 0.0, 0.2)


## Room lighting: up while browsing, down for the film.
func _set_lights(up: bool) -> void:
	if _lights:
		_lights.kill()
	_lights = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_lights.tween_property(_spill, "light_energy", 0.8 if up else 0.12, 1.2)
	_lights.tween_property(_environment, "ambient_light_energy", 0.6 if up else 0.15, 1.2)
	# The night sky dims slowly, like a cinema's lights, and comes back the
	# same way.
	_lights.tween_method(_set_night, _night, 1.0 if up else NIGHT_DIMMED, NIGHT_SECONDS)


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


## How bright the night (sky and far floor) is: 1 browsing, dimmed watching.
func _set_night(level: float) -> void:
	_night = level
	_sky_material.set_shader_parameter("brightness", level)
	_floor_material.set_shader_parameter("brightness", level)


## The headset's refresh rate: the highest it offers up to PREFERRED_HZ.
## Smooth for menus and films alike, and lighter on the battery than the
## panel's maximum.
func _choose_refresh_rate(openxr: XRInterface) -> void:
	if not openxr.has_method("get_available_display_refresh_rates"):
		return
	var best := 0.0
	for rate: float in openxr.get_available_display_refresh_rates():
		if rate <= PREFERRED_HZ + 0.5 and rate > best:
			best = rate
	if best > 0.0:
		openxr.display_refresh_rate = best


func _build_room() -> void:
	var environment := Environment.new()
	# A starry night all round; the floor stretches off into its horizon.
	_sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("1a1c22")
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	_environment = environment
	add_child(world)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	# Finer near you, so the spill light and fade stay smooth.
	floor_mesh.subdivide_width = 64
	floor_mesh.subdivide_depth = 64
	_floor_material.shader = FLOOR_SHADER
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = _floor_material
	add_child(floor_node)

	# The wall "lights" the floor in front of it.
	var spill := OmniLight3D.new()
	spill.position = Vector3(0, 0.6, -2.4)
	spill.light_color = Color("c9d4ff")
	spill.light_energy = 0.8
	spill.omni_range = 4.5
	add_child(spill)
	_spill = spill
