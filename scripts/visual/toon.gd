@tool
class_name Toon
extends RefCounted
## Helpers to build the soft "toy / clay" look out of primitive meshes.
## Meshes and materials are cached so many props share the same resources.

static var _materials := {}
static var _meshes := {}


static func mat(color: Color, roughness: float = 0.8, metallic: float = 0.0, rim: float = 0.25) -> StandardMaterial3D:
	var key := "mat|%s|%.2f|%.2f|%.2f" % [color.to_html(), roughness, metallic, rim]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.7
	_materials[key] = m
	return m


static func emissive(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "emi|%s|%.2f" % [color.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_materials[key] = m
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var key := "uns|%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = m
	return m


## Soft round additive dot. Used for sparkles and fake glows.
static func glow_dot(color: Color, billboard: bool = true) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [color.to_html(), billboard]
	if _materials.has(key):
		return _materials[key]
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_materials[key] = m
	return m


static func gold() -> Material:
	var path := "res://assets/materials/gold.tres"
	if not _materials.has(path):
		_materials[path] = load(path)
	return _materials[path]


static func sphere(radius: float, segments: int = 24, rings: int = 12) -> SphereMesh:
	return ellipsoid(radius, radius * 2.0, segments, rings)


static func ellipsoid(radius: float, height: float, segments: int = 24, rings: int = 12) -> SphereMesh:
	var key := "sph|%.3f|%.3f|%d|%d" % [radius, height, segments, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = segments
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> BoxMesh:
	var key := "box|%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func cylinder(top: float, bottom: float, height: float, segments: int = 16) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top, bottom, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "cap|%.3f|%.3f" % [radius, height]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		m.radial_segments = 20
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


static func prism(size: Vector3) -> PrismMesh:
	var key := "pri|%s" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func part(parent: Node, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, cast_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func pivot(parent: Node, pos: Vector3 = Vector3.ZERO, node_name: String = "") -> Node3D:
	var n := Node3D.new()
	if node_name != "":
		n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n
