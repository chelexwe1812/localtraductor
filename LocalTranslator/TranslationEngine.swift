import Foundation

/// Tono / registro de la traducción. Se inyecta como directiva en el
/// prompt de usuario por cada llamada a `translate`, no en el system
/// prompt — así cambiar de tono es instantáneo (no recarga el modelo).
enum TranslationTone: String, CaseIterable, Identifiable, Hashable {
    case neutral
    case formal
    case casual
    case technical

    var id: String { rawValue }

    /// Frase en inglés que se concatena al prompt para dirigir el estilo
    /// de salida del modelo. `nil` para `.neutral`: no añadimos nada y
    /// queda el comportamiento original (traducción "neutra").
    var instruction: String? {
        switch self {
        case .neutral:
            return nil
        case .formal:
            return "Use a formal, professional register."
        case .casual:
            return "Use a casual, colloquial register."
        case .technical:
            return "Use a precise technical register and preserve technical terms in their original form when there is no clear equivalent."
        }
    }
}

/// Contrato que todo motor de traducción debe cumplir.
/// Hoy lo implementará un motor falso (mock); mañana, MLX con un modelo real.
/// La UI no necesita saber cuál se usa.
protocol TranslationEngine: Sendable {
    /// Carga el modelo en memoria. Puede tardar, por eso es async.
    /// El `progressHandler` opcional recibe valores entre 0 y 1 mientras
    /// se descargan los pesos del modelo (solo aplica la primera vez).
    func loadModel(progressHandler: (@Sendable (Double) -> Void)?) async throws

    /// Traduce un texto de un idioma a otro emitiendo deltas (fragmentos)
    /// según los va generando el modelo. La UI concatena los chunks para
    /// mostrar la traducción palabra a palabra. `tone` ajusta el registro
    /// de salida (formal / casual / técnico / neutro).
    func translate(_ text: String,
                   from source: Language,
                   to target: Language,
                   tone: TranslationTone) async throws -> AsyncThrowingStream<String, Error>
}

extension TranslationEngine {
    /// Atajo cuando no necesitamos seguir el progreso.
    func loadModel() async throws {
        try await loadModel(progressHandler: nil)
    }
}
