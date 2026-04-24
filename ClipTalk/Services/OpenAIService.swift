import Foundation

enum OpenAIError: LocalizedError {
    case missingKey
    case invalidResponse
    case http(status: Int, body: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your OpenAI API key in Settings to generate plain-English explanations."
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        case .http(let status, let body):
            return "OpenAI HTTP \(status): \(body.prefix(200))"
        case .network(let msg):
            return "Network error: \(msg)"
        }
    }
}

/// Calls OpenAI chat completions to rewrite broadcast commentary into plain
/// English. Uses GPT-4o-mini — cheap (~$0.0001 per clip) and fast.
enum OpenAIService {

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Rewrite a broadcast transcript into plain English. Returns nil if the
    /// user hasn't set a key; throws on network/API errors.
    static func rewriteToCleanEnglish(_ transcript: String) async throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard let key = Keychain.getOpenAIKey(), !key.isEmpty else {
            throw OpenAIError.missingKey
        }

        let system = """
        You rewrite live sports broadcast commentary into plain, natural English for language learners. \
        Keep one or two short sentences. Explain what actually happened in the play, expanding any \
        implicit subject or dropped words. Do not add quotes, emojis, or commentary about the rewrite. \
        Return only the plain-English version.
        """

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": trimmed],
            ],
            "temperature": 0.3,
            "max_tokens": 200,
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenAIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(status: http.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
