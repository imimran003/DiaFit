#include <SwiftUI/SwiftUI.h>
using namespace metal;

// An intentionally restrained material pass. The food moves less than half a
// pixel; the effect reads as light moving through lacquered print, never as a
// UI wobble. This is especially important during matched-geometry travel.
[[ stitchable ]]
half4 lensPass(float2 position, SwiftUI::Layer layer, float2 size, float time) {
    float2 uv = position / max(size, float2(1.0));
    float wave = sin((uv.x * 1.7 + uv.y * 1.3 + time * 0.08) * 6.28318);
    float2 center = float2(0.5, 0.5);
    float distanceFromCenter = distance(uv, center);
    float strength = (1.0 - smoothstep(0.18, 0.78, distanceFromCenter)) * 0.32;
    float2 offset = normalize(uv - center + 0.001) * wave * strength;
    half4 sampled = layer.sample(position + offset);
    half sheen = half(0.006 * sin((uv.x - uv.y + time * 0.05) * 6.28318));
    return half4(min(sampled.rgb + sheen, half3(1.0)), sampled.a);
}
