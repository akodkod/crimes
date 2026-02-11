shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 overlay_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform float grid_line_width : hint_range(0.01, 0.2) = 0.05;
uniform bool world_oriented = true;

varying vec3 grid_pos;
varying vec3 grid_normal;

void vertex() {
	if (world_oriented) {
		grid_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		grid_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	} else {
		grid_pos = VERTEX;
		grid_normal = NORMAL;
	}
}

void fragment() {
	// 1x1m 3D checker pattern (works on any surface orientation)
	float checker = mod(floor(grid_pos.x) + floor(grid_pos.y) + floor(grid_pos.z), 2.0);

	// Strong lines every 5m on all axes
	// Exclude the axis aligned with the surface normal to avoid full-face lines
	vec3 m5 = mod(grid_pos, 5.0);
	vec3 dist5 = min(m5, 5.0 - m5) + abs(grid_normal) * 100.0;
	float min_dist = min(dist5.x, min(dist5.y, dist5.z));
	float aa = fwidth(min_dist);
	float line5 = 1.0 - smoothstep(grid_line_width * 0.5 - aa, grid_line_width * 0.5 + aa, min_dist);

	vec3 color = mix(base_color.rgb, overlay_color.rgb, checker * overlay_color.a);
	vec3 line_color = mix(base_color.rgb, overlay_color.rgb, overlay_color.a * 5.0);
	ALBEDO = mix(color, line_color, line5);
}
