shader_type canvas_item;

uniform vec2 size = vec2(100.0, 20.0);
uniform float dash_length_x: hint_range(1, 10) = 5.0;
uniform float dash_length_y: hint_range(1, 10) = 5.0;
uniform float moving_speed: hint_range(0.0, 1.0, 0.001) = 0.0;
uniform bool show_top = true;
uniform bool show_bottom = true;
uniform bool show_left = true;
uniform bool show_right = true;

void fragment() {
	vec2 uv = UV;
	uv.x += TIME * moving_speed;
	
	uv.x = uv.x * size.x / dash_length_x;
	float id_x = floor(uv.x);
	uv.x -= id_x;
	
	uv.y = uv.y * size.y / dash_length_y;
	float id_y = floor(uv.y);
	uv.y -= id_y;
	
	//COLOR.a = 1.0 - step(1.0, mod(id_x + id_y, 2.0));
	float a = step(1.0, mod(id_x + id_y, 2.0));
	if (a > 0.0) {
		if (!show_left) {
			a *= float(id_x > 0.0);
		}
		if (!show_right) {
			a *= float(id_x + dash_length_x < size.x / dash_length_x);
		}
		if (!show_top) {
			a *= float(id_y > 0.0);
		}
		if (!show_bottom) {
			a *= float(id_y + dash_length_y < size.y / dash_length_y);
		}
	}
	COLOR.a = a;
}
