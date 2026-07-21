shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;

// EXPOSE PARAMETERS TO CONTROL YOUR WIND SPEED AND TEXTURAL DRIFT
uniform vec4 wind_color : source_color = vec4(1.0, 1.0, 1.0, 0.25);
uniform float scroll_speed : hint_range(0.0, 10.0) = 4.5;
uniform float texture_tiling : hint_range(0.1, 20.0) = 2.0;

// This exposes the Noise Texture slot directly to your Inspector panel below!
uniform sampler2D noise_texture : hint_default_white;

void fragment() {
	// 1. SCROLL THE TEXTURE COORDINATES CONTINUOUSLY DOWN THE LONG AXIS
	vec2 moving_uv = UV;
	moving_uv.x *= texture_tiling;
	moving_uv.y = (UV.y * texture_tiling) - (TIME * scroll_speed);
	
	// 2. SAMPLE OUR TEXTURE AND BREAK COHESION
	vec4 noise_sample = texture(noise_texture, moving_uv);
	
	// 3. DEFINE FINAL COLOR INPUTS
	ALBEDO = wind_color.rgb;
	
	// Alpha is determined by multiplying your opacity settings against the scrolling noise gaps, 
	// making the wind "play around each other" natively with zero harsh digital outlines!
	ALPHA = wind_color.a * noise_sample.r * (1.0 - UV.y); // Fades out gently towards the far tip!
}