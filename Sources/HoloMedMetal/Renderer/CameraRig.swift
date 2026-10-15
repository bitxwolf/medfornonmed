import Foundation
import simd

public enum CameraPreset: String {
    case anterior = "anterior"
    case anteriorOblique = "anterior_oblique"
    case leftLateral = "left_lateral"
    case rightLateral = "right_lateral"
    case superiorOblique = "superior_oblique"
    case posterior = "posterior"

    public var directionVector: simd_float3 {
        switch self {
        case .anterior:
            return simd_normalize(simd_float3(0.0, 0.0, 1.0))
        case .anteriorOblique:
            return simd_normalize(simd_float3(0.35, 0.25, 0.90))
        case .leftLateral:
            return simd_normalize(simd_float3(-1.0, 0.0, 0.0))
        case .rightLateral:
            return simd_normalize(simd_float3(1.0, 0.0, 0.0))
        case .superiorOblique:
            return simd_normalize(simd_float3(0.30, 0.70, 0.64))
        case .posterior:
            return simd_normalize(simd_float3(0.0, 0.0, -1.0))
        }
    }
}

public final class CameraRig {
    // Current live camera state
    public var eye: simd_float3
    public var target: simd_float3
    public var up: simd_float3 = simd_float3(0, 1, 0)
    public var fovRadians: Float = Float.pi / 4.0 // 45 degrees

    // Spherical coordinates for user touch orbit controls
    public var radius: Float = 1.4
    public var azimuth: Float = 0.0
    public var elevation: Float = 0.15

    // Animation transition state
    private var isAnimating: Bool = false
    private var animationStartTime: CFTimeInterval = 0.0
    private var animationDuration: CFTimeInterval = 0.90
    private var startEye: simd_float3 = simd_float3(0)
    private var startTarget: simd_float3 = simd_float3(0)
    private var endEye: simd_float3 = simd_float3(0)
    private var endTarget: simd_float3 = simd_float3(0)

    public init(initialEye: simd_float3 = simd_float3(0, 0.1, 1.4), initialTarget: simd_float3 = simd_float3(0, 0, 0)) {
        self.eye = initialEye
        self.target = initialTarget
        updateEyeFromSpherical()
    }

    /// Computes view matrix for rendering
    public func getViewMatrix() -> simd_float4x4 {
        return MatrixMath.makeLookAt(eye: eye, target: target, up: up)
    }

    /// Computes perspective projection matrix
    public func getProjectionMatrix(aspect: Float) -> simd_float4x4 {
        return MatrixMath.makePerspective(fovyRadians: fovRadians, aspect: aspect, nearZ: 0.01, farZ: 20.0)
    }

    /// Handles user touch drag / orbit
    public func rotate(deltaX: Float, deltaY: Float) {
        if isAnimating { return }
        azimuth += deltaX * 0.005
        elevation = max(-Float.pi * 0.45, min(Float.pi * 0.45, elevation + deltaY * 0.005))
        updateEyeFromSpherical()
    }

    /// Handles user touch pinch / zoom
    public func zoom(scaleDelta: Float) {
        if isAnimating { return }
        radius = max(0.25, min(3.5, radius / scaleDelta))
        updateEyeFromSpherical()
    }

    /// Handles user two-finger pan
    public func pan(deltaX: Float, deltaY: Float) {
        if isAnimating { return }
        let right = simd_normalize(simd_cross(simd_normalize(target - eye), up))
        let realUp = simd_cross(right, simd_normalize(target - eye))
        let panSpeed: Float = 0.001 * radius
        let offset = (-right * deltaX + realUp * deltaY) * panSpeed
        target += offset
        eye += offset
    }

    private func updateEyeFromSpherical() {
        let cosElev = cosf(elevation)
        let x = radius * cosElev * sinf(azimuth)
        let y = radius * sinf(elevation)
        let z = radius * cosElev * cosf(azimuth)
        eye = target + simd_float3(x, y, z)
    }

    /// Frames multiple anatomical targets with exact bounding-sphere math & SLERP
    public func frameTargets(centroids: [simd_float3], radii: [Float], preset: CameraPreset = .anteriorOblique) {
        guard !centroids.isEmpty else { return }

        // 1. Center of mass C
        var center = simd_float3(0)
        for c in centroids { center += c }
        center /= Float(centroids.count)

        // 2. Maximum enclosing radius R
        var maxR: Float = 0.05
        for (i, c) in centroids.enumerated() {
            let r = i < radii.count ? radii[i] : 0.05
            let dist = simd_distance(c, center) + r
            if dist > maxR { maxR = dist }
        }

        // 3. Distance d = (alpha * R) / sin(fov / 2) with alpha = 1.35 padding
        let alpha: Float = 1.35
        let dist = (alpha * maxR) / sinf(fovRadians * 0.5)

        // 4. Directional preset vector
        let dir = preset.directionVector
        let targetEye = center + dir * dist

        // 5. Begin smooth 0.9s cubic-eased transition
        startEye = eye
        startTarget = target
        endEye = targetEye
        endTarget = center
        animationStartTime = CACurrentMediaTime()
        isAnimating = true
    }

    /// Updates animation transition per frame
    public func update(currentTime: CFTimeInterval) {
        guard isAnimating else { return }

        let elapsed = currentTime - animationStartTime
        let progress = Float(min(1.0, max(0.0, elapsed / animationDuration)))

        // Cubic easing: t = t < 0.5 ? 4 * t^3 : 1 - pow(-2 * t + 2, 3) / 2
        let t: Float
        if progress < 0.5 {
            t = 4.0 * progress * progress * progress
        } else {
            let f = -2.0 * progress + 2.0
            t = 1.0 - (f * f * f) * 0.5
        }

        eye = simd_mix(startEye, endEye, simd_float3(t))
        target = simd_mix(startTarget, endTarget, simd_float3(t))

        if progress >= 1.0 {
            isAnimating = false
            // Synchronize spherical variables
            let diff = eye - target
            radius = simd_length(diff)
            if radius > 0.001 {
                elevation = asinf(max(-1.0, min(1.0, diff.y / radius)))
                azimuth = atan2f(diff.x, diff.z)
            }
        }
    }
}
