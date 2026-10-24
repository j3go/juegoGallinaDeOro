@tool
class_name EggIcon
extends Control
## Small golden egg drawn with polygons, used in the HUD.

@export var color := Color(1.0, 0.78, 0.24)


func _draw() -> void:
	var c := size * 0.5
	var rx := size.x * 0.42
	var ry := size.y * 0.46
	var outline := PackedVector2Array()
	var body := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		# Narrower top half gives the egg shape.
		var squeeze := 0.82 if sin(a) < 0.0 else 1.0
		var p := Vector2(cos(a) * rx * squeeze, sin(a) * ry)
		body.append(c + p + Vector2(0, ry * 0.05))
		outline.append(c + p * 1.12 + Vector2(0, ry * 0.05))
	draw_colored_polygon(outline, Color(0.6, 0.38, 0.1))
	draw_colored_polygon(body, color)
	var shine := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		shine.append(c + Vector2(-rx * 0.35, -ry * 0.3) + Vector2(cos(a) * rx * 0.18, sin(a) * ry * 0.28))
	draw_colored_polygon(shine, Color(1, 0.95, 0.75))
