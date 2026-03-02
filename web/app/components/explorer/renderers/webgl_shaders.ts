// GLSL shaders for the WebGL RTL schematic renderer.

export const RECT_VERTEX = `#version 300 es
precision highp float;

// Per-instance attributes
layout(location = 0) in vec2 a_position;    // center x, y
layout(location = 1) in vec2 a_size;        // width, height
layout(location = 2) in vec4 a_fillColor;
layout(location = 3) in vec4 a_strokeColor;
layout(location = 4) in float a_strokeWidth;
layout(location = 5) in float a_cornerRadius;

// Per-vertex quad corner (0..1, 0..1)
layout(location = 6) in vec2 a_quadCorner;

uniform mat3 u_viewMatrix;
uniform vec2 u_resolution;

out vec2 v_uv;
out vec2 v_size;
out vec4 v_fillColor;
out vec4 v_strokeColor;
out float v_strokeWidth;
out float v_cornerRadius;

void main() {
  vec2 local = (a_quadCorner - 0.5) * a_size;
  vec2 world = a_position + local;
  vec3 clip = u_viewMatrix * vec3(world, 1.0);
  gl_Position = vec4(
    (clip.x / u_resolution.x) * 2.0 - 1.0,
    1.0 - (clip.y / u_resolution.y) * 2.0,
    0.0, 1.0
  );
  v_uv = a_quadCorner;
  v_size = a_size;
  v_fillColor = a_fillColor;
  v_strokeColor = a_strokeColor;
  v_strokeWidth = a_strokeWidth;
  v_cornerRadius = a_cornerRadius;
}
`;

export const RECT_FRAGMENT = `#version 300 es
precision highp float;

in vec2 v_uv;
in vec2 v_size;
in vec4 v_fillColor;
in vec4 v_strokeColor;
in float v_strokeWidth;
in float v_cornerRadius;

out vec4 fragColor;

float sdfRoundedRect(vec2 p, vec2 b, float r) {
  vec2 d = abs(p) - b + vec2(r);
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void main() {
  vec2 pixelPos = (v_uv - 0.5) * v_size;
  vec2 halfSize = v_size * 0.5;
  float r = min(v_cornerRadius, min(halfSize.x, halfSize.y));
  float dist = sdfRoundedRect(pixelPos, halfSize, r);

  float fillAlpha = 1.0 - smoothstep(-1.0, 0.0, dist);
  float strokeAlpha = 1.0 - smoothstep(v_strokeWidth - 1.0, v_strokeWidth, abs(dist));

  vec4 color = mix(v_fillColor * fillAlpha, v_strokeColor, strokeAlpha * v_strokeColor.a);
  color.a = max(fillAlpha * v_fillColor.a, strokeAlpha * v_strokeColor.a);
  if (color.a < 0.01) discard;
  fragColor = color;
}
`;

export const LINE_VERTEX = `#version 300 es
precision highp float;

layout(location = 0) in vec2 a_start;
layout(location = 1) in vec2 a_end;
layout(location = 2) in vec4 a_color;
layout(location = 3) in float a_width;
layout(location = 4) in float a_vertexIndex;

uniform mat3 u_viewMatrix;
uniform vec2 u_resolution;

out vec4 v_color;

void main() {
  vec2 dir = a_end - a_start;
  vec2 normal = normalize(vec2(-dir.y, dir.x));

  // Expand line segment into a thin quad
  float side = (mod(a_vertexIndex, 2.0) < 1.0) ? -1.0 : 1.0;
  float along = (a_vertexIndex < 2.0) ? 0.0 : 1.0;

  vec2 world = mix(a_start, a_end, along) + normal * side * a_width * 0.5;
  vec3 clip = u_viewMatrix * vec3(world, 1.0);
  gl_Position = vec4(
    (clip.x / u_resolution.x) * 2.0 - 1.0,
    1.0 - (clip.y / u_resolution.y) * 2.0,
    0.0, 1.0
  );
  v_color = a_color;
}
`;

export const LINE_FRAGMENT = `#version 300 es
precision highp float;

in vec4 v_color;
out vec4 fragColor;

void main() {
  fragColor = v_color;
}
`;
