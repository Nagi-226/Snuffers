// ow_noise.gdshaderinc — 周期噪声库
// 1:1 移植自 Claude-of-Duty src/materials/glsl/noise.js（见文档10 §1-P1）
// 全部函数周期化（per 参数）以保证无缝平铺。

// ---------------------------------------------------------------- hashes ----
float ow_hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
float ow_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 ow_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// ------------------------------------------------------- gradient noise ----
vec2 ow_grad2(vec2 i, vec2 per) {
	float a = ow_hash12(mod(i, per) + 0.317) * 6.28318530718;
	return vec2(cos(a), sin(a));
}

// 周期梯度（Perlin）噪声，返回约 [-1,1]
float ow_noise(vec2 p, vec2 per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(ow_grad2(i + vec2(0.0, 0.0), per), f - vec2(0.0, 0.0));
	float b = dot(ow_grad2(i + vec2(1.0, 0.0), per), f - vec2(1.0, 0.0));
	float c = dot(ow_grad2(i + vec2(0.0, 1.0), per), f - vec2(0.0, 1.0));
	float d = dot(ow_grad2(i + vec2(1.0, 1.0), per), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4142;
}
float ow_noise01(vec2 p, vec2 per) { return ow_noise(p, per) * 0.5 + 0.5; }

// ------------------------------------------------------------------ fbm ----
float ow_fbm(vec2 p, vec2 per, int oct, float gain) {
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < 10; i++) {
		if (i >= oct) { break; }
		s += a * ow_noise(p, per);
		n += a;
		p *= 2.0;
		per *= 2.0;
		a *= gain;
	}
	return s / max(n, 1e-4);
}
float ow_fbm01(vec2 p, vec2 per, int oct, float gain) { return ow_fbm(p, per, oct, gain) * 0.5 + 0.5; }

// Billow fbm — 蓬松团块，适合锈斑/黏土
float ow_billow(vec2 p, vec2 per, int oct, float gain) {
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < 10; i++) {
		if (i >= oct) { break; }
		s += a * abs(ow_noise(p, per));
		n += a;
		p *= 2.0;
		per *= 2.0;
		a *= gain;
	}
	return s / max(n, 1e-4);
}

// --------------------------------------------------------- domain warp -----
vec2 ow_warp(vec2 p, vec2 per, float amp, int oct) {
	vec2 q = vec2(ow_fbm(p + vec2(1.7, 9.2), per, oct, 0.5),
	              ow_fbm(p + vec2(8.3, 2.8), per, oct, 0.5));
	return p + amp * q;
}

// -------------------------------------------------------------- worley -----
// 周期 Worley/Voronoi: .x=F1距离 .y=F2距离 .z/.w=F1格hash
vec4 ow_worley(vec2 p, vec2 per, float jitter) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 cell = mod(ip + g, per);
			vec2 o = ow_hash22(cell + 0.771) * jitter + (1.0 - jitter) * 0.5;
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < f1) { f2 = f1; f1 = d; id = ow_hash22(cell + 3.117); }
			else if (d < f2) { f2 = d; }
		}
	}
	return vec4(sqrt(f1), sqrt(f2), id);
}

// ------------------------------------------------------------ utilities ----
// sRGB 书写习惯 → 线性输出（调色在伽马空间直观，渲染在线性空间）
vec3 ow_srgb(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}
// 保平铺的各向异性剪切（k/stretch 取整数格点才回绕）
vec2 ow_shear(vec2 p, float k, float stretch) {
	return vec2(p.x + p.y * k, p.y * stretch);
}
vec2 ow_shear_per(vec2 per, float stretch) {
	return vec2(per.x, per.y * stretch);
}
