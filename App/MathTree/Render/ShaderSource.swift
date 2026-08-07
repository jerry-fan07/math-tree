/// The renderer's Metal source, compiled at launch with
/// `MTLDevice.makeLibrary(source:options:)`.
///
/// It lives in a string rather than a `.metal` file because of D0.3: SwiftPM
/// silently ignores `.metal` files in a Swift target — no `default.metallib` is
/// produced and `makeDefaultLibrary()` returns nil. Metal caches the compile on
/// the source text, so only a user's first-ever launch pays the full ~66 ms
/// (D3.2); warm launches are ~0.5 ms.
enum ShaderSource {
    static let metal = """
        #include <metal_stdlib>
        using namespace metal;

        // ---- Mirrors of RenderTypes.swift ------------------------------------

        struct Uniforms {
            float2 originPx;
            float  scalePx;
            float  backingScale;
            float2 viewportPx;
            float  reveal;
            float  bandT;
            float  edgeAlpha;
            float  labelAlpha;
        };

        struct NodeInstance {
            float2 pos;
            half2  radii;
            uint   rgba;
        };

        struct EdgeInstance {
            float2 a;
            float2 b;
            uint   rgbaA;
            uint   rgbaB;
        };

        struct LabelInstance {
            float2 anchor;
            float2 sizePt;
            float2 uvMin;
            float2 uvMax;
            uint   rgba;
            uint   page;
            float  offsetPt;
            float  fadeStart;
        };

        struct DrawParams {
            uint  rangeStart;
            float count;
            float revealBase;
            float revealSpan;
            float alpha;
            float widthPt;
            float dashPeriodPt;
            float dashDuty;
            float arrowAlpha;
            float arrowSizePt;
        };

        // ---- Shared helpers ---------------------------------------------------

        static inline float4 unpackRGBA(uint c) {
            return float4(float(c & 0xFFu),
                          float((c >> 8) & 0xFFu),
                          float((c >> 16) & 0xFFu),
                          float((c >> 24) & 0xFFu)) * (1.0 / 255.0);
        }

        // Drawable pixels -> clip space. The drawable's origin is top-left, so y
        // is flipped here once and world coordinates stay in screen orientation
        // everywhere else (including on the CPU, for picking).
        static inline float4 pxToClip(float2 px, float2 viewportPx) {
            float2 ndc = float2(px.x / max(viewportPx.x, 1.0) * 2.0 - 1.0,
                                1.0 - px.y / max(viewportPx.y, 1.0) * 2.0);
            return float4(ndc, 0.0, 1.0);
        }

        // Progressive reveal (§6.4). Instances are tier-sorted, so ramping on the
        // instance index makes hubs fade in first and the constellation fill in
        // behind them — with no extra per-instance bytes and no CPU work.
        static inline float revealFactor(uint iid, constant DrawParams &p, float reveal) {
            float frac = float(iid) / max(p.count, 1.0);
            float appear = p.revealBase + p.revealSpan * frac;
            return saturate((reveal - appear) * 8.0);
        }

        // ---- Nodes ------------------------------------------------------------

        struct NodeVaryings {
            float4 position [[position]];
            float2 local;       // distance from the centre, in radius units
            float4 color;
            float  radiusPx;
            float  halo;
        };

        vertex NodeVaryings nodeVertex(uint vid                       [[vertex_id]],
                                       uint iid                       [[instance_id]],
                                       constant Uniforms      &u      [[buffer(0)]],
                                       device const NodeInstance *inst [[buffer(1)]],
                                       constant DrawParams    &p      [[buffer(2)]])
        {
            NodeInstance n = inst[iid + p.rangeStart];

            float radiusPt = mix(float(n.radii.x), float(n.radii.y), u.bandT);
            float radiusPx = max(radiusPt * u.backingScale, 0.75);

            // Only nodes big enough to read as hubs get a halo; that is what makes
            // branches look like galaxies rather than dots (§6.1).
            float halo = saturate((radiusPt - 5.0) / 12.0) * 0.40;
            float extent = radiusPx * mix(1.35, 2.80, saturate(halo * 3.0));

            float2 corner = float2((vid & 1u) != 0u ? 1.0 : -1.0,
                                   (vid & 2u) != 0u ? 1.0 : -1.0);
            float2 centrePx = u.originPx + n.pos * u.scalePx;

            NodeVaryings out;
            out.position = pxToClip(centrePx + corner * extent, u.viewportPx);
            out.local    = corner * (extent / radiusPx);
            out.color    = unpackRGBA(n.rgba);
            out.color.a *= p.alpha * revealFactor(iid, p, u.reveal);
            out.radiusPx = radiusPx;
            out.halo     = halo;
            return out;
        }

        fragment float4 nodeFragment(NodeVaryings v [[stage_in]])
        {
            float d = length(v.local);
            float aa = max(1.4 / v.radiusPx, 0.02);
            float core = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
            float halo = v.halo * exp2(-max(d - 1.0, 0.0) * 3.5) * (1.0 - core);
            float a = saturate(core + halo) * v.color.a;
            return float4(v.color.rgb * a, a);      // premultiplied
        }

        // Same geometry, drawn as an annulus — the hover highlight of §6.1's
        // detail zoom.
        fragment float4 ringFragment(NodeVaryings v [[stage_in]])
        {
            float d = length(v.local);
            float aa = max(1.8 / v.radiusPx, 0.03);
            float outer = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
            float inner = 1.0 - smoothstep(0.70 - aa, 0.70 + aa, d);
            float a = saturate(outer - inner) * v.color.a;
            return float4(v.color.rgb * a, a);
        }

        // ---- Edges ------------------------------------------------------------

        struct EdgeVaryings {
            float4 position [[position]];
            float4 color;
            float  alongPx;
            float  acrossPx;
            float  lengthPx;
            float  halfWidthPx;
            float  dashPeriodPx;
            float  dashDuty;
            float  arrowAlpha;
            float  arrowSizePx;
        };

        vertex EdgeVaryings edgeVertex(uint vid                        [[vertex_id]],
                                       uint iid                        [[instance_id]],
                                       constant Uniforms       &u      [[buffer(0)]],
                                       device const EdgeInstance *inst [[buffer(1)]],
                                       constant DrawParams     &p      [[buffer(2)]])
        {
            EdgeInstance e = inst[iid + p.rangeStart];

            float2 aPx = u.originPx + e.a * u.scalePx;
            float2 bPx = u.originPx + e.b * u.scalePx;
            float2 delta = bPx - aPx;
            float  lengthPx = length(delta);
            // D3.4: guard normalize() — coincident endpoints are legal content.
            float2 dir = lengthPx > 1e-4 ? delta / lengthPx : float2(1.0, 0.0);
            float2 nrm = float2(-dir.y, dir.x);

            float halfWidthPx = max(p.widthPt * u.backingScale, 0.9) * 0.5;
            float arrowSizePx = p.arrowSizePt * u.backingScale;
            // The quad has to be wide enough to hold the arrowhead as well as the
            // stroke, plus a pixel of antialiasing slack on each side.
            float halfExtent = max(halfWidthPx, arrowSizePx * 0.55) + 1.5;

            float t = (vid & 2u) != 0u ? 1.0 : 0.0;
            float s = (vid & 1u) != 0u ? 1.0 : -1.0;
            float2 px = mix(aPx, bPx, t) + nrm * (s * halfExtent);

            EdgeVaryings out;
            out.position     = pxToClip(px, u.viewportPx);
            out.color        = unpackRGBA(t < 0.5 ? e.rgbaA : e.rgbaB);
            out.color.a     *= p.alpha * u.edgeAlpha * revealFactor(iid, p, u.reveal);
            out.alongPx      = t * lengthPx;
            out.acrossPx     = s * halfExtent;
            out.lengthPx     = lengthPx;
            out.halfWidthPx  = halfWidthPx;
            out.dashPeriodPx = p.dashPeriodPt * u.backingScale;
            out.dashDuty     = p.dashDuty;
            out.arrowAlpha   = p.arrowAlpha;
            out.arrowSizePx  = arrowSizePx;
            return out;
        }

        fragment float4 edgeFragment(EdgeVaryings v [[stage_in]])
        {
            float across = abs(v.acrossPx);

            // Stroke with an alpha falloff across the width (D3.4) — this is what
            // makes a 1 pt hairline read as a hairline on a Retina drawable.
            float stroke = 1.0 - smoothstep(v.halfWidthPx - 0.7, v.halfWidthPx + 0.7, across);
            stroke *= mix(1.0, 0.45, saturate(across / max(v.halfWidthPx, 0.001)));

            // Dashes: `relates` edges break up as the band deepens (§6.1 mid zoom).
            if (v.dashPeriodPx > 0.5 && v.dashDuty < 0.999) {
                float phase = fract(v.alongPx / v.dashPeriodPx);
                float soft = 0.5 / v.dashPeriodPx + 0.02;
                stroke *= 1.0 - smoothstep(v.dashDuty - soft, v.dashDuty + soft, phase);
            }

            // Arrowhead: a triangle riding the edge, marking prerequisite
            // direction. Placed mid-edge rather than at the endpoint because the
            // target node's radius changes with the zoom band and is not carried
            // per edge instance.
            float arrow = 0.0;
            if (v.arrowAlpha > 0.002 && v.lengthPx > 6.0) {
                float tip = v.lengthPx * 0.62;
                float behind = tip - v.alongPx;
                float h = min(v.arrowSizePx, v.lengthPx * 0.34);
                if (behind >= 0.0 && behind <= h) {
                    float halfSpan = (h > 0.001 ? behind / h : 0.0) * h * 0.55;
                    arrow = (1.0 - smoothstep(halfSpan - 0.7, halfSpan + 0.7, across))
                          * v.arrowAlpha;
                }
            }

            float a = saturate(max(stroke, arrow)) * v.color.a;
            return float4(v.color.rgb * a, a);
        }

        // ---- Labels -----------------------------------------------------------

        struct LabelVaryings {
            float4 position [[position]];
            float2 uv;
            float4 color;
            uint   page;
            float2 texelSize;
        };

        vertex LabelVaryings labelVertex(uint vid                         [[vertex_id]],
                                         uint iid                         [[instance_id]],
                                         constant Uniforms        &u      [[buffer(0)]],
                                         device const LabelInstance *inst [[buffer(1)]],
                                         constant DrawParams      &p      [[buffer(2)]],
                                         texture2d_array<float> atlas     [[texture(0)]])
        {
            LabelInstance l = inst[iid + p.rangeStart];

            float2 anchorPx = u.originPx + l.anchor * u.scalePx;
            float2 sizePx   = l.sizePt * u.backingScale;
            float2 boxPx    = anchorPx + float2(-sizePx.x * 0.5, l.offsetPt * u.backingScale);

            float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0,
                                   (vid & 2u) != 0u ? 1.0 : 0.0);

            // Per-tier fade: labels for lower prominence emerge as the band
            // deepens (§6.1). fadeStart < 0 means "visible from overview on".
            float tierFade = smoothstep(l.fadeStart, l.fadeStart + 0.10, u.bandT);

            LabelVaryings out;
            out.position  = pxToClip(boxPx + corner * sizePx, u.viewportPx);
            out.uv        = mix(l.uvMin, l.uvMax, corner);
            out.color     = unpackRGBA(l.rgba);
            out.color.a  *= p.alpha * u.labelAlpha * tierFade
                          * revealFactor(iid, p, u.reveal);
            out.page      = l.page;
            out.texelSize = float2(1.0 / float(atlas.get_width()),
                                   1.0 / float(atlas.get_height()));
            return out;
        }

        fragment float4 labelFragment(LabelVaryings v [[stage_in]],
                                      texture2d_array<float> atlas [[texture(0)]],
                                      sampler smp [[sampler(0)]])
        {
            float coverage = atlas.sample(smp, v.uv, v.page).r;

            // A four-tap dilation gives the glyphs a dark backing so they stay
            // legible where they cross a bright edge, without a second atlas.
            float2 o = v.texelSize;
            float halo = max(max(atlas.sample(smp, v.uv + float2( o.x, 0), v.page).r,
                                 atlas.sample(smp, v.uv + float2(-o.x, 0), v.page).r),
                             max(atlas.sample(smp, v.uv + float2(0,  o.y), v.page).r,
                                 atlas.sample(smp, v.uv + float2(0, -o.y), v.page).r));

            float a = saturate(max(coverage, halo * 0.75)) * v.color.a;
            float3 rgb = v.color.rgb * coverage;    // backing stays black
            return float4(rgb * a, a);
        }
        """
}
