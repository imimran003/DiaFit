#include <SwiftUI/SwiftUI.h>
using namespace metal;

// A deliberately restrained material pass. It creates a barely perceptible
// lens-like breathing in generated-food placeholders, avoiding aggressive UI
// distortion while image generations stream in.
[[ stitchable ]]
half4 lensPass(float2 position, SwiftUI::Layer layer, float2 size, float time) {
    float2 uv = position / max(size, float2(1.0));
    float wave = sin((uv.x * 1.7 + uv.y * 1.3 + time * 0.16) * 6.28318);
    float2 center = float2(0.5, 0.5);
    float distanceFromCenter = distance(uv, center);
    float strength = (1.0 - smoothstep(0.18, 0.78, distanceFromCenter)) * 0.65;
    float2 offset = normalize(uv - center + 0.001) * wave * strength;
    return layer.sample(position + offset);
}
