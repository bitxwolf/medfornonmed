import Foundation
import HoloMedMetal

public final class DualOutputParser {
    private var buffer: String = ""
    private var insideCommand: Bool = false
    private var commandBuffer: String = ""

    public var onTextDelta: ((String) -> Void)?
    public var onSceneCommand: ((SceneCommandPayload) -> Void)?
    public var onCitationFound: ((String) -> Void)?

    public init() {}

    public func reset() {
        buffer = ""
        insideCommand = false
        commandBuffer = ""
    }

    /// Feeds streaming chunk of tokens from OpenAI SSE connection
    public func feedChunk(_ chunk: String) {
        buffer += chunk

        while !buffer.isEmpty {
            if !insideCommand {
                if let openRange = buffer.range(of: "<scene_cmd>") {
                    // Everything before <scene_cmd> is prose text
                    let prose = String(buffer[..<openRange.lowerBound])
                    if !prose.isEmpty {
                        checkForCitations(in: prose)
                        onTextDelta?(prose)
                    }
                    buffer = String(buffer[openRange.upperBound...])
                    insideCommand = true
                    commandBuffer = ""
                } else {
                    // Check if buffer ends with a partial tag like "<scene"
                    if let partialTagIdx = buffer.lastIndex(of: "<") {
                        let potentialTag = String(buffer[partialTagIdx...])
                        if "<scene_cmd>".hasPrefix(potentialTag) {
                            // Leave partial tag in buffer for next chunk
                            let safeText = String(buffer[..<partialTagIdx])
                            if !safeText.isEmpty {
                                checkForCitations(in: safeText)
                                onTextDelta?(safeText)
                            }
                            buffer = potentialTag
                            return
                        }
                    }
                    // Emit all text as narrative
                    checkForCitations(in: buffer)
                    onTextDelta?(buffer)
                    buffer = ""
                }
            } else {
                if let closeRange = buffer.range(of: "</scene_cmd>") {
                    let jsonText = commandBuffer + String(buffer[..<closeRange.lowerBound])
                    buffer = String(buffer[closeRange.upperBound...])
                    insideCommand = false
                    commandBuffer = ""
                    parseAndEmitCommand(jsonText)
                } else {
                    commandBuffer += buffer
                    buffer = ""
                }
            }
        }
    }

    private func parseAndEmitCommand(_ jsonString: String) {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            let cmd = try decoder.decode(SceneCommandPayload.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.onSceneCommand?(cmd)
            }
        } catch {
            print("[DualOutputParser] Failed to decode scene command: \(error), raw: \(trimmed)")
        }
    }

    private func checkForCitations(in text: String) {
        // Regex search for [StatPearls: ...] or [PMID: ...]
        let pattern = "\\[(StatPearls[^\\]]+|PMID[^\\]]+|NBK[^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                let citation = nsText.substring(with: m.range)
                DispatchQueue.main.async { [weak self] in
                    self?.onCitationFound?(citation)
                }
            }
        }
    }
}
