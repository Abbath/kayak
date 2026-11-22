shader_type spatial;

uniform vec4 water_color : source_color = vec4(0.1, 0.42, 0.62, 1.0);
uniform vec4 water_deep : source_color = vec4(0.04, 0.22, 0.42, 1.0);

varying vec3 world_pos;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.35 + TIME * 1.4) * 0.06;
	VERTEX.y += sin(VERTEX.z * 0.22 + TIME * 1.1) * 0.05;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	float sparkle = sin(world_pos.x * 0.55 + TIME * 1.8) * sin(world_pos.z * 0.37 - TIME * 1.3);
	ALBEDO = mix(water_deep.rgb, water_color.rgb, 0.62 + sparkle * 0.12);
	ROUGHNESS = 0.42;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
