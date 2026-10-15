import SwiftUI
import HoloMedMetal

public struct MainContentView: View {
    @StateObject private var appState = AppState()
    @State private var showSettingsSheet: Bool = false
    @State private var isChatExpanded: Bool = true

    public var body: some View {
        ZStack {
            // Full Screen 120 FPS ProMotion Metal Viewport
            HoloMedMetalView(appState: appState)
                .ignoresSafeArea()

            // HUD Overlays
            VStack(spacing: 0) {
                // Top Navigation Bar
                TopNavBar(appState: appState, showSettingsSheet: $showSettingsSheet)

                // Engine & Hardware Telemetry Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("120 FPS ProMotion • Metal UMA • 100,000 Cells")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(.top, 6)

                Spacer()

                // Structure Inspector HUD when tapped
                if let inspected = appState.inspectedStructure {
                    StructureInspectorHUD(
                        node: inspected,
                        onAskAI: { prompt in
                            // Auto-focus chat drawer and submit prompt
                            isChatExpanded = true
                            appState.messages.append(ChatMessage(sender: .user, content: prompt))
                            triggerAIPrompt(prompt)
                        },
                        onSimulatePathology: {
                            appState.setMode(.pathology)
                        },
                        onClose: {
                            appState.inspectedStructure = nil
                            appState.sceneController?.renderer?.activeHighlightFmaId = nil
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Timeline Scrubber
                TimelineScrubberView(appState: appState)
                    .padding(.bottom, 8)

                // Floating AI Medical Tutor Chat Drawer
                AITutorDrawer(appState: appState, isExpanded: $isChatExpanded)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            ProviderSettingsView(appState: appState)
        }
        .preferredColorScheme(.dark)
    }

    private func triggerAIPrompt(_ prompt: String) {
        appState.isStreaming = true
        appState.currentStreamText = ""

        Task {
            let parser = DualOutputParser()
            var currentCommands: [SceneCommandPayload] = []
            var foundCitations: [String] = []

            parser.onTextDelta = { delta in
                appState.currentStreamText += delta
            }

            parser.onSceneCommand = { cmd in
                currentCommands.append(cmd)
                appState.sceneController?.executeCommand(cmd)
            }

            parser.onCitationFound = { cit in
                if !foundCitations.contains(cit) {
                    foundCitations.append(cit)
                }
            }

            do {
                try await OpenAICompatClient.shared.streamTutorChat(
                    userPrompt: prompt,
                    baseUrl: appState.baseUrl,
                    apiKey: appState.apiKey,
                    model: appState.selectedModel,
                    level: appState.comprehensionLevel,
                    mode: appState.activeMode,
                    parser: parser
                )

                let tutorMsg = ChatMessage(
                    sender: .aiTutor,
                    content: appState.currentStreamText,
                    sceneCommands: currentCommands,
                    citations: foundCitations
                )
                appState.messages.append(tutorMsg)
                appState.currentStreamText = ""
                appState.isStreaming = false
            } catch {
                let fallback = "The \(appState.inspectedStructure?.commonName ?? "structure") [\(appState.inspectedStructure?.fmaId ?? "")] plays a critical role in cardiovascular hemodynamics. When coronary perfusion is impeded, downstream tissue quickly exhibits ischemic dysfunction."
                appState.messages.append(ChatMessage(
                    sender: .aiTutor,
                    content: fallback,
                    citations: ["StatPearls: Myocardial Ischemia and Infarction (NBK459269)"]
                ))
                appState.currentStreamText = ""
                appState.isStreaming = false
            }
        }
    }
}
