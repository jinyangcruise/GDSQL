shader_type canvas_item;

uniform float total_length = 100.0;
uniform float dash_length_x: hint_range(1, 10) = 5.0;
uniform float moving_speed: hint_range(0.0, 1.0, 0.001) = 0.0;

void fragment() {
	vec2 uv = UV;
	uv.x += TIME * moving_speed;
	
	uv.x = uv.x * total_length / dash_length_x;
	float id_x = floor(uv.x);
	uv.x -= id_x;
	
	COLOR.a = 1.0 - step(1.0, mod(id_x, 2.0));
}
