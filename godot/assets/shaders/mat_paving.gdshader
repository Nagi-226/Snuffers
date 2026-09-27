shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// mat_paving.gdshader — 巷弄石板路（人行道石板砖变体）
// 2026-09-27 机主裁决：巷内地面改用石板路（参考人行道马路牙子上石板）。
// 错缝石板网格 + 砖缝砂浆 + 逐块色差 + 表面磨损噪点。世界空间 XZ 投影，无需 UV。

#include "res://assets/shaders/ow_noise.gdshaderinc"

uniform float seed = 5.0;
uniform float world_scale = 1.0; // 尺度分档：道具级 1.0m（文档10 §1-P1）
uniform float slab_size = 0.55;  // 石板边长（米）

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world_pos.xz / world_scale;

	// 错缝石板网格：奇数行横向偏移半块
	vec2 g = uv / slab_size;
	g.x += mod(floor(g.y), 2.0) * 0.5;
	vec2 cell = floor(g);
	vec2 f = fract(g);

	// 砖缝（砂浆）：四边收边
	float gw = 0.055; // 缝宽（砖边比例）
	float grout = max(
		max(step(f.x, gw), step(1.0 - gw, f.x)),
		max(step(f.y, gw), step(1.0 - gw, f.y)));

	// 逐块色差 + 微倾斜感（hash）
	float h1 = ow_hash12(cell + seed * 7.31);
	float h2 = ow_hash12(cell * 1.71 + seed * 3.97);

	// 石板基色：青灰系，逐块深浅
	vec3 c_light = ow_srgb(vec3(0.435, 0.430, 0.415));
	vec3 c_mid = ow_srgb(vec3(0.330, 0.328, 0.320));
	vec3 c_dark = ow_srgb(vec3(0.235, 0.232, 0.228));
	vec3 c = mix(c_mid, c_light, h1);
	c = mix(c, c_dark, h2 * 0.45);

	// 板面磨损与污渍噪点
	vec2 p = uv * 3.0 + seed * 11.7;
	float wear = ow_fbm01(p, vec2(64.0), 4, 0.55);
	c *= 0.88 + 0.24 * wear;
	float stain = ow_fbm01(uv * 0.6 + seed * 5.3, vec2(32.0), 3, 0.55);
	c *= 0.90 + 0.18 * smoothstep(0.35, 0.75, stain);

	// 板内微起伏：中心略凸（踩踏抛光），边缘略暗
	vec2 d_edge = min(f, vec2(1.0) - f) / gw;
	float dome = clamp(min(d_edge.x, d_edge.y), 0.0, 1.0);
	c *= 0.92 + 0.08 * dome;

	// 砖缝砂浆：深灰 + 噪点破碎
	vec3 c_grout = ow_srgb(vec3(0.145, 0.142, 0.138)) * (0.85 + 0.3 * ow_fbm01(p * 2.0, vec2(64.0), 3, 0.5));
	c = mix(c, c_grout, grout);

	float rough = 0.78 + (h2 - 0.5) * 0.12 + grout * 0.15;
	float ao = 1.0 - grout * 0.35;

	ALBEDO = c;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	AO = clamp(ao, 0.0, 1.0);
}
