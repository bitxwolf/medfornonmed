import SwiftUI

public struct ProviderSettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var testSuccessMessage: String? = nil
    @State private var testErrorMessage: String? = nil

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OpenAI-Compatible Provider Gateway").font(.caption).bold()) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://openrouter.ai/api/v1", text: $appState.baseUrl)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key (Optional for Local Ollama / LM Studio)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $appState.apiKey)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    Button(action: fetchModels) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(appState.isFetchingModels ? "Fetching Models..." : "Auto-Fetch Models from Endpoint")
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .disabled(appState.isFetchingModels)
                }

                Section(header: Text("Select Model").font(.caption).bold()) {
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(appState.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Connection Verification").font(.caption).bold()) {
                    Button(action: testConnection) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test Model Stream Ping")
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }

                    if let success = testSuccessMessage {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if let error = testErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Preset Providers").font(.caption).bold()) {
                    Button("OpenRouter (Multi-Model)") {
                        appState.baseUrl = "https://openrouter.ai/api/v1"
                        appState.selectedModel = "anthropic/claude-3.5-sonnet"
                    }
                    Button("Groq (Ultra-Fast 500 T/s)") {
                        appState.baseUrl = "https://api.groq.com/openai/v1"
                        appState.selectedModel = "llama-3.3-70b-versatile"
                    }
                    Button("Local Ollama / LM Studio (WiFi)") {
                        appState.baseUrl = "http://localhost:11434/v1"
                        appState.selectedModel = "llama3.2:latest"
                    }
                }
            }
            .navigationTitle("AI Tutor Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func fetchModels() {
        appState.isFetchingModels = true
        testSuccessMessage = nil
        testErrorMessage = nil

        Task {
            do {
                let models = try await OpenAICompatClient.shared.fetchModels(
                    baseUrl: appState.baseUrl,
                    apiKey: appState.apiKey
                )
                await MainActor.run {
                    appState.availableModels = models
                    if let first = models.first, !models.contains(appState.selectedModel) {
                        appState.selectedModel = first
                    }
                    appState.isFetchingModels = false
                    testSuccessMessage = "Successfully fetched \(models.count) models!"
                }
            } catch {
                await MainActor.run {
                    appState.isFetchingModels = false
                    testErrorMessage = "Fetch failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func testConnection() {
        testSuccessMessage = nil
        testErrorMessage = nil

        Task {
            do {
                let models = try await OpenAICompatClient.shared.fetchModels(
                    baseUrl: appState.baseUrl,
                    apiKey: appState.apiKey
                )
                await MainActor.run {
                    testSuccessMessage = "Connection verified! \(models.count) models reachable."
                }
            } catch {
                await MainActor.run {
                    testErrorMessage = "Connection error: \(error.localizedDescription)"
                }
            }
        }
    }
}
