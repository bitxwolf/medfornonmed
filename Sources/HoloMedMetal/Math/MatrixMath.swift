import Foundation
import simd

public enum MatrixMath {
    public static func makePerspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let ys = 1.0 / tanf(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        return simd_float4x4(
            simd_float4(xs,  0,  0,           0),
            simd_float4(0,   ys, 0,           0),
            simd_float4(0,   0,  zs,         -1),
            simd_float4(0,   0,  zs * nearZ,  0)
        )
    }

    public static func makeLookAt(eye: simd_float3, target: simd_float3, up: simd_float3) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        let t = simd_float3(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye))

        return simd_float4x4(
            simd_float4(x.x, y.x, z.x, 0),
            simd_float4(x.y, y.y, z.y, 0),
            simd_float4(x.z, y.z, z.z, 0),
            simd_float4(t.x, t.y, t.z, 1)
        )
    }

    public static func makeTranslation(_ t: simd_float3) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = simd_float4(t.x, t.y, t.z, 1.0)
        return m
    }

    public static func makeScale(_ s: simd_float3) -> simd_float4x4 {
        return simd_float4x4(
            simd_float4(s.x, 0,   0,   0),
            simd_float4(0,   s.y, 0,   0),
            simd_float4(0,   0,   s.z, 0),
            simd_float4(0,   0,   0,   1)
        )
    }

    public static func makeRotation(radians: Float, axis: simd_float3) -> simd_float4x4 {
        let unitAxis = simd_normalize(axis)
        let ct = cosf(radians)
        let st = sinf(radians)
        let ci = 1 - ct
        let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z

        return simd_float4x4(
            simd_float4(ct + x * x * ci,     y * x * ci + z * st,  z * x * ci - y * st, 0),
            simd_float4(x * y * ci - z * st, ct + y * y * ci,     z * y * ci + x * st, 0),
            simd_float4(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci,     0),
            simd_float4(0,                   0,                   0,                   1)
        )
    }

    public static func normalMatrix(from modelMatrix: simd_float4x4) -> simd_float4x4 {
        let upper3x3 = simd_float3x3(
            simd_float3(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
            simd_float3(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
            simd_float3(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
        )
        let invTr = upper3x3.inverse.transpose
        return simd_float4x4(
            simd_float4(invTr.columns.0, 0),
            simd_float4(invTr.columns.1, 0),
            simd_float4(invTr.columns.2, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    public static func slerp(q1: simd_quatf, q2: simd_quatf, t: Float) -> simd_quatf {
        return simd_slerp(q1, q2, t)
    }
}
