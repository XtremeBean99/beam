shader_type canvas_item;

// Render the sprite as a flat white silhouette (alpha straight from the texture),
// so colourful source art matches the game's monochrome white look. Multiplying by
// COLOR keeps modulate (tint / fade-in) working and the transparent surround clear.
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(1.0, 1.0, 1.0, tex.a) * COLOR;
}
