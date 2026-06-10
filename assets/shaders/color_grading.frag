#version 460 core

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform sampler2D uTexture;
uniform float uBrightness; // -1.0 to 1.0
uniform float uContrast;   // 0.0 to 2.0
uniform float uSaturation; // 0.0 to 2.0
uniform float uHue;        // -3.14 to 3.14

out vec4 fragColor;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 color = texture(uTexture, uv);

    // 1. Brightness
    color.rgb += uBrightness;

    // 2. Contrast
    color.rgb = (color.rgb - 0.5) * uContrast + 0.5;

    // 3. Saturation & Hue
    vec3 hsv = rgb2hsv(color.rgb);
    hsv.x += uHue / (2.0 * 3.14159);
    hsv.y *= uSaturation;
    color.rgb = hsv2rgb(hsv);

    fragColor = color;
}
