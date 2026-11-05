/// Metal source compiled at runtime (`makeLibrary(source:)`), so plain `swift build` works
/// without Xcode's offline Metal compiler.
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 origin; // overlay origin, global points
        float2 size;   // overlay size, points
    };

    struct FlakeOut {
        float4 position [[position]];
        float2 uv;     // -1…1 across the quad
        float alpha;
        float core;    // flake radius as a fraction of the quad half-extent
    };

    // Instanced quad: 4-vertex triangle strip per sprite (x, y, radius, alpha).
    vertex FlakeOut flakeVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device float4 *sprites [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]]) {
        float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
        float4 s = sprites[iid];
        float extent = s.z * 1.6 + 0.75; // soft halo plus anti-aliasing room, points
        float2 p = s.xy + corner * extent;
        FlakeOut out;
        out.position = float4((p - u.origin) / u.size * 2.0 - 1.0, 0.0, 1.0);
        out.uv = corner;
        out.alpha = s.w;
        out.core = s.z / extent;
        return out;
    }

    // Soft round flake, premultiplied white.
    fragment float4 flakeFragment(FlakeOut in [[stage_in]]) {
        float d = length(in.uv);
        float a = in.alpha * (1.0 - smoothstep(in.core * 0.45, 1.0, d));
        return float4(a, a, a, a);
    }
    """
}
