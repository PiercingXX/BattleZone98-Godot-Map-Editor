extends RefCounted
class_name ThemeProbe
## Theme lookups with a fallback. Reusable controls must not name colours: the
## Theme resource is authored elsewhere, so ask the chain first and only then
## fall back to something neutral that still reads on any background.


static func color(node: Control, name: String, type_name: String,
		fallback: Color) -> Color:
	if node != null and node.has_theme_color(name, type_name):
		return node.get_theme_color(name, type_name)
	return fallback


static func constant(node: Control, name: String, type_name: String,
		fallback: int) -> int:
	if node != null and node.has_theme_constant(name, type_name):
		return node.get_theme_constant(name, type_name)
	return fallback


static func font_size(node: Control, name: String, type_name: String,
		fallback: int) -> int:
	if node != null and node.has_theme_font_size(name, type_name):
		return node.get_theme_font_size(name, type_name)
	return fallback


static func stylebox(node: Control, name: String, type_name: String) -> StyleBox:
	if node != null and node.has_theme_stylebox(name, type_name):
		return node.get_theme_stylebox(name, type_name)
	return null


## The accent a control should highlight with: the theme's if it has one,
## otherwise a mid blue that survives both a dark and a light chrome.
static func accent(node: Control) -> Color:
	if node != null and node.has_theme_color("accent", "Editor"):
		return node.get_theme_color("accent", "Editor")
	if node != null and node.has_theme_color("font_color", "ProgressBar"):
		return node.get_theme_color("font_color", "ProgressBar")
	return Color(0.22, 0.52, 0.78, 1)


## Body text colour, taken from whatever Label styling is in force.
static func text(node: Control) -> Color:
	return color(node, "font_color", "Label", Color(0.90, 0.90, 0.92, 1))


## De-emphasised text: the theme's dim colour, else body text at 65 %.
static func dim_text(node: Control) -> Color:
	if node != null and node.has_theme_color("font_disabled_color", "Button"):
		return node.get_theme_color("font_disabled_color", "Button")
	var base := text(node)
	return Color(base.r, base.g, base.b, base.a * 0.65)
