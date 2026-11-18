#version 460 core

// The swirling paint behind the app.
//
// Ported to Flutter's fragment-shader dialect from the Balatro background
// component in React Bits by David Haz, which is MIT licensed:
// https://github.com/DavidHDev/react-bits  (src/content/Backgrounds/Balatro)
//
// What it does, in three steps: the coordinates are snapped to a coarse grid
// and turned about the centre by an angle that leans on the distance, which
// is the spin; five passes then fold the coordinates, each reading what the
// one before wrote, which is what marbles them; and the distance the folded
// point ends up at picks between three colours, sharpened by a contrast term
// so the bands meet in a line rather than a smear.
//
// The colours are not the original's red and blue: they are the two the
// player picked in settings, with the middle one derived from them, so the
// backdrop is the colour the rest of the app is drawn in.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uColour1;
uniform vec4 uColour2;
uniform vec4 uColour3;

out vec4 fragColor;

// The original's defaults, which are what make it look like itself.
const float kSpinRotation = -2.0;
const float kSpinSpeed = 7.0;
const float kSpinEase = 1.0;
const float kSpinAmount = 0.25;
const float kContrast = 3.5;
const float kLighting = 0.4;
const float kPixelFilter = 745.0;

void main() {
  vec2 screenSize = uSize;
  vec2 screen_coords = FlutterFragCoord().xy;

  float pixel_size = length(screenSize.xy) / kPixelFilter;
  vec2 uv =
      (floor(screen_coords.xy * (1.0 / pixel_size)) * pixel_size -
       0.5 * screenSize.xy) /
      length(screenSize.xy);
  float uv_len = length(uv);

  // The original offers a still version and a turning one; this turns, which
  // is the whole point of putting it behind a screen somebody sits in front
  // of for an evening.
  float speed = uTime * (kSpinRotation * kSpinEase * 0.2);
  speed += 302.2;

  float new_pixel_angle = atan(uv.y, uv.x) + speed -
      kSpinEase * 20.0 * (kSpinAmount * uv_len + (1.0 - kSpinAmount));
  vec2 mid = (screenSize.xy / length(screenSize.xy)) / 2.0;
  uv = vec2(uv_len * cos(new_pixel_angle) + mid.x,
            uv_len * sin(new_pixel_angle) + mid.y) -
      mid;

  uv *= 30.0;
  speed = uTime * kSpinSpeed;

  vec2 uv2 = vec2(uv.x + uv.y);
  for (int i = 0; i < 5; i++) {
    uv2 += sin(max(uv.x, uv.y)) + uv;
    uv += 0.5 * vec2(cos(5.1123314 + 0.353 * uv2.y + speed * 0.131121),
                     sin(uv2.x - 0.113 * speed));
    uv -= cos(uv.x + uv.y) - sin(uv.x * 0.711 - uv.y);
  }

  float contrast_mod = (0.25 * kContrast + 0.5 * kSpinAmount + 1.2);
  float paint_res = min(2.0, max(0.0, length(uv) * 0.035 * contrast_mod));
  float c1p = max(0.0, 1.0 - contrast_mod * abs(1.0 - paint_res));
  float c2p = max(0.0, 1.0 - contrast_mod * abs(paint_res));
  float c3p = 1.0 - min(1.0, c1p + c2p);
  float light = (kLighting - 0.2) * max(c1p * 5.0 - 4.0, 0.0) +
      kLighting * max(c2p * 5.0 - 4.0, 0.0);

  vec4 painted = (0.3 / kContrast) * uColour1 +
      (1.0 - 0.3 / kContrast) *
          (uColour1 * c1p + uColour2 * c2p +
           vec4(c3p * uColour3.rgb, c3p * uColour1.a)) +
      light;

  // Sat under the whole app rather than beside it: the paint is dimmed and
  // pulled toward the ground at the edges, so a menu is read against
  // something quiet and the swirl is still plainly there.
  vec3 ground = uColour3.rgb;
  vec3 colour = mix(ground, painted.rgb, 0.72);
  float edge = length((screen_coords - 0.5 * screenSize) / length(screenSize));
  colour = mix(colour, ground, smoothstep(0.18, 0.62, edge) * 0.45);

  fragColor = vec4(colour, 1.0);
}
