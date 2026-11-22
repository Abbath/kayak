shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 water_color : source_color = vec4(0.1, 0.42, 0.62, 1.0);
uniform vec4 water_deep : source_color = vec4(0.04, 0.22, 0.42, 1.0);

varying vec3 world_pos;
varying float foam;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.35 + TIME * 1.4) * 0.06;
	VERTEX.y += sin(VERTEX.z * 0.22 + TIME * 1.1) * 0.05;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	foam = COLOR.a;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	float sparkle = sin(world_pos.x * 0.55 + TIME * 1.8) * sin(world_pos.z * 0.37 - TIME * 1.3);
	vec3 water = mix(water_deep.rgb, water_color.rgb, 0.62 + sparkle * 0.12);
	ALBEDO = mix(water, vec3(0.82, 0.91, 0.94), foam);
	ALPHA = mix(0.74, 0.94, foam);
	ROUGHNESS = mix(0.42, 0.16, foam);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
