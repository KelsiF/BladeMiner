shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// --- параметры ---
uniform bool use_scanlines = true;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;

uniform bool use_vignette = true;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.6;

uniform bool use_color_grade = true;
uniform vec3 tint = vec3(1.0, 0.98, 0.9);
uniform float saturation : hint_range(0.0, 2.0) = 1.05;
uniform float contrast : hint_range(0.0, 2.0) = 1.05;

uniform bool use_dither = false;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.05;

void fragment() {
    vec4 col = texture(screen_texture, SCREEN_UV);

    // цветокоррекция
    if (use_color_grade) {
        col.rgb *= tint;
        float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
        col.rgb = mix(vec3(gray), col.rgb, saturation);
        col.rgb = (col.rgb - 0.5) * contrast + 0.5;
    }

    // сканлайны (полоски CRT)
    if (use_scanlines) {
        float line = sin(SCREEN_UV.y * 720.0) * 0.5 + 0.5;
        col.rgb *= 1.0 - (line * scanline_strength);
    }

    // виньетка
    if (use_vignette) {
        vec2 uv = SCREEN_UV - 0.5;
        float vig = 1.0 - dot(uv, uv) * vignette_strength;
        col.rgb *= clamp(vig, 0.0, 1.0);
    }

    // лёгкий дизеринг, чтобы не было бандинга при градиентах
    if (use_dither) {
        float noise = fract(sin(dot(SCREEN_UV, vec2(12.9898,78.233))) * 43758.5453);
        col.rgb += (noise - 0.5) * dither_strength * 0.05;
    }

    COLOR = col;
}