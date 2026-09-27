shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// mat_concrete.gdshader — 混凝土（浇筑板变体）
// 移植自 Claude-of-Duty surfaces-arch.js CONCRETE（精简：去模板缝/锯缝，保留
// 浇筑色差/冲刷带/露骨料/砂粒/气孔五层）。三平面世界空间投影，无需 UV。
// 文档: desktop-port/godot-spike/10-claude-of-duty-borrowing.md §1-P1

#include "res://assets/shaders/ow_noise.gdshaderinc"

uniform float seed = 11.0;
uniform float world_scale = 2.5; // 一个纹理周期跨越的米数

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

void fragment() {
	vec2 uv = triplanar_uv(v_world_pos, v_world_normal) / world_scale;
	vec2 P = vec2(8.0);
	vec2 p = uv * P + seed * 13.7;

	// 基色: 浇筑色差 + 水泥霜花
	float macro = ow_fbm01(p * 0.5, P * 0.5, 4, 0.58);
	float mid = ow_fbm01(ow_warp(p * 2.0, P * 2.0, 0.7, 3), P * 2.0, 5, 0.5);
	float fine = ow_fbm01(p * 18.0, P * 18.0, 4, 0.5);
	float micro = ow_fbm01(p * 26.0, P * 26.0, 3, 0.5);

	vec3 c_light = ow_srgb(vec3(0.520, 0.512, 0.492));
	vec3 c_mid = ow_srgb(vec3(0.395, 0.392, 0.385));
	vec3 c_dark = ow_srgb(vec3(0.255, 0.253, 0.258));
	vec3 c = mix(c_mid, c_light, smoothstep(0.35, 0.85, macro));
	c = mix(c, c_dark, smoothstep(0.55, 0.95, mid) * 0.55);
	c *= 0.93 + 0.14 * fine;

	// 0.1–1m 浇筑斑块带 + 雨水冲刷带
	float pour_b = ow_fbm01(ow_warp(p * 1.5 + 8.3, P * 1.5, 0.6, 3), P * 1.5, 4, 0.58);
	pour_b = clamp((pour_b - 0.5) * 2.5 + 0.5, 0.0, 1.0);
	c *= 0.82 + 0.38 * pour_b;
	float wash = ow_fbm01(p * 7.0 + 2.0, P * 7.0, 4, 0.5);
	wash = clamp((wash - 0.5) * 2.2 + 0.5, 0.0, 1.0);
	c *= 0.925 + 0.155 * wash;

	float rough = 0.70 + (mid - 0.5) * 0.16 + (micro - 0.5) * 0.07;
	float ao = 1.0;

	// 露骨料: 皮下石屑局部翻出
	vec4 agg = ow_worley(p * 13.0, P * 13.0, 0.95);
	float agg_shape = smoothstep(0.46, 0.10, agg.x);
	float agg_exposed = agg_shape * step(0.74, ow_fbm01(p * 3.0 + 5.0, P * 3.0, 3, 0.5) + agg.z * 0.35);
	c = mix(c, mix(ow_srgb(vec3(0.335, 0.320, 0.300)), ow_srgb(vec3(0.560, 0.545, 0.505)), agg.z), agg_exposed * 0.7);
	rough += agg_exposed * 0.07 * (agg.z - 0.5);

	// 粗砂颗粒
	vec4 sand = ow_worley(p * 20.0, P * 20.0, 1.0);
	float sand_m = smoothstep(0.44, 0.05, sand.x);
	float sand_sel = 0.40 + 0.60 * step(0.30, sand.z);
	c *= 1.0 + (sand_m * sand_sel - 0.20) * 0.15;
	rough += (sand.z - 0.5) * 0.11 + sand_m * 0.04;
	ao -= sand_m * 0.06;
	float sand_trough = smoothstep(0.52, 0.88, sand.x);
	c = mix(c, c * 0.86, sand_trough * 0.34);

	// 浇筑气孔
	vec4 pores = ow_worley(p * 22.0, P * 22.0, 1.0);
	float pore = smoothstep(0.26, 0.0, pores.x) * step(0.84, pores.w);
	ao -= pore * 0.55;
	rough += pore * 0.10;

	ALBEDO = c;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	AO = clamp(ao, 0.0, 1.0);
}
