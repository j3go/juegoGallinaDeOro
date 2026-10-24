@tool
class_name UITheme
extends RefCounted
## Shared look for every screen: rounded cream panels, warm text and golden buttons.

const TEXT := Color(0.3, 0.2, 0.13)
const TEXT_SOFT := Color(0.56, 0.45, 0.35)
const GOLD := Color(1.0, 0.79, 0.25)
const GOLD_LIGHT := Color(1.0, 0.87, 0.45)
const GOLD_DARK := Color(0.8, 0.52, 0.12)
const ACCENT := Color(0.94, 0.48, 0.25)
const PANEL := Color(1.0, 0.98, 0.93, 0.93)
const DANGER := Color(0.92, 0.3, 0.25)

static var _font: Font


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Fredoka", "Baloo 2", "Nunito", "Varela Round", "Comfortaa", "Quicksand",
			"Fira Sans", "Ubuntu", "Cantarell", "Adwaita Sans", "DejaVu Sans", "Sans-Serif",
		])
		f.font_weight = 800
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
	return _font


static func label(text: String, size: int, color: Color = TEXT, outline: int = 0,
		outline_color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box_style(color: Color, radius: int = 20, padding: int = 16, border_color: Color = Color(0, 0, 0, 0),
		border_bottom: int = 0, shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding * 0.7
	s.content_margin_bottom = padding * 0.7
	if border_bottom > 0:
		s.border_color = border_color
		s.border_width_bottom = border_bottom
	if shadow:
		s.shadow_color = Color(0.35, 0.22, 0.1, 0.18)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func panel(color: Color = PANEL, radius: int = 22, padding: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box_style(color, radius, padding))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func dot(color: Color, size: float = 18.0) -> Panel:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(size, size)
	d.add_theme_stylebox_override("panel", box_style(color, int(size), 0, Color(0, 0, 0, 0), 0, false))
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


static func button(text: String, size: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, TEXT)
	b.add_theme_stylebox_override("normal", box_style(GOLD, 22, 28, GOLD_DARK, 7))
	b.add_theme_stylebox_override("hover", box_style(GOLD_LIGHT, 22, 28, GOLD_DARK, 7))
	b.add_theme_stylebox_override("focus", box_style(Color(0, 0, 0, 0), 22, 28, Color(0, 0, 0, 0), 0, false))
	var pressed := box_style(GOLD_DARK.lerp(GOLD, 0.6), 22, 28, GOLD_DARK, 2)
	pressed.content_margin_top += 5
	b.add_theme_stylebox_override("pressed", pressed)
	b.custom_minimum_size = Vector2(280, 76)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## Recursively stops containers from swallowing mouse input meant for the game.
static func ignore_mouse(node: Node) -> void:
	if node is Control and not node is BaseButton:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)
