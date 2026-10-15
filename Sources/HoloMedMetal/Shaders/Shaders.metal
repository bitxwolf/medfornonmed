#include <metal_stdlib>
#include "../include/ShaderTypes.h"

using namespace metal;

// ==============================================================================
// 1. CATMULL-ROM SPLINE MATH & EVALUATION (C++14 / MSL)
// ==============================================================================

// Evaluates cubic Catmull-Rom spline segment between P1 and P2 with neighbors P0 and P3
static inline float3 evaluateCatmullRom(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float t2 = t * t;
    float t3 = t2 * t;
    return 0.5f * ((2.0f * p1) +
                   (-p0 + p2) * t +
                   (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2 +
                   (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3);
}

// Evaluates first derivative (tangent) of cubic Catmull-Rom spline
static inline float3 evaluateCatmullRomTangent(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float t2 = t * t;
    return 0.5f * ((-p0 + p2) +
                   2.0f * (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t +
                   3.0f * (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t2);
}

// ==============================================================================
// 2. PARALLEL COMPUTE KERNEL: 100,000 BLOOD CELL PARTICLES IN UMA
// ==============================================================================
// Executes directly on Apple Silicon GPU compute cores with zero CPU overhead,
// reading and updating shared memory buffers in place.

kernel void simulate_blood_cells_kernel(device BloodCellInstance*         cells           [[buffer(BufferIndexBloodCells)]],
                                       constant SplinePoint*             splineNodes     [[buffer(BufferIndexSplineNodes)]],
                                       constant BlockageParams&          blockage        [[buffer(BufferIndexBlockageParams)]],
                                       constant Uniforms&                uniforms        [[buffer(BufferIndexUniforms)]],
                                       constant uint&                    nodeCount       [[buffer(4)]],
                                       constant uint&                    totalCells      [[buffer(5)]],
                                       uint id [[thread_position_in_grid]])
{
    if (id >= totalCells || nodeCount < 4) {
        return;
    }

    device BloodCellInstance& cell = cells[id];

    // Determine speed based on lumen position (Poiseuille parabolic velocity profile)
    // Centerline has max velocity, walls have near zero due to viscous boundary layer
    float parabolicFactor = max(0.2f, 1.0f - (cell.radialOffset * cell.radialOffset));
    float baseSpeed = 0.08f * parabolicFactor;

    // Check interaction with arterial stenosis / atherosclerotic plaque
    float distToBlockage = cell.splineProgress - blockage.splineProgress;
    bool isNearBlockage = abs(distToBlockage) < 0.08f;
    bool isUpstream = distToBlockage < 0.0f && distToBlockage > -0.15f;

    if (blockage.stenosisSeverity > 0.05f) {
        if (isNearBlockage && blockage.stenosisSeverity >= 0.90f) {
            // Severe or total acute occlusion (e.g. LAD Coronary Thrombus in Acute MI)
            cell.isBlocked = 1;
            baseSpeed = 0.0f;
        } else if (isUpstream) {
            // Upstream bottleneck deceleration & turbulence
            float slowdown = 1.0f - (blockage.stenosisSeverity * (1.0f - abs(distToBlockage) / 0.15f));
            baseSpeed *= max(0.05f, slowdown);
        } else if (isNearBlockage) {
            // Jet velocity through narrow patent lumen
            baseSpeed *= (1.0f + blockage.stenosisSeverity * 1.5f);
        }
    } else {
        cell.isBlocked = 0;
    }

    // Advance progress along spline
    float dt = 0.008f;
    cell.splineProgress += (baseSpeed * dt);
    if (cell.splineProgress >= 1.0f) {
        cell.splineProgress -= 1.0f;
        cell.isBlocked = 0;
    }

    // Multi-segment Catmull-Rom spline lookup
    float totalProgress = cell.splineProgress * float(nodeCount - 3);
    uint segIdx = clamp(uint(floor(totalProgress)), 0u, nodeCount - 4);
    float localT = fract(totalProgress);

    float3 p0 = splineNodes[segIdx].position;
    float3 p1 = splineNodes[segIdx + 1].position;
    float3 p2 = splineNodes[segIdx + 2].position;
    float3 p3 = splineNodes[segIdx + 3].position;

    float r1 = splineNodes[segIdx + 1].lumenRadius;
    float r2 = splineNodes[segIdx + 2].lumenRadius;
    float lumenRadius = mix(r1, r2, localT);

    // Stenosis constricts effective lumen radius
    if (isNearBlockage) {
        float constriction = 1.0f - blockage.stenosisSeverity * (1.0f - abs(distToBlockage) / 0.08f);
        lumenRadius *= max(0.12f, constriction);
    }

    // Compute center position and forward tangent
    float3 centerPos = evaluateCatmullRom(p0, p1, p2, p3, localT);
    float3 tangent = normalize(evaluateCatmullRomTangent(p0, p1, p2, p3, localT));

    // Construct orthonormal Frenet-Serret frame
    float3 arbitraryUp = float3(0.0f, 1.0f, 0.0f);
    if (abs(dot(tangent, arbitraryUp)) > 0.9f) {
        arbitraryUp = float3(1.0f, 0.0f, 0.0f);
    }
    float3 normal = normalize(cross(tangent, arbitraryUp));
    float3 binormal = cross(tangent, normal);

    // Spiral motion inside blood vessel
    cell.radialAngle += (cell.spinPhase * dt * 3.0f);
    float currentRadius = cell.radialOffset * lumenRadius;

    float3 radialOffsetVec = (cos(cell.radialAngle) * normal + sin(cell.radialAngle) * binormal) * currentRadius;
    cell.position = centerPos + radialOffsetVec;
    cell.velocity = tangent * baseSpeed;
    cell.orientation = tangent;

    // Physiological Oxygenation Transition:
    // Deoxygenated blue in vena cava / right heart chambers (progress < 0.35)
    // Alveolar oxygenation in lungs (0.35 - 0.45)
    // Oxygenated crimson red in left heart chambers & systemic aorta/LAD (progress > 0.45)
    float4 deoxygenatedColor = float4(0.15f, 0.38f, 0.88f, 0.95f); // Venous blue
    float4 oxygenatedColor   = float4(0.96f, 0.06f, 0.08f, 0.98f); // Arterial bright red
    float4 ischemicColor     = float4(0.35f, 0.12f, 0.42f, 0.90f); // Hypoxic cyanotic

    if (cell.splineProgress < 0.35f) {
        cell.color = deoxygenatedColor;
    } else if (cell.splineProgress < 0.48f) {
        float o2Factor = smoothstep(0.35f, 0.48f, cell.splineProgress);
        cell.color = mix(deoxygenatedColor, oxygenatedColor, o2Factor);
    } else {
        if (cell.isBlocked == 1) {
            // Stagnant deoxygenating blood at thrombosis
            cell.color = mix(oxygenatedColor, ischemicColor, 0.75f);
        } else {
            cell.color = oxygenatedColor;
        }
    }
}

// ==============================================================================
// 3. HARDWARE INSTANCED BLOOD CELL (ERYTHROCYTE) SHADERS
// ==============================================================================

struct BloodCellVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPos;
    float4 color;
    float  fresnel;
};

vertex BloodCellVertexOut blood_cell_vertex(uint vertexID [[vertex_id]],
                                            uint instanceID [[instance_id]],
                                            constant VertexIn* vertices [[buffer(BufferIndexMeshPositions)]],
                                            constant BloodCellInstance* instances [[buffer(BufferIndexBloodCells)]],
                                            constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    BloodCellVertexOut out;
    VertexIn v = vertices[vertexID];
    BloodCellInstance inst = instances[instanceID];

    // Align erythrocyte disc to flow direction (tangent)
    float3 forward = normalize(inst.orientation);
    float3 up = float3(0.0f, 1.0f, 0.0f);
    if (abs(dot(forward, up)) > 0.9f) {
        up = float3(1.0f, 0.0f, 0.0f);
    }
    float3 right = normalize(cross(forward, up));
    up = cross(right, forward);

    // Apply Evans-Fung biconcave erythrocyte scaling (flat disc indented at center)
    float3 scaledVertex = v.position * inst.scale;
    float3 rotatedVertex = right * scaledVertex.x + up * scaledVertex.y + forward * scaledVertex.z;
    float3 worldPosition = inst.position + rotatedVertex;

    float3 rotatedNormal = normalize(right * v.normal.x + up * v.normal.y + forward * v.normal.z);

    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPosition, 1.0f);
    out.worldNormal = rotatedNormal;
    out.worldPos = worldPosition;
    out.color = inst.color;

    // Fresnel rim effect for glistening erythrocyte membrane
    float3 viewDir = normalize(uniforms.cameraPosition - worldPosition);
    out.fresnel = 1.0f - max(0.0f, dot(rotatedNormal, viewDir));

    return out;
}

fragment float4 blood_cell_fragment(BloodCellVertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(uniforms.lightDirection);
    float3 V = normalize(uniforms.cameraPosition - in.worldPos);
    float3 H = normalize(L + V);

    // Diffuse + Hemoglobin Subsurface Scattering
    float NdotL = max(0.0f, dot(N, L));
    float sss = pow(max(0.0f, dot(-V, L)), 2.0f) * 0.35f; // Translucent glow

    // Blinn-Phong specular for lipid bilayer membrane
    float NdotH = max(0.0f, dot(N, H));
    float spec = pow(NdotH, 32.0f) * 0.45f;

    // Rim lighting (Fresnel)
    float rim = pow(in.fresnel, 3.0f) * 0.5f;

    float3 baseColor = in.color.rgb;
    float3 litColor = baseColor * (uniforms.ambientIntensity + NdotL + sss) + float3(1.0f, 0.9f, 0.9f) * spec + rim * baseColor * 1.5f;

    return float4(litColor, in.color.a);
}

// ==============================================================================
// 4. PROCEDURAL MYOCARDIAL TISSUE ISCHEMIA & NECROSIS SHADER
// ==============================================================================

struct TissueVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPos;
    float2 texCoords;
    float  lesionFactor;
};

vertex TissueVertexOut tissue_state_vertex(VertexIn in [[stage_in]],
                                           constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                                           constant TissueParams& tissue [[buffer(BufferIndexTissueParams)]])
{
    TissueVertexOut out;

    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0f);
    float3 worldNormal = normalize((uniforms.normalMatrix * float4(in.normal, 0.0f)).xyz);

    // Compute spatial proximity to ischemic territory (e.g. LAD anterior myocardium)
    float distToLesion = length(worldPos.xyz - tissue.lesionCentroid);
    float lesionProximity = 1.0f - smoothstep(0.0f, tissue.lesionRadius, distToLesion);

    // Inflamed tissue normal expansion (edema)
    if (tissue.state == TissueStateInflamed) {
        float pulse = sin(tissue.time * 4.0f) * 0.5f + 0.5f;
        worldPos.xyz += worldNormal * (tissue.inflammationFactor * 0.015f * pulse);
    }

    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = worldNormal;
    out.worldPos = worldPos.xyz;
    out.texCoords = in.texCoords;
    out.lesionFactor = lesionProximity;

    return out;
}

fragment float4 tissue_state_fragment(TissueVertexOut in [[stage_in]],
                                      constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                                      constant TissueParams& tissue [[buffer(BufferIndexTissueParams)]])
{
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(uniforms.lightDirection);
    float3 V = normalize(uniforms.cameraPosition - in.worldPos);
    float3 H = normalize(L + V);

    float NdotL = max(0.15f, dot(N, L));
    float spec = pow(max(0.0f, dot(N, H)), 16.0f) * 0.2f;

    // Healthy perfused myocardium (deep vibrant pinkish-red)
    float3 healthyColor = float3(0.82f, 0.22f, 0.26f);

    // Ischemic cyanotic hypoxia (dark violaceous purple with hypoxic pulse)
    float hypoxicPulse = sin(tissue.time * tissue.hypoxicPulseSpeed) * 0.5f + 0.5f;
    float3 ischemicColor = float3(0.28f, 0.12f, 0.38f) * (0.85f + 0.30f * hypoxicPulse);

    // Necrotic infarcted myocardium (mottled dark grey-brown with loss of luster)
    // Procedural pseudo-noise for mottled patchy infarction
    float noise = fract(sin(dot(in.worldPos.xy, float2(12.9898f, 78.233f))) * 43758.5453f);
    float3 necroticColor = float3(0.18f, 0.15f, 0.16f) + float3(0.06f) * noise;

    // Inflamed erythematous hyperemic tissue
    float3 inflamedColor = float3(0.95f, 0.10f, 0.12f);

    float3 finalColor = healthyColor;

    if (tissue.state == TissueStateIschemic) {
        float factor = in.lesionFactor * tissue.ischemicRatio;
        finalColor = mix(healthyColor, ischemicColor, factor);
    } else if (tissue.state == TissueStateNecrotic) {
        float ischemicPart = in.lesionFactor * tissue.ischemicRatio;
        float necroticPart = in.lesionFactor * tissue.necroticRatio;
        float3 temp = mix(healthyColor, ischemicColor, ischemicPart);
        finalColor = mix(temp, necroticColor, necroticPart);
        spec *= (1.0f - necroticPart * 0.8f); // Infarcted tissue loses surface gloss
    } else if (tissue.state == TissueStateInflamed) {
        finalColor = mix(healthyColor, inflamedColor, in.lesionFactor * tissue.inflammationFactor);
    } else if (tissue.state == TissueStateHighlighted) {
        finalColor = mix(healthyColor, uniforms.highlightColor.rgb, uniforms.highlightIntensity);
    }

    float3 lit = finalColor * (uniforms.ambientIntensity + NdotL) + float3(spec);
    return float4(lit, uniforms.occlusionAlpha);
}

// ==============================================================================
// 5. PROCEDURAL ARTERIAL BLOCKAGE (ATHEROMA & THROMBUS) SHADER
// ==============================================================================

struct BlockageVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPos;
    float  beaconPulse;
};

vertex BlockageVertexOut arterial_blockage_vertex(VertexIn in [[stage_in]],
                                                 constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                                                 constant BlockageParams& blockage [[buffer(BufferIndexBlockageParams)]])
{
    BlockageVertexOut out;

    // Scale and position blockage mesh at stenosis location
    float3 scaledPos = in.position * blockage.plaqueRadius;
    float4 worldPos = float4(blockage.center + scaledPos, 1.0f);

    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = in.normal;
    out.worldPos = worldPos.xyz;
    out.beaconPulse = blockage.warningPulse;

    return out;
}

fragment float4 arterial_blockage_fragment(BlockageVertexOut in [[stage_in]],
                                           constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                                           constant BlockageParams& blockage [[buffer(BufferIndexBlockageParams)]])
{
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(uniforms.lightDirection);
    float NdotL = max(0.2f, dot(N, L));

    // Atheroma (calcified lipid core: yellowish-tan)
    float3 lipidColor = float3(0.92f, 0.84f, 0.55f);
    // Acute thrombus (fibrin-platelet clot: dark brown-red)
    float3 thrombusColor = float3(0.42f, 0.08f, 0.10f);

    float3 plaqueColor = mix(lipidColor, thrombusColor, blockage.stenosisSeverity);

    // Pulsing warning beacon halo around high-grade blockage
    float pulse = sin(blockage.warningPulse * 5.0f) * 0.5f + 0.5f;
    float3 beaconGlow = float3(1.0f, 0.2f, 0.1f) * pulse * (blockage.stenosisSeverity > 0.7f ? 1.0f : 0.0f);

    float3 finalColor = plaqueColor * (uniforms.ambientIntensity + NdotL) + beaconGlow;
    return float4(finalColor, 1.0f);
}

// ==============================================================================
// 6. GENERAL ANATOMICAL MESH SHADER WITH OCCLUSION X-RAY GHOSTING
// ==============================================================================

struct GenericMeshVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPos;
    float2 texCoords;
};

vertex GenericMeshVertexOut generic_mesh_vertex(VertexIn in [[stage_in]],
                                                constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    GenericMeshVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0f);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = normalize((uniforms.normalMatrix * float4(in.normal, 0.0f)).xyz);
    out.worldPos = worldPos.xyz;
    out.texCoords = in.texCoords;
    return out;
}

fragment float4 generic_mesh_fragment(GenericMeshVertexOut in [[stage_in]],
                                      constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(uniforms.lightDirection);
    float3 V = normalize(uniforms.cameraPosition - in.worldPos);
    float3 H = normalize(L + V);

    float NdotL = max(0.18f, dot(N, L));
    float spec = pow(max(0.0f, dot(N, H)), 24.0f) * 0.3f;
    float fresnel = pow(1.0f - max(0.0f, dot(N, V)), 2.5f);

    float3 baseColor = float3(0.75f, 0.68f, 0.65f); // Natural anatomical base

    // Highlight emissive blend
    if (uniforms.highlightIntensity > 0.01f) {
        baseColor = mix(baseColor, uniforms.highlightColor.rgb, uniforms.highlightIntensity);
    }

    // X-ray ghosting for occluding superficial structures (e.g. ribcage, sternum)
    float alpha = uniforms.occlusionAlpha;
    if (alpha < 0.99f) {
        // Fresnel edge glow makes ghosted translucent structures clearly readable
        baseColor = mix(baseColor, float3(0.5f, 0.8f, 1.0f), fresnel * 0.6f);
        alpha = max(alpha, fresnel * 0.35f);
    }

    float3 litColor = baseColor * (uniforms.ambientIntensity + NdotL) + float3(spec);
    return float4(litColor, alpha);
}
