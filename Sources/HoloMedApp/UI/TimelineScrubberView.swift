import SwiftUI
import HoloMedMetal

public struct TimelineScrubberView: View {
    @ObservedObject var appState: AppState

    private let timelineSteps: [(title: String, cmd: SceneCommandPayload)] = [
        ("1. Normal Flow", SceneCommandPayload(
            step: 1,
            action: .resetScene
        )),
        ("2. Focus LAD Artery", SceneCommandPayload(
            step: 2,
            action: .focusAndIsolate,
            targetIds: ["FMA_7101", "FMA_7088"],
            fadeOccluders: true,
            cameraPreset: "anterior_oblique"
        )),
        ("3. 50% Plaque Stenosis", SceneCommandPayload(
            step: 3,
            action: .applyPathology,
            pathologyType: "vascular_occlusion",
            severity: 0.50
        )),
        ("4. 95% Acute Thrombus & AMI", SceneCommandPayload(
            step: 4,
            action: .applyPathology,
            pathologyType: "myocardial_infarction",
            severity: 0.95
        ))
    ]

    public var body: some View {
        HStack(spacing: 12) {
            // Previous Step Button
            Button(action: {
                if appState.currentTimelineStep > 0 {
                    appState.currentTimelineStep -= 1
                    applyCurrentStep()
                }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13))
                    .foregroundColor(appState.currentTimelineStep > 0 ? .white : .white.opacity(0.3))
            }
            .disabled(appState.currentTimelineStep == 0)

            // Current Step Title Badge
            VStack(alignment: .center, spacing: 2) {
                Text(timelineSteps[appState.currentTimelineStep].title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Text("Step \(appState.currentTimelineStep + 1) of \(timelineSteps.count)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(minWidth: 140)

            // Next Step Button
            Button(action: {
                if appState.currentTimelineStep < timelineSteps.count - 1 {
                    appState.currentTimelineStep += 1
                    applyCurrentStep()
                }
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13))
                    .foregroundColor(appState.currentTimelineStep < timelineSteps.count - 1 ? .white : .white.opacity(0.3))
            }
            .disabled(appState.currentTimelineStep >= timelineSteps.count - 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color.black.opacity(0.7)
                .background(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func applyCurrentStep() {
        let step = timelineSteps[appState.currentTimelineStep]
        appState.sceneController?.executeCommand(step.cmd)
    }
}
