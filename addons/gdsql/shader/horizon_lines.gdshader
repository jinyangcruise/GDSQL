shader_type canvas_item;

uniform float total_length = 100.0;
uniform float dash_length_y: hint_range(1, 10) = 5.0;
uniform float moving_speed: hint_range(0.0, 1.0, 0.001) = 0.0;

void fragment() {
	vec2 uv = UV;
	uv.y += TIME * moving_speed;
	
	uv.y = uv.y * total_length / dash_length_y;
	float id_y = floor(uv.y);
	uv.y -= id_y;
	
	COLOR.a = 1.0 - step(1.0, mod(id_y, 2.0));
}
