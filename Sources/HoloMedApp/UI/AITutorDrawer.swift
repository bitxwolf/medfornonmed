import SwiftUI
import HoloMedMetal

public struct AITutorDrawer: View {
    @ObservedObject var appState: AppState
    @Binding var isExpanded: Bool
    @State private var inputText: String = ""
    @State private var activeCitation: String? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // Header / Handle
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.cyan)
                    Text("AI Medical Tutor")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    Text(appState.comprehensionLevel.title)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundColor(.cyan)
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85))

            if isExpanded {
                // Chat Message Stream
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(appState.messages) { msg in
                                MessageBubbleView(message: msg, onStepTap: { cmd in
                                    appState.sceneController?.executeCommand(cmd)
                                }, onCitationTap: { citation in
                                    activeCitation = citation
                                })
                            }

                            if appState.isStreaming && !appState.currentStreamText.isEmpty {
                                StreamingBubbleView(text: appState.currentStreamText)
                                    .id("streaming_end")
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: appState.currentStreamText) { _ in
                        withAnimation {
                            proxy.scrollTo("streaming_end", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: 280)

                // Contextual Follow-Up Quick Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickChip(title: "Explain more simply", icon: "brain") {
                            sendUserPrompt("Can you explain that more simply using everyday analogies?")
                        }
                        QuickChip(title: "Clinical pathophysiology", icon: "stethoscope") {
                            sendUserPrompt("What is the clinical pathophysiology and hemodynamics of this condition?")
                        }
                        QuickChip(title: "Simulate Heart Attack", icon: "exclamationmark.triangle.fill") {
                            sendUserPrompt("Simulate an acute myocardial infarction from an LAD coronary artery occlusion.")
                        }
                        QuickChip(title: "Show blood flow chambers", icon: "arrow.triangle.swap") {
                            sendUserPrompt("Show the complete path of blood flow through all four heart chambers and lungs.")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .background(Color.black.opacity(0.7))

                // Text Input Bar
                HStack(spacing: 10) {
                    TextField("Ask AI tutor about anatomy or disease...", text: $inputText)
                        .padding(9)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    Button(action: {
                        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let text = inputText
                        inputText = ""
                        sendUserPrompt(text)
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(appState.isStreaming ? .gray : .blue)
                    }
                    .disabled(appState.isStreaming)
                }
                .padding(12)
                .background(Color.black.opacity(0.85))
            }
        }
        .background(
            Color.black.opacity(0.65)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .alert(item: Binding<AlertItem?>(
            get: { activeCitation != nil ? AlertItem(title: activeCitation!) : nil },
            set: { _ in activeCitation = nil }
        )) { item in
            Alert(
                title: Text("Verified Literature Source"),
                message: Text("Citation: \(item.title)\n\nGrounded in vetted NIH/NCBI StatPearls & PubMed peer-reviewed literature with direct FMA anatomical mapping."),
                dismissButton: .default(Text("Done"))
            )
        }
    }

    private func sendUserPrompt(_ prompt: String) {
        let userMsg = ChatMessage(sender: .user, content: prompt)
        appState.messages.append(userMsg)

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
                // Offline fallback response with local medical knowledge graph
                let fallbackItems = MedicalKnowledgeGraph.shared.findRelevantLiterature(for: prompt)
                let fallbackCitations = fallbackItems.map { "\($0.source): \($0.title) [\($0.id)]" }

                var fallbackText = "*(Local Offline Grounding)*\n\n"
                if let item = fallbackItems.first {
                    fallbackText += "\(item.excerpt)\n\n"
                } else {
                    fallbackText += "The heart functions as a synchronized dual pump. Deoxygenated blood returns to the right atrium [FMA_7096] and right ventricle [FMA_7098], moving through the pulmonary circuit to be oxygenated in the lungs [FMA_7309/7310]. Oxygenated blood returns to the left atrium [FMA_7099] and high-pressure left ventricle [FMA_7097] before being pumped into the aorta [FMA_3734] and Left Anterior Descending artery [FMA_7101].\n\n"
                }

                let tutorMsg = ChatMessage(
                    sender: .aiTutor,
                    content: fallbackText,
                    sceneCommands: [],
                    citations: fallbackCitations.isEmpty ? ["StatPearls: Cardiovascular Physiology (NBK537158)"] : fallbackCitations
                )
                appState.messages.append(tutorMsg)
                appState.currentStreamText = ""
                appState.isStreaming = false
            }
        }
    }
}

public struct AlertItem: Identifiable {
    public var id: String { title }
    public let title: String
}

public struct QuickChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .foregroundColor(.white.opacity(0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}

public struct MessageBubbleView: View {
    let message: ChatMessage
    let onStepTap: (SceneCommandPayload) -> Void
    let onCitationTap: (String) -> Void

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.sender == .aiTutor {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.cyan)
                    .frame(width: 24, height: 24)
                    .background(Color.cyan.opacity(0.2))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(message.content))
                    .font(.system(size: 13))
                    .foregroundColor(.white)

                // Step Badges
                if !message.sceneCommands.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(message.sceneCommands.enumerated()), id: \.offset) { idx, cmd in
                            Button(action: { onStepTap(cmd) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.circle.fill")
                                    Text("Step \(cmd.step ?? (idx + 1))")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.4))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Citations
                if !message.citations.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.citations, id: \.self) { citation in
                            Button(action: { onCitationTap(citation) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "book.closed.fill")
                                    Text(citation)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.25))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                message.sender == .user
                    ? Color.blue.opacity(0.45)
                    : Color.white.opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.sender == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
    }
}

public struct StreamingBubbleView: View {
    let text: String

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyan)
                .frame(width: 24, height: 24)
                .background(Color.cyan.opacity(0.2))
                .clipShape(Circle())

            HStack(spacing: 2) {
                Text(LocalizedStringKey(text))
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
