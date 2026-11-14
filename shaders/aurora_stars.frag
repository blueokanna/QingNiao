#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec3 uSurface;
uniform vec3 uAccent;
uniform vec3 uStar;
uniform float uAmoled;
uniform sampler2D uAtlas;
out vec4 fragColor;

float randomValue(float cell, float seed) {
  return fract(sin(cell * 17.17 + seed * 109.13) * 43758.5453);
}

// Quintic interpolation: value, velocity and acceleration meet at each knot.
// Independent, non-looping low-frequency noise avoids a synchronized pulse.
float slowNoise(float time, float seed) {
  float index = floor(time);
  float f = fract(time);
  float blend = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(randomValue(index, seed), randomValue(index + 1.0, seed), blend) * 2.0 - 1.0;
}

vec3 parameters(vec2 cell, float column) {
  vec2 pixel = vec2(mod(cell.x, 8.0) * 4.0 + column, mod(cell.y, 32.0));
  return texture(uAtlas, (pixel + 0.5) / 32.0).rgb;
}

void main() {
  vec2 point = FlutterFragCoord().xy;
  float cellSize = max(uSize.x / 6.0, 48.0);
  vec2 cell = floor(point / cellSize);
  float glow = (1.0 - clamp(length(point - uSize * vec2(0.1, 0.05)) /
      max(uSize.x * 0.9, 1.0), 0.0, 1.0)) * 0.12 * (1.0 - uAmoled);
  vec3 base = mix(uSurface, uAccent, glow);
  vec3 geometry = parameters(cell, 0.0);
  vec2 anchor = (cell + 0.18 + 0.64 * geometry.rg) * cellSize;
  float radius = 0.48 + 0.82 * geometry.b;
  // Most fragments are empty sky. Skip noise evaluation outside the maximum
  // star + halo + drift bounds instead of running it across the full screen.
  if (any(greaterThan(abs(point - anchor), vec2(radius * 2.6 + 1.5)))) {
    fragColor = vec4(base, 1.0);
    return;
  }
  vec3 light = parameters(cell, 1.0);
  vec3 motion = parameters(cell, 2.0);
  vec3 seeds = parameters(cell, 3.0);
  if (seeds.b < 0.5) {
    fragColor = vec4(base, 1.0);
    return;
  }
  float period = mix(64.0, 160.0, light.b);
  float phase = light.g * 73.0;
  float shimmer = 0.65 * slowNoise(uTime / period + phase, seeds.r + 1.0)
      + 0.35 * slowNoise(uTime / (period * 2.37) + phase, seeds.g + 3.0);
  float driftPeriod = mix(240.0, 600.0, motion.g);
  vec2 drift = vec2(
      slowNoise(uTime / driftPeriod + phase, seeds.r + 5.0),
      slowNoise(uTime / (driftPeriod * 1.73) + phase, seeds.g + 7.0));
  vec2 center = anchor + drift * (0.25 + 0.95 * motion.r);
  float distanceToStar = length(point - center);
  float core = 1.0 - smoothstep(max(0.0, radius - 0.5), radius + 0.5, distanceToStar);
  float halo = (1.0 - smoothstep(radius, radius * 2.6, distanceToStar))
      * smoothstep(0.75, 1.0, light.r) * 0.025 * (1.0 - uAmoled);
  float alpha = (core * (mix(0.10, 0.18, uAmoled) + light.r * 0.18 + shimmer * 0.018)
      + halo) * seeds.b;
  vec3 spectrum = mix(vec3(0.90, 0.95, 1.0), vec3(1.0, 0.95, 0.88), motion.b);
  fragColor = vec4(mix(base, uStar * spectrum, alpha), 1.0);
}
