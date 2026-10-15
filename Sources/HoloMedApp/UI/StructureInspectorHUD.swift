import SwiftUI
import HoloMedMetal

public struct StructureInspectorHUD: View {
    let node: AnatomicalMeshNode
    let onAskAI: (String) -> Void
    let onSimulatePathology: () -> Void
    let onClose: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.commonName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(node.latinName)
                        .font(.system(size: 12, weight: .regular))
                        .italic()
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Text(node.fmaId)
                    .font(.system(size: 11, weight: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.3))
                    .foregroundColor(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            HStack(spacing: 8) {
                Label(node.organSystem.capitalized, systemImage: "cross.case.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            Divider().background(Color.white.opacity(0.2))

            HStack(spacing: 8) {
                Button(action: {
                    onAskAI("Explain the function and blood flow through the \(node.commonName) [\(node.fmaId)]")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Ask AI Tutor")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                Button(action: onSimulatePathology) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Simulate Pathology")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(
            Color.black.opacity(0.75)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
    }
}
