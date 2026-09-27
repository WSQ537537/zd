#version 320 es
// iOS 26 Liquid Glass — SDF capsule pill, refraction + Fresnel specular

precision highp float;

in vec2 fragCoord;   // fragment position in pixels
out vec4 fragColor;

uniform vec2  uResolution;   // widget size in pixels
uniform vec2  uCenter;       // pill center in pixels
uniform vec2  uHalfSize;     // half-width, half-height
uniform float uRadius;       // corner radius
uniform float uRefraction;   // refraction strength (0..1)
uniform float uBlurSigma;    // blur sigma for fallback
uniform vec3  uTint;         // glass tint color
uniform float uTintAlpha;    // glass tint opacity
uniform float uLightAngle;   // light direction angle (rad)

#define PI 3.14159265359
#define PX(a) (a / uResolution.y)

// ── Rounded-box SDF (pill / capsule) ────────────────────────────
float sdPill(vec2 p, vec2 center, vec2 half, float radius) {
    vec2 q = abs(p - center) - half;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
    // Normalised pixel coords (0..1)
    vec2 uv = fragCoord / uResolution;

    // Normalised centre and half-size in uv space
    vec2 c  = uCenter / uResolution;
    vec2 h  = uHalfSize / uResolution;
    float r = uRadius  / uResolution.y;

    // ── 1. Sample blurred background (from BackdropFilter) ───────
    vec3 blurred = texture(uBackground, uv).rgb;

    // ── 2. SDF & mask ─────────────────────────────────────────────
    float d = sdPill(uv, c, h, r);
    float mask = 1.0 - smoothstep(PX(1.5), 0.0, d);

    // Edge transition band for smooth glass boundary
    float edgeBand = smoothstep(PX(-12.0), PX(6.0), d)
                   - smoothstep(PX(0.0),  PX(8.0),  d);

    // ── 3. Refraction displacement (Snell-like) ──────────────────
    vec2  dir      = normalize(uv - c + 1e-5);
    float fresnel  = pow(1.0 - abs(dot(dir, vec2(0.0, -1.0))), 2.5);
    float refractA = clamp(fresnel * uRefraction * 0.18, 0.0, 0.12);
    vec2  refUV    = uv + dir * refractA * edgeBand;
    vec3  refractC = texture(uBackground, refUV).rgb;

    // ── 4. Ambient + diffuse lighting ────────────────────────────
    float ambient = 0.06;
    vec2  lightDir = normalize(vec2(cos(uLightAngle), sin(uLightAngle)));
    vec2  surfNorm = uv - c;
    float diff     = max(0.0, dot(normalize(surfNorm), lightDir));
    diff *= clamp(mask - smoothstep(0.0, PX(-3.0), d), 0.0, 1.0);
    vec3  light    = vec3(ambient + diff * 0.35);

    // ── 5. Shadow (dark band below the pill) ─────────────────────
    float shadowMask = clamp(mask - smoothstep(PX(2.0), PX(-4.0), d), 0.0, 1.0);
    float shadow     = shadowMask * smoothstep(0.0, PX(8.0), uv.y - c.y + h.y);
    light -= shadow * 0.08;

    // ── 6. Fresnel edge glow ──────────────────────────────────────
    float rim   = pow(edgeBand, 1.5);
    vec3  rimC  = uTint * rim * 0.45;

    // ── 7. Tint overlay ───────────────────────────────────────────
    vec3  tinted  = blurred * uTintAlpha * 0.5 + uTint * uTintAlpha * 0.15;

    // ── 8. Composite ──────────────────────────────────────────────
    vec3  color  = mix(blurred, refractC, mask * 0.6);
    color       += light;
    color       += rimC;
    color       += tinted * mask;

    float alpha  = mask * (0.72 + fresnel * 0.15 + edgeBand * 0.12);
    fragColor    = vec4(clamp(color, 0.0, 1.0), alpha);
}
