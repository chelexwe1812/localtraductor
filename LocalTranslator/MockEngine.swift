import Foundation

/// Motor de prueba. No traduce de verdad: simula un retardo y
/// devuelve el texto marcado. Sirve para construir y probar toda
/// la app antes de integrar el modelo de IA real.
actor MockEngine: TranslationEngine {

    func loadModel(progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        if let progressHandler {
            // Reportamos progreso simulado en 10 pasos para ejercitar la UI.
            for i in 1...10 {
                try await Task.sleep(for: .milliseconds(100))
                progressHandler(Double(i) / 10.0)
            }
        } else {
            try await Task.sleep(for: .seconds(1))
        }
    }

    func translate(_ text: String,
                   from source: Language,
                   to target: Language,
                   tone: TranslationTone) async throws -> AsyncThrowingStream<String, Error> {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        let translated = "[\(source.rawValue)→\(target.rawValue)|\(tone.rawValue)] \(text)"
        // Trocea por palabras para imitar el goteo de tokens del modelo real.
        let words = translated.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        return AsyncThrowingStream { continuation in
            let task = Task {
                // Pequeño retardo inicial simulando "first-token-latency".
                try? await Task.sleep(for: .milliseconds(200))
                for (i, w) in words.enumerated() {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(i == 0 ? w : " " + w)
                    try? await Task.sleep(for: .milliseconds(40))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
