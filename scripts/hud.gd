extends CanvasLayer
## Crosshair, hitmarker, ammo counter and a controls hint.

var _ammo: Label
var _hint: Label
var _cross: Control
var _hitmarker: Control
var _hit_time := 0.0


func _ready() -> void:
	add_to_group("hud")
	_cross = _Crosshair.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)

	_hitmarker = _Hitmarker.new()
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hitmarker.visible = false
	add_child(_hitmarker)

	_ammo = Label.new()
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-180, -90)
	_ammo.add_theme_font_size_override("font_size", 36)
	add_child(_ammo)

	_hint = Label.new()
	_hint.position = Vector2(20, 16)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hint.text = "WASD move · Shift sprint · Space jump (again in air to glide)\n" \
		+ "LMB fire · RMB aim · R reload · [ ] FOV · Esc free mouse"
	add_child(_hint)


func _process(delta: float) -> void:
	if _hit_time > 0.0:
		_hit_time -= delta
		_hitmarker.modulate.a = clamp(_hit_time / 0.15, 0.0, 1.0)
		if _hit_time <= 0.0:
			_hitmarker.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_cross.visible = not player.weapon.is_aiming()
		_hint.text = _hint.text.get_slice("\nFOV", 0) + "\nFOV %d" % int(player.base_fov)


func set_ammo(current: int, mag: int) -> void:
	_ammo.text = "%d / %d" % [current, mag]
	_ammo.modulate = Color(1, 0.4, 0.3) if current <= mag / 4 else Color.WHITE


func show_hitmarker(crit: bool) -> void:
	_hitmarker.visible = true
	_hitmarker.modulate = Color(1.0, 0.85, 0.2) if crit else Color.WHITE
	_hit_time = 0.15


class _Crosshair extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 2.0, Color(1, 1, 1, 0.9))
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 8.0, c + d * 16.0, Color(1, 1, 1, 0.8), 2.0)


class _Hitmarker extends Control:
	func _draw() -> void:
		var c := size * 0.5
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 7.0, c + d * 15.0, Color.WHITE, 2.5)
