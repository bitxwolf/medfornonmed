import Foundation
import simd

public struct SplineWaypoint {
    public var position: simd_float3
    public var lumenRadius: Float
    public var structureId: String
    public var description: String

    public init(position: simd_float3, lumenRadius: Float, structureId: String, description: String) {
        self.position = position
        self.lumenRadius = lumenRadius
        self.structureId = structureId
        self.description = description
    }
}

public enum SplineMath {
    public static func evaluateCatmullRom(p0: simd_float3, p1: simd_float3, p2: simd_float3, p3: simd_float3, t: Float) -> simd_float3 {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * ((2.0 * p1) +
                      (-p0 + p2) * t +
                      (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
                      (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
    }

    public static func evaluateTangent(p0: simd_float3, p1: simd_float3, p2: simd_float3, p3: simd_float3, t: Float) -> simd_float3 {
        let t2 = t * t
        let d = 0.5 * ((-p0 + p2) +
                       2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t +
                       3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2)
        let len = simd_length(d)
        return len > 0.0001 ? d / len : simd_float3(0, 0, 1)
    }

    /// Generates canonical cardiovascular circuit control points connecting:
    /// Vena Cava -> Right Atrium (FMA_7096) -> Tricuspid Valve -> Right Ventricle (FMA_7098) ->
    /// Pulmonary Trunk -> Pulmonary Capillaries (Lungs FMA_7309/7310) -> Pulmonary Veins ->
    /// Left Atrium (FMA_7099) -> Mitral Valve -> Left Ventricle (FMA_7097) ->
    /// Ascending Aorta (FMA_3734) -> LAD Coronary Artery (FMA_7101)
    public static func generateCardiovascularCircuit() -> [SplineWaypoint] {
        return [
            // Superior Vena Cava input (Venous blue)
            SplineWaypoint(position: simd_float3(0.18, 0.45, 0.05), lumenRadius: 0.045, structureId: "FMA_4720", description: "Superior Vena Cava"),
            SplineWaypoint(position: simd_float3(0.16, 0.28, 0.06), lumenRadius: 0.048, structureId: "FMA_4720", description: "SVC into Right Atrium"),

            // Right Atrium (FMA_7096)
            SplineWaypoint(position: simd_float3(0.14, 0.12, 0.08), lumenRadius: 0.065, structureId: "FMA_7096", description: "Right Atrium"),

            // Tricuspid Valve (FMA_7234)
            SplineWaypoint(position: simd_float3(0.08, -0.02, 0.10), lumenRadius: 0.050, structureId: "FMA_7234", description: "Tricuspid Valve"),

            // Right Ventricle (FMA_7098)
            SplineWaypoint(position: simd_float3(0.04, -0.16, 0.12), lumenRadius: 0.070, structureId: "FMA_7098", description: "Right Ventricle"),

            // Pulmonary Trunk & Outflow
            SplineWaypoint(position: simd_float3(-0.02, 0.08, 0.12), lumenRadius: 0.045, structureId: "FMA_8614", description: "Pulmonary Trunk"),
            SplineWaypoint(position: simd_float3(-0.15, 0.22, 0.02), lumenRadius: 0.040, structureId: "FMA_8615", description: "Pulmonary Artery Left Branch"),

            // Alveolar Capillary Bed in Lungs (FMA_7309 / FMA_7310) - O2 Exchange Transition Zone
            SplineWaypoint(position: simd_float3(-0.35, 0.15, -0.08), lumenRadius: 0.055, structureId: "FMA_7310", description: "Left Pulmonary Capillary Bed (Oxygenation)"),
            SplineWaypoint(position: simd_float3(-0.25, 0.02, -0.12), lumenRadius: 0.045, structureId: "FMA_7310", description: "Pulmonary Venules"),

            // Pulmonary Veins returning to Left Atrium
            SplineWaypoint(position: simd_float3(-0.12, 0.06, -0.14), lumenRadius: 0.040, structureId: "FMA_8622", description: "Pulmonary Vein"),

            // Left Atrium (FMA_7099)
            SplineWaypoint(position: simd_float3(-0.06, 0.10, -0.10), lumenRadius: 0.060, structureId: "FMA_7099", description: "Left Atrium (Oxygenated)"),

            // Mitral / Bicuspid Valve (FMA_7235)
            SplineWaypoint(position: simd_float3(-0.08, -0.02, -0.04), lumenRadius: 0.048, structureId: "FMA_7235", description: "Mitral Valve"),

            // Left Ventricle (FMA_7097) - Primary systemic pump
            SplineWaypoint(position: simd_float3(-0.10, -0.18, 0.02), lumenRadius: 0.075, structureId: "FMA_7097", description: "Left Ventricle"),
            SplineWaypoint(position: simd_float3(-0.05, -0.26, 0.06), lumenRadius: 0.060, structureId: "FMA_7097", description: "Left Ventricular Apex"),

            // Aortic Valve into Ascending Aorta (FMA_3734)
            SplineWaypoint(position: simd_float3(0.00, 0.05, 0.00), lumenRadius: 0.045, structureId: "FMA_3734", description: "Aortic Valve"),
            SplineWaypoint(position: simd_float3(0.04, 0.25, -0.02), lumenRadius: 0.055, structureId: "FMA_3734", description: "Ascending Aorta"),
            SplineWaypoint(position: simd_float3(0.00, 0.38, -0.08), lumenRadius: 0.052, structureId: "FMA_3734", description: "Aortic Arch"),

            // Left Anterior Descending (LAD) Coronary Artery Branch (FMA_7101) - Site of Acute MI
            SplineWaypoint(position: simd_float3(-0.02, 0.14, 0.15), lumenRadius: 0.028, structureId: "FMA_7101", description: "Left Main Coronary Ostium"),
            SplineWaypoint(position: simd_float3(-0.04, 0.02, 0.20), lumenRadius: 0.024, structureId: "FMA_7101", description: "Proximal LAD Coronary Artery (Plaque Site)"),
            SplineWaypoint(position: simd_float3(-0.06, -0.12, 0.18), lumenRadius: 0.020, structureId: "FMA_7101", description: "Mid LAD Coronary Artery"),
            SplineWaypoint(position: simd_float3(-0.07, -0.22, 0.12), lumenRadius: 0.016, structureId: "FMA_7101", description: "Distal LAD at Apex")
        ]
    }
}
