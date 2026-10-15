import Foundation
import HoloMedMetal

public final class OpenAICompatClient {
    public static let shared = OpenAICompatClient()

    /// Sanitizes and normalizes any user-entered OpenAI-compatible base URL
    public static func normalizeBaseUrl(_ rawUrl: String) -> String {
        var url = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        if url.hasSuffix("/chat/completions") {
            url = String(url.dropLast("/chat/completions".count))
        } else if url.hasSuffix("/models") {
            url = String(url.dropLast("/models".count))
        }

        if !url.contains("/v1") && !url.contains("/v1beta") && !url.contains("/api") {
            url += "/v1"
        }
        return url
    }

    /// Fetches all available models from GET {base_url}/models
    public func fetchModels(baseUrl: String, apiKey: String) async throws -> [String] {
        let normalized = Self.normalizeBaseUrl(baseUrl)
        guard let url = URL(string: "\(normalized)/models") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct ModelsResponse: Codable {
            struct ModelData: Codable {
                let id: String
            }
            let data: [ModelData]
        }

        if let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) {
            return decoded.data.map { $0.id }.sorted()
        }

        // Fallback for simple string array
        struct FlatModelsResponse: Codable {
            let models: [String]
        }
        if let decodedFlat = try? JSONDecoder().decode(FlatModelsResponse.self, from: data) {
            return decodedFlat.models.sorted()
        }

        return ["default-model"]
    }

    /// Streams AI tutor completions with multiplexed <scene_cmd> blocks
    public func streamTutorChat(
        userPrompt: String,
        baseUrl: String,
        apiKey: String,
        model: String,
        level: ComprehensionLevel,
        mode: AppMode,
        parser: DualOutputParser
    ) async throws {
        let normalized = Self.normalizeBaseUrl(baseUrl)
        guard let url = URL(string: "\(normalized)/chat/completions") else {
            throw URLError(.badURL)
        }

        let systemPrompt = buildSystemPrompt(level: level, mode: mode)

        let bodyPayload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.4,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        parser.reset()

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }
            let payload = String(trimmed.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let chunkData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            parser.feedChunk(content)
        }
    }

    private func buildSystemPrompt(level: ComprehensionLevel, mode: AppMode) -> String {
        return """
        You are HoloMed 3D AI Medical Tutor, running natively on iPhone with Apple Silicon Metal compute shaders at 120 FPS.
        Current Comprehension Level: \(level.rawValue) (\(level.title))
        Current Active Mode: \(mode.rawValue)

        VALID 3D ANATOMY REGISTRY (You MUST use these exact IDs in commands):
        - FMA_7088: Heart (Cor)
        - FMA_7096: Right Atrium (Atrium dextrum cordis)
        - FMA_7098: Right Ventricle (Ventriculus dexter cordis)
        - FMA_7099: Left Atrium (Atrium sinistrum cordis)
        - FMA_7097: Left Ventricle (Ventriculus sinister cordis)
        - FMA_7101: Left Anterior Descending (LAD) Coronary Artery
        - FMA_7100: Right Coronary Artery (RCA)
        - FMA_3734: Aorta (Ascending Aorta & Arch)
        - FMA_7309: Right Lung
        - FMA_7310: Left Lung
        - FMA_7480: Thoracic Ribcage & Sternum (Occluder)

        CRITICAL OUTPUT PROTOCOL:
        You must stream your medical explanation in markdown accompanied by synchronized <scene_cmd> blocks at the exact moment a visual transition occurs.
        Command format:
        <scene_cmd>
        {"step": 1, "action": "FOCUS_AND_ISOLATE", "target_ids": ["FMA_7096", "FMA_7098"], "camera_preset": "anterior_oblique"}
        </scene_cmd>

        For pathology (e.g. Heart Attack / AMI):
        <scene_cmd>
        {"step": 2, "action": "APPLY_PATHOLOGY", "pathology_type": "myocardial_infarction", "severity": 0.95, "target_id": "FMA_7101"}
        </scene_cmd>

        STYLE GUIDELINES BY COMPREHENSION LEVEL:
        - layperson: Use vivid everyday biology analogies (e.g. comparing coronary arteries to fuel lines, valves to one-way swing doors, ischemia to a clogged engine line). Keep sentences punchy.
        - pre_med: Explain pressure differentials, cardiac conduction, preload/afterload, coronary anatomy, and ECG correlates.
        - clinician: Use precise Latin nomenclature, cellular pathophysiology (loss of ATP, microvascular no-reflow, troponin release), hemodynamic formulas, and direct citations like [StatPearls: Acute MI (NBK459269)].
        """
    }
}
