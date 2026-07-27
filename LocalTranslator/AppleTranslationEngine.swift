import Foundation
import Translation

/// Motor de traducción "normal": usa el framework Translation de Apple,
/// el mismo que la app Traducir del sistema. Modelos neuronales clásicos,
/// gratis, on-device y prácticamente instantáneos.
///
/// Diferencias con `MLXEngine`:
/// - No hay nada pesado que cargar: `loadModel` es inmediato.
/// - No entiende de tonos (`tone` se ignora); la UI oculta ese menú
///   cuando este motor está activo.
/// - Los idiomas se descargan por pares bajo demanda. Si el par pedido no
///   está instalado, lanzamos `EngineError.languagesNotInstalled` y el
///   ViewModel abre el flujo de descarga del sistema.
///
/// La clase queda aislada al MainActor (isolación por defecto del proyecto),
/// lo que la hace `Sendable`; la inferencia real ocurre dentro del framework,
/// fuera del hilo principal, así que no bloqueamos la UI.
final class AppleTranslationEngine: TranslationEngine {

    /// Sesión cacheada para el último par de idiomas usado. Crear una
    /// `TranslationSession` es barato, pero reutilizarla evita el coste
    /// de re-preparar el mismo par en traducciones consecutivas.
    private var session: TranslationSession?
    private var sessionPair: (source: Language, target: Language)?

    // MARK: - TranslationEngine

    /// El traductor del sistema no requiere carga previa. Reportamos 1.0
    /// por cortesía con cualquier UI de progreso.
    func loadModel(progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        progressHandler?(1.0)
    }

    func translate(_ text: String,
                   from source: Language,
                   to target: Language,
                   tone: TranslationTone) async throws -> AsyncThrowingStream<String, Error> {

        // El ViewModel resuelve `.autoDetect` antes de llamar al motor;
        // si llegara aquí es un par inválido para el framework.
        guard source != .autoDetect,
              let sourceLanguage = source.localeLanguage,
              let targetLanguage = target.localeLanguage else {
            throw EngineError.languagePairUnsupported(source: source, target: target)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        // Comprobamos la disponibilidad del par antes de crear la sesión:
        // el init `installedSource` exige idiomas ya instalados.
        let availability = LanguageAvailability()
        switch await availability.status(from: sourceLanguage, to: targetLanguage) {
        case .installed:
            break
        case .supported:
            throw EngineError.languagesNotInstalled(source: source, target: target)
        case .unsupported:
            throw EngineError.languagePairUnsupported(source: source, target: target)
        @unknown default:
            break
        }

        try Task.checkCancellation()

        let session = sessionFor(source: source, target: target,
                                 sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)

        // El framework no streamea: devolvemos la traducción completa como
        // un único chunk para cumplir el contrato del protocolo.
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await session.translate(trimmed)
                    continuation.yield(response.targetText)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Sesiones

    private func sessionFor(source: Language, target: Language,
                            sourceLanguage: Locale.Language,
                            targetLanguage: Locale.Language) -> TranslationSession {
        if let session, sessionPair?.source == source, sessionPair?.target == target {
            return session
        }
        let newSession = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        session = newSession
        sessionPair = (source, target)
        return newSession
    }
}

// MARK: - Mapeo Language → Locale.Language

extension Language {
    /// Equivalente del framework Translation para este idioma. `nil` para
    /// `.autoDetect`, que no es un idioma real. Los raw values del enum
    /// ("en", "es", "zh-Hans"…) son identificadores BCP-47 válidos.
    var localeLanguage: Locale.Language? {
        guard self != .autoDetect else { return nil }
        return Locale.Language(identifier: rawValue)
    }
}
