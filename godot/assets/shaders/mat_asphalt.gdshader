shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// mat_asphalt.gdshader — 沥青路面
// 移植自 Claude-of-Duty surfaces-ground.js ASPHALT（精简：保留粘结剂基色 +
// 三级棱角骨料；去裂缝/标线层）。骨料棱角感来自 worley 域扭曲。三平面投影。
// 文档: desktop-port/godot-spike/10-claude-of-duty-borrowing.md §1-P1

#include "res://assets/shaders/ow_noise.gdshaderinc"

uniform float seed = 47.0;
uniform float world_scale = 2.5;

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
	vec2 p = uv * P + seed * 6.9;

	// 粘结剂: 深蓝灰基色，日照漂白斑块
	float macro = ow_fbm01(p * 0.55, P * 0.5, 4, 0.6);
	float mid = ow_fbm01(p * 3.0, P * 3.0, 5, 0.5);
	float fine = ow_fbm01(p * 16.0, P * 16.0, 4, 0.5);

	vec3 c_fresh = ow_srgb(vec3(0.115, 0.115, 0.122));
	vec3 c_worn = ow_srgb(vec3(0.300, 0.298, 0.295));
	vec3 c = mix(c_fresh, c_worn, smoothstep(0.25, 0.85, macro) * 0.85);
	c *= 0.94 + 0.12 * fine;

	float rough = 0.78 + (mid - 0.5) * 0.10 + (fine - 0.5) * 0.14;
	float ao = 1.0;

	// 骨料: 三级角砾，域扭曲让圆胞变棱角（沥青与鹅卵石滩的区别）
	vec2 ap = ow_warp(p, P, 0.10, 3);
	vec4 big = ow_worley(ap * 12.0, P * 12.0, 1.0);
	float big_m = smoothstep(0.40, 0.16, big.x);
	float big_exposed = big_m * smoothstep(0.30, 0.62, ow_fbm01(p * 2.2 + 3.0, P * 2.0, 4, 0.5) + big.w * 0.5);
	vec4 small = ow_worley(ap * 22.0 + 7.0, P * 22.0, 1.0);
	float small_m = smoothstep(0.36, 0.10, small.x);
	float small_exposed = small_m * step(0.30, small.w);
	vec4 grit = ow_worley(ap * 28.0 + 3.0, P * 28.0, 1.0);
	float grit_m = smoothstep(0.32, 0.06, grit.x) * step(0.45, grit.z);

	vec3 stone_a = ow_srgb(vec3(0.400, 0.392, 0.378));
	vec3 stone_b = ow_srgb(vec3(0.210, 0.200, 0.192));
	vec3 stone_c = ow_srgb(vec3(0.560, 0.520, 0.470));
	vec3 stone = mix(stone_a, stone_b, big.z);
	stone = mix(stone, stone_c, step(0.90, big.w));

	// 石头靠起伏和高光读，不靠色相对比：颜色对比减半
	c = mix(c, stone, big_exposed * 0.52);
	c = mix(c, mix(stone_a, stone_c, small.z), small_exposed * 0.22);
	c = mix(c, stone_a, grit_m * 0.15);
	rough -= big_exposed * 0.10 + small_exposed * 0.06;
	ao -= big_m * 0.05 + grit_m * 0.04;

	ALBEDO = c;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	AO = clamp(ao, 0.0, 1.0);
}
