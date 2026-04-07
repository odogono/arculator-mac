#include <metal_stdlib>

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texcoord;
};

vertex VertexOut arculator_passthrough_vertex(uint vertex_id [[vertex_id]])
{
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0),
    };
    constexpr float2 texcoords[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0),
    };

    VertexOut out;
    out.position = float4(positions[vertex_id], 0.0, 1.0);
    out.texcoord = texcoords[vertex_id];
    return out;
}

fragment float4 arculator_passthrough_fragment(VertexOut in [[stage_in]],
                                               texture2d<float> source [[texture(0)]],
                                               sampler textureSampler [[sampler(0)]],
                                               constant float4 &sourceRect [[buffer(0)]])
{
    float2 uv = mix(sourceRect.xy, sourceRect.zw, in.texcoord);
    return source.sample(textureSampler, uv);
}
