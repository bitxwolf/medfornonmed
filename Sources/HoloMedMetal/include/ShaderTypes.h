#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#else
#include <simd/simd.h>
#include <stdint.h>
#include <stdbool.h>
#endif

// Buffer Bindings
enum BufferIndex {
    BufferIndexMeshPositions    = 0,
    BufferIndexMeshGenerics     = 1,
    BufferIndexUniforms         = 2,
    BufferIndexBloodCells       = 3,
    BufferIndexSplineNodes      = 4,
    BufferIndexBlockageParams   = 5,
    BufferIndexTissueParams     = 6,
    BufferIndexInstanceData     = 7
};

// Texture Bindings
enum TextureIndex {
    TextureIndexBaseColor       = 0,
    TextureIndexNormal          = 1
};

// Function Constants
enum FunctionConstantIndex {
    FunctionConstantOcclusionFading = 0
};

// Tissue States matching the HoloMed spec:
// normal, highlighted, ischemic, necrotic, inflamed
enum TissueState {
    TissueStateNormal      = 0,
    TissueStateHighlighted = 1,
    TissueStateIschemic    = 2,
    TissueStateNecrotic    = 3,
    TissueStateInflamed    = 4
};

// Standard Blinn-Phong & Camera Uniforms (320 bytes, 16-byte aligned)
struct Uniforms {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 normalMatrix;
    vector_float3   cameraPosition;
    float           time;
    vector_float3   lightDirection;
    float           ambientIntensity;
    vector_float4   highlightColor;
    float           highlightIntensity;
    float           occlusionAlpha;
    float           padding[2];
};

// Spline Control Point along Catmull-Rom Path (48 bytes, 16-byte aligned)
struct SplinePoint {
    vector_float3 position;
    float         lumenRadius;
    vector_float3 tangent;
    float         arcLength;
    vector_float3 normal;
    float         targetSpeed;
};

// 100,000 Blood Cell Particle Instance in Apple Silicon UMA (80 bytes, 16-byte aligned)
struct BloodCellInstance {
    vector_float3 position;
    float         splineProgress; // u in [0, 1]
    vector_float3 velocity;
    float         radialOffset;   // distance from vessel lumen axis
    vector_float3 orientation;    // tangent or euler rotation
    float         radialAngle;    // theta in [0, 2*PI]
    vector_float4 color;          // RGBA (oxygenated arterial vs deoxygenated venous)
    float         scale;
    uint32_t      isBlocked;      // 1 if stopped at stenosis/thrombus
    uint32_t      cellType;       // 0: Erythrocyte (RBC), 1: Platelet, 2: Leukocyte
    float         spinPhase;      // rotational angle
};

// Dynamic Arterial Blockage & Atheroma / Thrombus (48 bytes, 16-byte aligned)
struct BlockageParams {
    vector_float3 center;
    float         stenosisSeverity; // 0.0 = patent, 1.0 = total occlusion
    vector_float3 vesselDirection;
    float         splineProgress;   // progress s in [0, 1] on vessel path
    float         plaqueRadius;
    float         thrombusLength;
    float         warningPulse;
    float         padding;
};

// Procedural Myocardial Tissue Ischemia & Necrosis (48 bytes, 16-byte aligned)
struct TissueParams {
    uint32_t      state;             // TissueState enum
    float         ischemicRatio;     // [0, 1] progression of hypoxia
    float         necroticRatio;     // [0, 1] progression of infarction/necrosis
    float         inflammationFactor;// [0, 1] hyperemia & edema
    vector_float3 lesionCentroid;    // 3D center of ischemic territory (e.g. LAD apex)
    float         lesionRadius;      // spatial falloff radius
    float         hypoxicPulseSpeed; // frequency of hypoxic metabolic pulsation
    float         time;
    float         padding[2];
};

// Standard Mesh Vertex (32 bytes, 16-byte aligned)
struct VertexIn {
    vector_float3 position;
    vector_float3 normal;
    vector_float2 texCoords;
};

#endif /* ShaderTypes_h */
