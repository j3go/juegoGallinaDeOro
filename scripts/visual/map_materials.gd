@tool
class_name MapMaterials
extends RefCounted
## Procedural shader "textures" for the map: patterns live in the surface itself, so there
## are no stray decal-like blobs and no overlapping ground layers fighting for depth.

const NOISE := """
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.03) * 0.3 + noise(p * 4.1) * 0.15;
}
"""

## Blotches on a base colour (cow spots, dirt, rust, mottled rock). Object space, so the
## pattern sticks to the mesh.
const SPOTS_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 spot_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float spot_scale = 2.5;
uniform float spot_amount = 0.35;
uniform float softness = 0.03;
uniform float grain = 0.08;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform float rim = 0.2;
uniform vec3 seed = vec3(0.0);
varying vec3 local_pos;
%s
void vertex() {
	local_pos = VERTEX;
}
void fragment() {
	vec3 p = local_pos * spot_scale + seed;
	float n = fbm(p);
	float s = smoothstep(1.0 - spot_amount - softness, 1.0 - spot_amount + softness, n);
	vec3 col = mix(base_color.rgb, spot_color.rgb, s);
	col *= 1.0 - grain * 0.5 + grain * noise(local_pos * 18.0);
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	RIM = rim;
	RIM_TINT = 0.7;
}
"""

## Staggered stone bricks with mortar lines, picked per face from the dominant normal axis.
const BRICK_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.42, 0.4, 0.42, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.22, 0.21, 0.23, 1.0);
uniform vec2 brick_size = vec2(0.7, 0.35);
uniform float mortar = 0.035;
varying vec3 local_pos;
varying vec3 local_normal;
%s
void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec3 an = abs(local_normal);
	vec2 uv = an.x > an.y && an.x > an.z ? local_pos.zy : (an.z > an.y ? local_pos.xy : local_pos.xz);
	uv /= brick_size;
	float row = floor(uv.y);
	uv.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	vec2 m = mortar / brick_size;
	float line = max(1.0 - smoothstep(0.0, m.x, min(f.x, 1.0 - f.x)), 1.0 - smoothstep(0.0, m.y, min(f.y, 1.0 - f.y)));
	float tint = hash(vec3(cell, row * 0.37 + 3.1));
	vec3 col = base_color.rgb * (0.82 + 0.3 * tint) * (0.92 + 0.16 * noise(local_pos * 9.0));
	ALBEDO = mix(col, mortar_color.rgb, line);
	ROUGHNESS = 0.95;
}
"""

## Ground: mud with darker patches, a dirt path ring around the crater and grassy areas.
const GROUND_SHADER := """
shader_type spatial;
uniform vec4 mud : source_color;
uniform vec4 mud_dark : source_color;
uniform vec4 path : source_color;
uniform vec4 grass : source_color;
uniform vec2 crater = vec2(0.5, 0.0);
varying vec3 world_pos;
%s
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = mix(mud_dark.rgb, mud.rgb, smoothstep(0.3, 0.7, fbm(vec3(p * 0.15, 1.7))));
	float wobble = (fbm(vec3(p * 0.4, 5.0)) - 0.5) * 1.6;
	float ring = 1.0 - smoothstep(1.0, 2.0, abs(length(p - crater) - 5.6 + wobble));
	float lane = 1.0 - smoothstep(0.9, 1.8, abs(p.x - 0.5 + sin(p.y * 0.3) * 1.2 + wobble));
	float path_mask = clamp(max(ring, lane * smoothstep(13.0, 9.0, abs(p.y))), 0.0, 1.0);
	col = mix(col, path.rgb, path_mask * 0.85);
	float grass_mask = smoothstep(0.55, 0.64, fbm(vec3(p * 0.2, 9.3))) * (1.0 - path_mask);
	col = mix(col, grass.rgb, grass_mask);
	col *= 0.88 + 0.24 * noise(vec3(p * 2.2, 0.0));
	ALBEDO = col;
	ROUGHNESS = 0.97;
}
"""

static var _shaders := {}
static var _cache := {}


static func spots(base: Color, spot: Color, scale: float, amount: float, roughness: float = 0.8,
		metallic: float = 0.0, rim: float = 0.2, softness: float = 0.03) -> ShaderMaterial:
	var key := "spots|%s|%s|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f" % [base.to_html(), spot.to_html(), scale, amount, roughness, metallic, rim, softness]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("spots", SPOTS_SHADER)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("spot_color", spot)
	m.set_shader_parameter("spot_scale", scale)
	m.set_shader_parameter("spot_amount", amount)
	m.set_shader_parameter("softness", softness)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("seed", Vector3(base.r * 13.0, spot.g * 7.0, scale))
	_cache[key] = m
	return m


static func bricks(base: Color, mortar_color: Color, brick_size: Vector2 = Vector2(0.7, 0.35)) -> ShaderMaterial:
	var key := "bricks|%s|%s|%s" % [base.to_html(), mortar_color.to_html(), brick_size]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("bricks", BRICK_SHADER)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("mortar_color", mortar_color)
	m.set_shader_parameter("brick_size", brick_size)
	_cache[key] = m
	return m


static func ground(mud: Color, mud_dark: Color, path: Color, grass: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("ground", GROUND_SHADER)
	m.set_shader_parameter("mud", mud)
	m.set_shader_parameter("mud_dark", mud_dark)
	m.set_shader_parameter("path", path)
	m.set_shader_parameter("grass", grass)
	return m


static func _shader(id: String, template: String) -> Shader:
	if not _shaders.has(id):
		var s := Shader.new()
		s.code = template % NOISE
		_shaders[id] = s
	return _shaders[id]
