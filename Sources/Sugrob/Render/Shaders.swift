/// Metal source compiled at runtime (`makeLibrary(source:)`), so plain `swift build` works
/// without Xcode's offline Metal compiler.
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // Must match `RenderUniforms` in SnowRenderer.swift (2 × float4).
    struct Uniforms {
        float2 origin; // overlay origin, global points
        float2 size;   // overlay size, points
        float scale;   // pixels per point
        float3 pad;
    };

    static float4 toClip(float2 p, constant Uniforms &u) {
        return float4((p - u.origin) / u.size * 2.0 - 1.0, 0.0, 1.0);
    }

    // MARK: Flakes

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
        FlakeOut out;
        out.position = toClip(s.xy + corner * extent, u);
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

    // MARK: Debris

    struct DebrisOut {
        float4 position [[position]];
        float2 uv;      // x across, y along the velocity (-1 tail … +1 head)
        float alpha;
        float aspect;   // half-length / half-width
    };

    // Instance = 2 × float4: (x, y, radius, alpha), (vx, vy, 0, 0).
    // The quad is stretched along the velocity into a short motion streak.
    vertex DebrisOut debrisVertex(uint vid [[vertex_id]],
                                  uint iid [[instance_id]],
                                  const device float4 *particles [[buffer(0)]],
                                  constant Uniforms &u [[buffer(1)]]) {
        float4 s = particles[iid * 2];
        float2 v = particles[iid * 2 + 1].xy;
        float speed = length(v);
        float2 along = speed > 1.0 ? v / speed : float2(0.0, -1.0);
        float2 across = float2(-along.y, along.x);
        float halfWidth = s.z + 0.75;
        // ~22 ms of travel behind the particle, capped so fast flings stay crisp.
        float halfLength = halfWidth + min(speed * 0.011, 14.0);
        float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
        float2 p = s.xy + across * corner.x * halfWidth + along * (corner.y * halfLength - (halfLength - halfWidth));
        DebrisOut out;
        out.position = toClip(p, u);
        out.uv = corner;
        out.alpha = s.w;
        out.aspect = halfLength / halfWidth;
        return out;
    }

    fragment float4 debrisFragment(DebrisOut in [[stage_in]]) {
        // Capsule: round head and tail, fading toward the tail.
        float y = in.uv.y * in.aspect;
        float capY = max(abs(y) - (in.aspect - 1.0), 0.0);
        float d = length(float2(in.uv.x, capY));
        float body = 1.0 - smoothstep(0.35, 1.0, d);
        float tail = mix(0.25, 1.0, saturate((in.uv.y + 1.0) * 0.5));
        float a = in.alpha * body * tail;
        return float4(a, a, a, a);
    }

    // MARK: Caps

    struct CapOut {
        float4 position [[position]];
        float v;       // points above the base (window edge or corner arc)
        float hTop;    // snow height at this x, points
    };

    static float hash11(float n) { return fract(sin(n) * 43758.5453); }
    static float valueNoise(float x) {
        float i = floor(x);
        float f = fract(x);
        float t = f * f * (3.0 - 2.0 * f);
        return mix(hash11(i), hash11(i + 1.0), t);
    }

    // One instance per column segment, 2 × float4:
    //   a = (x0, x1, base0, base1)   absolute points
    //   b = (top0, top1, rel0, rel1) top = absolute snow surface, rel = x from the window's left
    vertex CapOut capVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            const device float4 *segments [[buffer(0)]],
                            constant Uniforms &u [[buffer(1)]]) {
        float4 a = segments[iid * 2];
        float4 b = segments[iid * 2 + 1];
        bool right = (vid & 1) != 0;
        bool top = (vid & 2) != 0;
        float x = right ? a.y : a.x;
        float baseY = right ? a.w : a.z;
        float rel = right ? b.w : b.z;
        float h = (right ? b.y : b.x) - baseY;
        // Slight lumpiness on the contour, anchored to the window so it moves with it.
        float lump = (valueNoise(rel * 0.31) - 0.5) * 0.9 + (valueNoise(rel * 1.3 + 7.0) - 0.5) * 0.35;
        h = max(h + lump * saturate(h / 3.0), 0.0);
        float pixel = 1.0 / u.scale;
        // Bottom tucks 1 pt under the edge to hide seams; top gets one pixel for anti-aliasing.
        float y = top ? baseY + h + pixel : baseY - 1.0;
        CapOut out;
        out.position = toClip(float2(x, y), u);
        out.v = y - baseY;
        out.hTop = h;
        return out;
    }

    fragment float4 capFragment(CapOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        if (in.hTop < 0.05) discard_fragment();
        float pixel = 1.0 / u.scale;
        float dist = in.hTop - in.v;                 // points below the snow surface
        float alpha = saturate(dist / pixel + 0.5);  // anti-aliased top contour
        float t = saturate(in.v / max(in.hTop, 1.0));
        float3 bottom = float3(0.910, 0.933, 0.973); // #E8EEF8, cool shade
        float3 color = mix(bottom, float3(0.975), smoothstep(0.0, 0.9, t));
        if (dist < pixel * 1.5) color = float3(1.0);  // 1 px bright highlight
        if (in.v < 0.0) color = bottom * 0.96;        // tucked under the edge
        alpha *= 0.97;
        return float4(color * alpha, alpha);
    }

    // MARK: Debug rectangles

    struct RectOut {
        float4 position [[position]];
        float4 color;
    };

    // One instance = 2 × float4: (x, y, w, h), premultiplied (r, g, b, a).
    vertex RectOut rectVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              const device float4 *rects [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
        float4 r = rects[iid * 2];
        float2 corner = float2((vid & 1) ? 1.0 : 0.0, (vid & 2) ? 1.0 : 0.0);
        RectOut out;
        out.position = toClip(r.xy + corner * r.zw, u);
        out.color = rects[iid * 2 + 1];
        return out;
    }

    fragment float4 rectFragment(RectOut in [[stage_in]]) {
        return in.color;
    }

    // MARK: Toy snowplow sprite and snow carried by its blade

    struct PlowOut {
        float4 position [[position]];
        float2 uv;
        float2 local;
        float load;
    };

    vertex PlowOut plowVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              const device float4 *plows [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
        float4 p = plows[iid * 2];
        float2 corner = float2((vid & 1) ? 1.0 : 0.0, (vid & 2) ? 1.0 : 0.0);
        PlowOut out;
        out.local = corner * (p.zw + float2(16, 0)) - float2(16, 0);
        out.uv = float2(out.local.x / p.z, 1.0 - out.local.y / p.w);
        out.load = plows[iid * 2 + 1].x;
        out.position = toClip(p.xy + out.local, u);
        return out;
    }

    fragment float4 plowFragment(PlowOut in [[stage_in]],
                                texture2d<float> sprite [[texture(0)]]) {
        constexpr sampler imageSampler(filter::linear, address::clamp_to_edge);
        float4 color = sprite.sample(imageSampler, in.uv);
        if (in.uv.x < 0.0) color = float4(0);
        color.rgb *= color.a;
        // Area of this triangular cross-section equals the simulated blade load.
        float height = sqrt(max(in.load, 0.0));
        float width = 2.0 * height;
        float x = in.local.x - 4.0;
        float y = in.local.y - 5.0;
        float top = height * clamp(1.0 + x / max(width, 0.001), 0.0, 1.0);
        float mask = smoothstep(-width, -width + 0.5, x) *
                     (1.0 - smoothstep(-0.5, 0.0, x)) *
                     step(0.0, y) * (1.0 - smoothstep(top - 0.5, top, y));
        if (in.load > 0.01) color = mix(color, float4(0.94, 0.97, 1.0, 1.0), mask);
        return color;
    }
    """
}
