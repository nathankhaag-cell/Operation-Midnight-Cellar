extends CanvasLayer
## Reticle, hitmarker, weapon list with ammo, target health bar, reload prompt, grenade
## and melee ability icons, a melee impact flash and a controls hint. Everything is drawn in code.

const Data := preload("res://scripts/weapon_data.gd")
const ENEMY_RED := Color(1.0, 0.28, 0.22)
const MAJOR_GOLD := Color(1.0, 0.78, 0.25)

var _hint: Label
var _prompt: Label
var _weapons: Array[Label] = []
var _cross: _Reticle
var _hitmarker: _Hitmarker
var _bar: _TargetBar
var _abilities: _Abilities
var _impact: ColorRect
var _hit_time := 0.0
var _hit_kill := false
var _target: Node
var _target_time := 0.0


func _ready() -> void:
	add_to_group("hud")
	_cross = _Reticle.new()
	_full_rect(_cross)

	_hitmarker = _Hitmarker.new()
	_full_rect(_hitmarker)
	_hitmarker.visible = false

	_bar = _TargetBar.new()
	_full_rect(_bar)
	_bar.visible = false

	# Weapon list, top left: one row per slot, the equipped one bright.
	var list := VBoxContainer.new()
	list.position = Vector2(24, 20)
	list.add_theme_constant_override("separation", 2)
	add_child(list)
	for i in Data.ORDER.size():
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_constant_override("outline_size", 4)
		row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		list.add_child(row)
		_weapons.append(row)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-60, 46)
	_prompt.size = Vector2(120, 24)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 16)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(_prompt)

	# Grenade and melee, bottom left.
	_abilities = _Abilities.new()
	_full_rect(_abilities)

	_impact = ColorRect.new()
	_impact.color = Color(1, 1, 1, 0)
	_full_rect(_impact)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_right = -20
	_hint.offset_bottom = -16
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(1, 1, 1, 0.7)
	add_child(_hint)


func _full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _process(delta: float) -> void:
	if _hit_time > 0.0:
		_hit_time -= delta
		_hitmarker.modulate.a = clampf(_hit_time / (0.25 if _hit_kill else 0.15), 0.0, 1.0)
		if _hit_time <= 0.0:
			_hitmarker.visible = false

	if _target_time > 0.0:
		_target_time -= delta
		_bar.visible = _target_time > 0.0 and is_instance_valid(_target)
		if _bar.visible:
			_bar.title = _target.display_name
			_bar.fill = _target.health_fraction()
			_bar.color = MAJOR_GOLD if _target.is_major else ENEMY_RED
			_bar.modulate.a = clampf(_target_time / 0.4, 0.0, 1.0)
			_bar.queue_redraw()

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var weapon = player.weapon
	_update_reticle(player, weapon)
	_update_weapons(weapon)
	_abilities.update(player.abilities.grenade_charge, player.abilities.melee_fraction(),
		player.abilities.GRENADE_RECHARGE, delta)
	_impact.color.a = maxf(_impact.color.a - delta * 2.5, 0.0)

	var ammo: int = weapon.ammo()
	var mag: int = weapon.stats["mag"]
	if weapon.is_reloading():
		_prompt.text = "Reloading"
		_prompt.modulate = Color(1, 1, 1, 0.8)
	elif ammo == 0:
		_prompt.text = "Reload"
		_prompt.modulate = ENEMY_RED
	elif ammo <= mag / 4:
		_prompt.text = "Low ammo"
		_prompt.modulate = Color(1, 0.75, 0.4)
	else:
		_prompt.text = ""

	_hint.text = "WASD move · Shift sprint · Space jump (again in air to glide)\n" \
		+ "LMB fire · RMB aim · R reload · 1 2 3 or wheel switch\n" \
		+ "Q grenade · F or mouse thumb melee · [ ] FOV %d · Esc free mouse" % int(player.base_fov)


func _update_reticle(player: Node, weapon: Node) -> void:
	var cam: Camera3D = player.camera
	var half_h := _cross.size.y * 0.5
	var px := tan(deg_to_rad(weapon.spread_degrees())) / tan(deg_to_rad(cam.fov) * 0.5) * half_h
	_cross.style = weapon.current_id()
	_cross.spread = px
	_cross.hot = weapon.is_over_target()
	_cross.modulate.a = 1.0 - clampf(weapon.aim_blend() * 1.6, 0.0, 1.0)
	_cross.visible = _cross.modulate.a > 0.01
	_cross.queue_redraw()


func _update_weapons(weapon: Node) -> void:
	var active: int = weapon.target_slot()
	for i in _weapons.size():
		var id: String = Data.ORDER[i]
		var a: Dictionary = Data.ARCHETYPES[id]
		var row := _weapons[i]
		var count: int = weapon.mags[id]
		row.text = "%d  %s   %d / %d" % [i + 1, a["name"], count, a["mag"]]
		var low: bool = count <= int(a["mag"]) / 4
		if i == active:
			row.modulate = ENEMY_RED.lightened(0.3) if low else Color.WHITE
			row.add_theme_font_size_override("font_size", 22)
		else:
			row.modulate = Color(1, 1, 1, 0.45)
			row.add_theme_font_size_override("font_size", 16)


func show_hitmarker(crit: bool, killed := false) -> void:
	_hitmarker.visible = true
	_hitmarker.crit = crit
	_hitmarker.kill = killed
	_hitmarker.queue_redraw()
	_hit_kill = killed
	_hit_time = 0.25 if killed else 0.15


## A quick white flash when a punch connects.
func flash_impact() -> void:
	_impact.color.a = 0.18


func show_target(target: Node) -> void:
	_target = target
	_target_time = 3.0


## The reticle: a shape per archetype whose gap opens with the current spread, and
## which turns red when it's over a target in range.
class _Reticle extends Control:
	var style := "auto_rifle"
	var spread := 0.0
	var hot := false

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1.0, 0.3, 0.25, 0.95) if hot else Color(1, 1, 1, 0.9)
		var shadow := Color(0, 0, 0, 0.35)
		var gap := maxf(spread, 4.0)
		match style:
			"hand_cannon":
				# A ring that breathes with spread, with three short ticks.
				var r := gap + 6.0
				draw_arc(c, r, 0.0, TAU, 40, shadow, 3.5)
				draw_arc(c, r, 0.0, TAU, 40, col, 1.5)
				for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
					_tick(c + d * (r + 3.0), c + d * (r + 10.0), col, shadow)
				draw_circle(c, 1.5, col)
			"scout_rifle":
				# A dot under a small chevron, ticks out to the sides.
				draw_circle(c, 2.0, col)
				_tick(c + Vector2(-7, -5 - gap * 0.3), c + Vector2(0, -2 - gap * 0.3), col, shadow)
				_tick(c + Vector2(7, -5 - gap * 0.3), c + Vector2(0, -2 - gap * 0.3), col, shadow)
				for d in [Vector2(-1, 0), Vector2(1, 0)]:
					_tick(c + d * (gap + 6.0), c + d * (gap + 16.0), col, shadow)
			_:
				# Auto rifle: a dot and four ticks.
				draw_circle(c, 2.0, col)
				for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					_tick(c + d * (gap + 4.0), c + d * (gap + 12.0), col, shadow)

	func _tick(a: Vector2, b: Vector2, col: Color, shadow: Color) -> void:
		draw_line(a, b, shadow, 4.0)
		draw_line(a, b, col, 2.0)


class _Hitmarker extends Control:
	var crit := false
	var kill := false

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1.0, 0.85, 0.2) if crit else Color.WHITE
		var inner := 9.0 if kill else 7.0
		var outer := 20.0 if kill else 15.0
		var width := 3.5 if kill else 2.5
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * inner, c + d * outer, Color(0, 0, 0, 0.4), width + 2.0)
			draw_line(c + d * inner, c + d * outer, col, width)


## The name and health bar of whatever you last hit, top centre.
class _TargetBar extends Control:
	var title := ""
	var fill := 1.0
	var color := Color.RED

	func _draw() -> void:
		var w := 360.0
		var top := Vector2((size.x - w) * 0.5, 48)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, top + Vector2(0, -8), title, HORIZONTAL_ALIGNMENT_CENTER, w, 16, 4, Color(0, 0, 0, 0.6))
		draw_string(font, top + Vector2(0, -8), title, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color.WHITE)
		draw_rect(Rect2(top - Vector2(2, 2), Vector2(w + 4, 12)), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(top, Vector2(w * fill, 8)), color)


## Grenade and melee icons, bottom left. Each fills from the bottom as it charges and
## gives a short pulse the moment it's ready.
class _Abilities extends Control:
	const BOX := 54.0
	const READY := Color(1.0, 0.85, 0.45)
	var _charges := [1.0, 1.0]
	var _pulses := [0.0, 0.0]
	var _grenade_recharge := 20.0

	func update(grenade: float, melee: float, grenade_recharge: float, delta: float) -> void:
		_grenade_recharge = grenade_recharge
		var now := [grenade, melee]
		for i in 2:
			if now[i] >= 1.0 and _charges[i] < 1.0:
				_pulses[i] = 1.0
			_pulses[i] = maxf(_pulses[i] - delta * 2.5, 0.0)
			_charges[i] = now[i]
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var keys := ["Q", "F"]
		for i in 2:
			var origin := Vector2(28 + i * (BOX + 18), size.y - 150)
			var rect := Rect2(origin, Vector2(BOX, BOX))
			var charge: float = _charges[i]
			var ready := charge >= 1.0
			# Pulse: the frame grows and glows for a moment.
			var grow: float = _pulses[i] * 8.0
			draw_rect(rect.grow(2), Color(0, 0, 0, 0.5))
			var fill_h := BOX * charge
			draw_rect(Rect2(origin + Vector2(0, BOX - fill_h), Vector2(BOX, fill_h)),
				Color(1, 1, 1, 0.28) if not ready else Color(READY.r, READY.g, READY.b, 0.35))
			var frame := READY if ready else Color(1, 1, 1, 0.45)
			draw_rect(rect.grow(grow), Color(frame.r, frame.g, frame.b, 1.0 - _pulses[i] * 0.6) if grow > 0.0 else frame, false, 2.0)
			var c := rect.get_center()
			var icon := Color(1, 1, 1, 0.95) if ready else Color(1, 1, 1, 0.5)
			if i == 0:
				# Grenade: a body with a band, a lever and a ring pin.
				draw_circle(c + Vector2(0, 4), 13.0, icon)
				draw_rect(Rect2(c + Vector2(-14, 1), Vector2(28, 5)), Color(0, 0, 0, 0.45))
				draw_rect(Rect2(c + Vector2(-4, -15), Vector2(8, 6)), icon)
				draw_line(c + Vector2(4, -13), c + Vector2(12, -4), icon, 3.0)
				draw_arc(c + Vector2(-9, -15), 4.5, 0.0, TAU, 16, icon, 2.0)
			else:
				# Melee: a fist seen from the front, four knuckles over a thumb.
				for k in 4:
					draw_rect(Rect2(c + Vector2(-14 + k * 7, -12), Vector2(6, 11)), icon)
				draw_rect(Rect2(c + Vector2(-14, 0), Vector2(27, 12)), icon)
				draw_rect(Rect2(c + Vector2(-14, 2), Vector2(14, 4)), Color(0, 0, 0, 0.45))
			draw_string(font, origin + Vector2(0, BOX + 18), keys[i], HORIZONTAL_ALIGNMENT_CENTER, BOX, 14, Color(1, 1, 1, 0.75))
			if not ready and i == 0:
				var secs := ceili((1.0 - charge) * _grenade_recharge)
				draw_string(font, origin + Vector2(0, -6), "%ds" % secs, HORIZONTAL_ALIGNMENT_CENTER, BOX, 13, Color(1, 1, 1, 0.7))
