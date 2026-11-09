#include <flutter/runtime_effect.glsl>
precision highp float;  //ADDED SEMICOLON

uniform vec2 u_resolution;
uniform float u_time;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / u_resolution.xy;
    float numBars = 8.0;       
    float speed = .5;         
    float barThickness = 0.3;  

    float movement = (uv.y * numBars) - (u_time * speed);
    float pattern = fract(movement);

    float isBar = step(1.0 - barThickness, pattern);

    vec3 yellow = vec3(1.0, 0.85, 0.0); 
    vec3 background = vec3(1.0, 1.0, 1.0); // Dark grey

    vec3 finalColor = mix(background, yellow, isBar);

    fragColor = vec4(finalColor, 1.0);
}