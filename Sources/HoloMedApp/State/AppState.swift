import Foundation
import SwiftUI
import HoloMedMetal
import simd

public enum AppMode: String, CaseIterable, Identifiable {
    case anatomy = "Anatomy & Flow"
    case pathology = "Pathology & Infarction"

    public var id: String { rawValue }
    public var iconName: String {
        switch self {
        case .anatomy: return "heart.fill"
        case .pathology: return "cross.vial.fill"
        }
    }
}

public enum ComprehensionLevel: String, CaseIterable, Identifiable {
    case layperson = "layperson"
    case preMed = "pre_med"
    case clinician = "clinician"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .layperson: return "Everyday Biology"
        case .preMed: return "Pre-Med Student"
        case .clinician: return "Clinician / MD"
        }
    }

    public var subtitle: String {
        switch self {
        case .layperson: return "Plain English & everyday analogies"
        case .preMed: return "Physiological mechanisms & terms"
        case .clinician: return "Hemodynamics, histology & StatPearls citations"
        }
    }
}

public struct ChatMessage: Identifiable {
    public let id: UUID = UUID()
    public let sender: MessageSender
    public var content: String
    public var sceneCommands: [SceneCommandPayload] = []
    public var citations: [String] = []
    public var timestamp: Date = Date()

    public enum MessageSender {
        case user
        case aiTutor
    }
}

@MainActor
public final class AppState: ObservableObject {
    // Mode & Comprehension Level
    @Published public var activeMode: AppMode = .anatomy
    @Published public var comprehensionLevel: ComprehensionLevel = .layperson

    // Provider Configuration (Universal OpenAI-Compatible)
    @Published public var baseUrl: String = "https://openrouter.ai/api/v1"
    @Published public var apiKey: String = ""
    @Published public var selectedModel: String = "anthropic/claude-3.5-sonnet"
    @Published public var availableModels: [String] = [
        "anthropic/claude-3.5-sonnet",
        "google/gemini-2.0-flash",
        "openai/gpt-4o",
        "meta-llama/llama-3.3-70b-instruct"
    ]
    @Published public var isFetchingModels: Bool = false
    @Published public var connectionStatus: String = "Ready"

    // Inspected 3D Structure
    @Published public var inspectedStructure: AnatomicalMeshNode? = nil

    // Chat & Tutor Stream
    @Published public var messages: [ChatMessage] = []
    @Published public var isStreaming: Bool = false
    @Published public var currentStreamText: String = ""
    @Published public var currentTimelineStep: Int = 0
    @Published public var totalTimelineSteps: Int = 1

    // 3D Scene Controller Reference
    public var sceneController: SceneController?

    public init() {
        seedInitialWelcomeMessage()
    }

    private func seedInitialWelcomeMessage() {
        let welcome = ChatMessage(
            sender: .aiTutor,
            content: "Welcome to **HoloMed 3D**! I am your AI Medical Tutor.\n\nRunning raw **Metal Shading Language (MSL)** compute kernels on Apple Silicon UMA, simulating **100,000 instanced erythrocytes** at a locked **120 FPS ProMotion**.\n\nTap any organ to inspect it, toggle **Pathology Mode** to trigger an Acute Myocardial Infarction simulation, or ask a question below!",
            sceneCommands: [],
            citations: ["StatPearls: Human Cardiovascular Physiology (NBK459269)"]
        )
        messages.append(welcome)
    }

    public func setMode(_ mode: AppMode) {
        self.activeMode = mode
        if mode == .pathology {
            // Trigger acute myocardial infarction simulation
            sceneController?.executeCommand(SceneCommandPayload(
                action: .applyPathology,
                pathologyType: "myocardial_infarction",
                severity: 0.95
            ))
            let msg = ChatMessage(
                sender: .aiTutor,
                content: "**Mode: Acute Myocardial Infarction (Pathology)**\n\nA 95% thrombotic occlusion has formed in the **Left Anterior Descending (LAD) coronary artery** [FMA_7101].\n\nNotice the **100,000 blood cells** immediately decelerating and stagnating upstream. Downstream anterior left ventricular myocardium [FMA_7097] is undergoing hypoxic cyanosis and tissue infarction.",
                sceneCommands: [],
                citations: ["StatPearls: Acute Coronary Syndrome (NBK459269)"]
            )
            messages.append(msg)
        } else {
            sceneController?.resetScene()
        }
    }
}
