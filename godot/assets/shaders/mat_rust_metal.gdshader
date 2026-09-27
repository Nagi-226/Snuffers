shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// mat_rust_metal.gdshader — 锈蚀金属
// 移植自 Claude-of-Duty surfaces-metal.js METAL_RUST（完整保留：钢板基色 +
// 扭曲billow锈斑 + 锈龄配色 + 鳞片剥落 + 深坑蚀穿）。三平面投影。
// 文档: desktop-port/godot-spike/10-claude-of-duty-borrowing.md §1-P1

#include "res://assets/shaders/ow_noise.gdshaderinc"

uniform float seed = 23.0;
uniform float world_scale = 1.2; // 金属件贴图周期更密（道具尺度分档纪律）

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 triplanar_uv(vec3 wp, vec3 wn) {
	vec3 an = abs(wn);
	if (an.y > an.x && an.y > an.z) { return wp.xz; }
	if (an.x > an.z) { return wp.zy; }
	return wp.xy;
}

// 锈色按「锈龄」而非「锈量」驱动：嫩锈橙 → 老锈红黑
vec3 ow_rust_colour(float t, float grain) {
	vec3 c1 = ow_srgb(vec3(0.560, 0.290, 0.110));
	vec3 c2 = ow_srgb(vec3(0.380, 0.180, 0.085));
	vec3 c3 = ow_srgb(vec3(0.190, 0.100, 0.060));
	vec3 c4 = ow_srgb(vec3(0.640, 0.400, 0.190));
	vec3 c = mix(c1, c2, smoothstep(0.15, 0.6, t));
	c = mix(c, c3, smoothstep(0.55, 1.0, t));
	c = mix(c, c4, smoothstep(0.55, 0.95, grain) * 0.45);
	return c * (0.82 + 0.36 * grain);
}

void fragment() {
	vec2 uv = triplanar_uv(v_world_pos, v_world_normal) / world_scale;
	vec2 P = vec2(8.0);
	vec2 p = uv * P + seed * 7.7;

	// 钢板基色（轧制纹 = 剪切域 fbm）
	float mill = ow_fbm01(ow_shear(p * 4.0, 1.0, 6.0), ow_shear_per(P * 4.0, 6.0), 4, 0.5);
	float fine = ow_fbm01(p * 22.0, P * 22.0, 4, 0.5);
	vec3 c = ow_srgb(vec3(0.330, 0.335, 0.345)) * (0.90 + 0.18 * mill);
	float rough = 0.40 + (mill - 0.5) * 0.16 + (fine - 0.5) * 0.08;
	float metal = 1.0;
	float ao = 1.0;

	// 锈斑: 扭曲 billow 团簇，剥落处硬边
	vec2 wp = ow_warp(p * 1.4, P * 1.4, 1.2, 4);
	float bloom = 1.0 - ow_billow(wp, P * 1.4, 5, 0.6);
	float spread = ow_fbm01(p * 0.7 + 12.0, P * 0.7, 3, 0.6);
	float rust = smoothstep(0.36, 0.72, bloom * (0.55 + 0.85 * spread));
	float rust_grain = ow_fbm01(p * 26.0, P * 26.0, 4, 0.55);
	float pit = ow_fbm01(p * 24.0, P * 24.0, 3, 0.5);

	// 鳞片剥落: 锈在团块边缘成片起翘
	float plate = ow_worley(p * 16.0, P * 16.0, 1.0).x;
	float flake = smoothstep(0.30, 0.10, plate) * smoothstep(0.25, 0.55, rust) * (1.0 - smoothstep(0.8, 1.0, rust));

	float rust_age = ow_fbm01(p * 0.85 + 21.0, P * 0.85, 4, 0.62);
	vec3 rust_col = ow_rust_colour(rust_age * 0.8 + rust * 0.3, rust_grain);
	c = mix(c, rust_col, rust);
	metal = mix(1.0, 0.0, smoothstep(0.15, 0.55, rust));
	rough = mix(rough, 0.86 + 0.10 * rust_grain, smoothstep(0.1, 0.6, rust));
	ao -= flake * 0.30 + smoothstep(0.6, 1.0, rust) * 0.15;
	ao -= smoothstep(0.5, 0.95, rust) * pit * 0.10;

	// 蚀穿深坑
	vec4 pits = ow_worley(p * 22.0, P * 22.0, 1.0);
	float deep = smoothstep(0.22, 0.0, pits.x) * step(0.72, pits.w) * smoothstep(0.3, 0.8, rust);
	ao -= deep * 0.45;
	c = mix(c, rust_col * 0.35, deep * 0.7);

	ALBEDO = c;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	AO = clamp(ao, 0.0, 1.0);
}
