import Foundation
import Observation
import NaturalLanguage
import AppKit

@MainActor
@Observable
final class TranslationViewModel {

    /// Pantalla actualmente visible dentro del popover.
    enum Screen {
        case translator
        case settings
    }

    // MARK: - Estado observable por la UI
    var screen: Screen = .translator
    var inputText: String = "" {
        didSet {
            if sourceLanguage == .autoDetect || settings.autoDetectLanguage {
                updateDetectedLanguage()
            }
            handleInputChange()
        }
    }
    var outputText: String = ""
    var sourceLanguage: Language = .english {
        didSet {
            // Mantenemos source ≠ target para que el botón ⇄ tenga sentido
            // y el modelo no reciba prompts del tipo "traduce de X a X".
            if sourceLanguage == targetLanguage {
                // Si veníamos de .autoDetect, no podemos devolver eso al
                // picker de destino (no lo expone). Caemos en un fallback.
                if oldValue == .autoDetect {
                    targetLanguage = (sourceLanguage == .english) ? .spanish : .english
                } else {
                    targetLanguage = oldValue
                }
            }
            // Al activar auto-detect con texto ya escrito, intentamos detectar
            // inmediatamente para que el selector salte al idioma real.
            if sourceLanguage == .autoDetect {
                updateDetectedLanguage()
            }
        }
    }
    var targetLanguage: Language = .spanish {
        didSet {
            if targetLanguage == sourceLanguage {
                sourceLanguage = oldValue
            }
        }
    }
    var modelState: ModelState = .idle
    var isTranslating: Bool = false

    /// Progreso (0…1) de la descarga del modelo. Lo consume la pantalla de
    /// bienvenida para pintar la barra. Se mantiene en 0 cuando no estamos
    /// descargando.
    var downloadProgress: Double = 0

    /// Bandera momentánea que dispara un halo Siri rodeando toda la ventana
    /// del traductor justo cuando se abre por primera vez después de la
    /// pantalla de bienvenida. Una vez celebrado, vuelve a `false`.
    var firstOpenGlow: Bool = false

    /// Contador que la vista observa para devolver el foco al `TextEditor`
    /// de entrada cada vez que se abre el popover (por icono o atajo). Lo
    /// incrementamos en `requestInputFocus()` y la vista hace `onChange`.
    var focusInputToken: Int = 0

    // MARK: - Dependencias y tareas internas
    private let engine: TranslationEngine
    private let settings: AppSettings
    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: Duration = .milliseconds(450)
    private let languageRecognizer = NLLanguageRecognizer()

    /// Último contenido del portapapeles que esta sesión ya "consumió". Sirve
    /// para que el auto-pegado al abrir no repita el mismo texto cada vez.
    private var lastSeenClipboard: String?

    // MARK: - Init
    /// Recibe el motor de traducción y la fuente de preferencias.
    init(engine: TranslationEngine, settings: AppSettings = .shared) {
        self.engine = engine
        self.settings = settings
    }

    // MARK: - Carga del modelo
    func loadModel() async {
        modelState = .loading
        downloadProgress = 0
        do {
            try await engine.loadModel { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress
                }
            }
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Limpiar la entrada y la salida
    /// Cancela cualquier traducción en vuelo y vacía los campos de texto.
    /// La invoca el `StatusBarController` cuando el popover se cierra,
    /// si el usuario activó "Vaciar al cerrar".
    func clearInput() {
        translationTask?.cancel()
        debounceTask?.cancel()
        inputText = ""
        outputText = ""
        isTranslating = false
    }

    /// Vuelve a la pantalla del traductor (se invoca al cerrarse el popover).
    func resetToTranslator() {
        screen = .translator
    }

    /// Dispara un halo Siri momentáneo alrededor de todo el ContentView,
    /// para celebrar la primera apertura del traductor tras la pantalla de
    /// bienvenida. El propio `SiriGlow` hace fade-in/out; aquí solo dejamos
    /// la bandera encendida 0.7 s para que la fase visible dure ~1 s.
    func celebrateFirstOpen() {
        firstOpenGlow = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.firstOpenGlow = false
        }
    }

    /// Pide a la vista que devuelva el foco al `TextEditor` de entrada.
    /// El usuario debe poder teclear inmediatamente tras abrir el popover
    /// con el atajo global, sin tener que hacer click primero en el área.
    func requestInputFocus() {
        focusInputToken &+= 1
    }

    // MARK: - Traducir el portapapeles al abrir

    /// Si el portapapeles contiene texto distinto al de la última vez que lo
    /// vimos, lo pega en `inputText` y lanza la traducción al instante.
    /// Pensado para invocarse justo antes de que el popover se muestre. No
    /// sobrescribe si el usuario ya tiene algo escrito ni si está navegando
    /// en Configuración.
    func translateClipboardOnOpenIfNeeded() {
        guard settings.translateClipboardOnOpen, screen == .translator else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Si es el mismo texto que ya consumimos, no hacemos nada.
        guard text != lastSeenClipboard else { return }
        lastSeenClipboard = text

        // No pisar lo que el usuario ya está escribiendo.
        guard inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        inputText = text
        // Si el modelo aún no está listo, translate() devolverá silenciosamente.
        translate()
    }

    // MARK: - Intercambiar idiomas (botón ⇄)
    func swapLanguages() {
        // En modo auto sin detección aún, no hay nada que intercambiar.
        guard sourceLanguage != .autoDetect else { return }
        // El `didSet` de `sourceLanguage` se encarga de mover target al
        // antiguo valor de source cuando los dos coinciden, así que basta
        // con asignar el target al source.
        sourceLanguage = targetLanguage
        // Si ya hay una traducción, el texto traducido pasa a ser la entrada.
        if !outputText.isEmpty {
            inputText = outputText
        }
    }

    // MARK: - Traducción a demanda
    /// Lanza la traducción del texto actual. La invoca la UI al pulsar Enter,
    /// el botón "Traducir", o el debounce automático si está habilitado.
    /// Si ya hay una traducción en vuelo, se cancela.
    func translate() {
        translationTask?.cancel()
        debounceTask?.cancel()

        let textSnapshot = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textSnapshot.isEmpty else {
            outputText = ""
            isTranslating = false
            return
        }

        guard modelState == .ready else { return }

        // Red de seguridad: si seguimos en .autoDetect al pulsar Enter,
        // forzamos una detección sobre el snapshot. El didSet de inputText
        // ya intenta detectar mientras se escribe, pero textos muy cortos
        // se ignoran allí y pueden llegar aquí sin haber actualizado el
        // picker.
        if sourceLanguage == .autoDetect {
            if let detected = detectLanguage(for: textSnapshot) {
                sourceLanguage = detected
            } else {
                // Prependemos el emoji a mano (no entra en el catálogo) para
                // evitar colisiones de símbolos auto-generados con otras
                // entradas que solo se diferenciaban por el prefijo.
                outputText = "⚠️ " + String(
                    localized: "No se pudo detectar el idioma de origen.",
                    locale: settings.appLanguage.locale
                )
                return
            }
        }

        // Si tras detectar coincide con el destino, no hay traducción posible.
        if sourceLanguage == targetLanguage {
            outputText = textSnapshot
            return
        }

        isTranslating = true
        // Limpiamos para que los deltas vayan apareciendo sobre lienzo en blanco.
        outputText = ""

        // Preservación de código/markdown: extraemos bloques fenced, código
        // inline y URLs, los sustituimos por placeholders `⟦C0⟧` y se los
        // pasamos al modelo. Conforme llegan los chunks restauramos los
        // placeholders al vuelo para que el usuario vea el código original.
        let (sanitized, preservedBlocks) = MarkdownCodePreserver.extract(textSnapshot)

        let toneSnapshot = settings.translationTone
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.engine.translate(
                    sanitized,
                    from: self.sourceLanguage,
                    to: self.targetLanguage,
                    tone: toneSnapshot
                )
                var buffer = ""
                for try await chunk in stream {
                    try Task.checkCancellation()
                    buffer += chunk
                    // Restauramos placeholders dentro del buffer parcial para
                    // que el código aparezca tal cual mientras se streamea.
                    self.outputText = MarkdownCodePreserver.restore(buffer, with: preservedBlocks)
                }
                try Task.checkCancellation()
                let final = MarkdownCodePreserver
                    .restore(buffer, with: preservedBlocks)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.outputText = final
            } catch is CancellationError {
                // Traducción descartada por una nueva: no hacemos nada
            } catch {
                self.outputText = "⚠️ " + String(
                    localized: "Error: \(error.localizedDescription)",
                    locale: self.settings.appLanguage.locale
                )
            }
            self.isTranslating = false
        }
    }

    // MARK: - Auto-traducción (debounce condicional)

    /// Reacciona a cambios de `inputText`. Solo dispara traducción automática
    /// si el usuario lo activó en Configuración.
    private func handleInputChange() {
        guard settings.autoTranslate else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceDelay)
            guard !Task.isCancelled else { return }
            self.translate()
        }
    }

    // MARK: - Detección de idioma

    /// Pasa `inputText` por el detector y, si hay un idioma fiable,
    /// actualiza `sourceLanguage` para que el picker refleje la detección.
    /// Se invoca cuando el usuario eligió `.autoDetect` en el picker o tiene
    /// activo el ajuste `autoDetectLanguage` en Configuración.
    private func updateDetectedLanguage() {
        guard let detected = detectLanguage(for: inputText) else { return }
        guard detected != sourceLanguage else { return }
        sourceLanguage = detected
    }

    /// Detecta el idioma de `text` con `NLLanguageRecognizer` (on-device,
    /// gratis, sin red). Devuelve `nil` si el texto es demasiado corto
    /// (< 4 chars) o si la confianza no supera 0.6.
    private func detectLanguage(for text: String) -> Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }

        languageRecognizer.reset()
        languageRecognizer.processString(trimmed)

        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 1)
        guard let (language, confidence) = hypotheses.first,
              confidence >= 0.6 else { return nil }

        switch language {
        case .english: return .english
        case .spanish: return .spanish
        case .french: return .french
        case .german: return .german
        case .italian: return .italian
        case .portuguese: return .portuguese
        case .russian: return .russian
        case .japanese: return .japanese
        case .korean: return .korean
        case .arabic: return .arabic
        case .simplifiedChinese: return .chineseSimplified
        case .traditionalChinese: return .chineseTraditional
        default: return nil
        }
    }
}

/// Sustituye en el texto las partes "no-traducibles" (bloques de código,
/// código inline y URLs) por placeholders `⟦C0⟧`, `⟦C1⟧`… para que el
/// modelo solo traduzca el lenguaje natural. Tras la traducción, los
/// placeholders se restauran con su contenido original intacto.
///
/// Los brackets `⟦` (U+27E6) y `⟧` (U+27E7) se eligen porque casi no
/// aparecen en texto natural y los modelos de chat tienden a reproducirlos
/// literalmente — además el system prompt ya pide explícitamente que se
/// preserven sin tocar.
enum MarkdownCodePreserver {

    /// Orden importa: el patrón fenced ``` matchea antes que el inline `
    /// para que ``` ... ``` no se rompa en tres ` sueltos.
    private static let patterns: [String] = [
        #"```[\s\S]*?```"#,      // bloques de código fenced (multi-línea)
        #"`[^`\n]+?`"#,          // código inline
        #"https?://[^\s)\]]+"#   // URLs (tutoriales suelen tenerlas)
    ]

    /// Devuelve el texto saneado con placeholders + la lista de fragmentos
    /// originales, en el orden en que se asignaron los índices.
    static func extract(_ text: String) -> (sanitized: String, blocks: [String]) {
        var sanitized = text
        var blocks: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            sanitized = replaceMatches(in: sanitized, regex: regex) { matched in
                blocks.append(matched)
                return "⟦C\(blocks.count - 1)⟧"
            }
        }
        return (sanitized, blocks)
    }

    /// Reemplaza `⟦C0⟧`, `⟦C1⟧`… por el contenido original. Idempotente y
    /// tolerante a placeholders parciales: si el stream aún no completó
    /// el patrón, se queda como está hasta que llegue el carácter de cierre.
    static func restore(_ text: String, with blocks: [String]) -> String {
        guard !blocks.isEmpty else { return text }
        var result = text
        for (i, block) in blocks.enumerated() {
            result = result.replacingOccurrences(of: "⟦C\(i)⟧", with: block)
        }
        return result
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        replacement: (String) -> String
    ) -> String {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastIdx = text.startIndex
        for m in matches {
            guard let range = Range(m.range, in: text) else { continue }
            result += text[lastIdx..<range.lowerBound]
            result += replacement(String(text[range]))
            lastIdx = range.upperBound
        }
        result += text[lastIdx...]
        return result
    }
}
