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

    /// `true` si los pesos del modelo LLM están en el caché de disco.
    /// Configuración lo usa para decidir entre "Eliminar" y "Descargar" y
    /// para desactivar la opción "IA local" cuando no hay modelo.
    var isModelDownloaded: Bool = false

    /// Tamaño del modelo en disco ya formateado ("2,5 GB"). `nil` cuando
    /// el modelo no está descargado.
    var modelSizeOnDisk: String?

    /// `true` mientras corre la descarga manual lanzada desde Configuración.
    var isDownloadingModel: Bool = false

    /// Mensaje de error de la última operación de gestión del modelo
    /// (descarga o borrado). `nil` cuando no hay error que mostrar.
    var modelActionError: String?

    // MARK: - Dependencias y tareas internas
    /// Motor LLM local (MLX). Se inyecta para poder usar `MockEngine` en
    /// previews y tests.
    private let llmEngine: TranslationEngine
    /// Motor del sistema (framework Translation de Apple). No requiere
    /// carga pesada, así que se crea siempre.
    private let appleEngine: TranslationEngine
    private let settings: AppSettings
    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: Duration = .milliseconds(450)
    private let languageRecognizer = NLLanguageRecognizer()

    /// `true` cuando el modelo LLM ya está cargado en RAM. Permite volver
    /// al motor de IA sin recargar si ya se cargó en esta sesión.
    private var llmLoaded = false

    /// Ventana del flujo de descarga de idiomas del traductor del sistema.
    /// `nil` cuando no hay descarga en curso.
    private var languageDownloadWindow: LanguageDownloadWindowController?

    /// Motor que atiende la traducción según la preferencia del usuario.
    private var activeEngine: TranslationEngine {
        settings.translationEngineKind == .appleTranslation ? appleEngine : llmEngine
    }

    /// Último contenido del portapapeles que esta sesión ya "consumió". Sirve
    /// para que el auto-pegado al abrir no repita el mismo texto cada vez.
    private var lastSeenClipboard: String?

    // MARK: - Init
    /// Recibe el motor de traducción y la fuente de preferencias.
    /// `settings` cae en `AppSettings.shared` dentro del cuerpo (y no como
    /// valor por defecto del parámetro) porque los argumentos por defecto se
    /// evalúan en contexto no aislado y `shared` está aislado al main actor.
    init(engine: TranslationEngine, settings: AppSettings? = nil) {
        self.llmEngine = engine
        self.appleEngine = AppleTranslationEngine()
        self.settings = settings ?? .shared
        refreshModelStorageInfo()
    }

    // MARK: - Carga del modelo
    func loadModel() async {
        // El traductor del sistema no necesita carga: listo al instante.
        // El LLM se cargará más tarde solo si el usuario cambia de motor.
        guard settings.translationEngineKind == .localLLM else {
            modelState = .ready
            return
        }
        modelState = .loading
        downloadProgress = 0
        do {
            try await llmEngine.loadModel { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress
                }
            }
            llmLoaded = true
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
        // La carga puede haber implicado la descarga inicial de los pesos:
        // refrescamos el estado en disco para Configuración.
        refreshModelStorageInfo()
    }

    // MARK: - Gestión del modelo en disco (Configuración)

    /// Relee del disco si el modelo está descargado y cuánto ocupa.
    func refreshModelStorageInfo() {
        isModelDownloaded = ModelStorage.isDownloaded
        modelSizeOnDisk = isModelDownloaded
            ? ModelStorage.sizeOnDisk().map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            }
            : nil
    }

    /// Elimina los pesos del modelo del disco y lo descarga de la RAM.
    /// Si el motor activo era el LLM, cambia automáticamente al traductor
    /// del sistema para que la app siga funcionando.
    func deleteLocalModel() {
        modelActionError = nil
        translationTask?.cancel()
        isTranslating = false

        do {
            try ModelStorage.deleteModel()
        } catch {
            modelActionError = String(
                localized: "No se pudo eliminar el modelo: \(error.localizedDescription)",
                locale: settings.appLanguage.locale
            )
        }

        // Liberamos también la copia en RAM: sin esto, borrar solo ahorraría
        // disco pero el modelo seguiría ocupando ~2.5 GB de memoria.
        Task { [llmEngine] in
            await llmEngine.unload()
        }
        llmLoaded = false
        refreshModelStorageInfo()

        if settings.translationEngineKind == .localLLM {
            // El onChange de ContentView invoca engineKindDidChange(),
            // que dejará modelState en .ready para el motor del sistema.
            settings.translationEngineKind = .appleTranslation
        }
    }

    /// Descarga (y carga) de nuevo el modelo desde Configuración. Al
    /// terminar, la opción "IA local" vuelve a estar disponible.
    func downloadLocalModel() {
        guard !isDownloadingModel else { return }
        modelActionError = nil
        isDownloadingModel = true
        downloadProgress = 0

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.llmEngine.loadModel { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress
                    }
                }
                self.llmLoaded = true
                if self.settings.translationEngineKind == .localLLM {
                    self.modelState = .ready
                }
            } catch {
                self.modelActionError = String(
                    localized: "No se pudo descargar el modelo: \(error.localizedDescription)",
                    locale: self.settings.appLanguage.locale
                )
            }
            self.isDownloadingModel = false
            self.refreshModelStorageInfo()
        }
    }

    /// Reacciona al cambio de motor en Configuración. Al pasar al traductor
    /// del sistema no hay nada que cargar; al volver al LLM, se carga solo
    /// si no se cargó antes en esta sesión (si ya está en RAM, es gratis).
    func engineKindDidChange() {
        translationTask?.cancel()
        isTranslating = false
        switch settings.translationEngineKind {
        case .appleTranslation:
            modelState = .ready
        case .localLLM:
            if llmLoaded {
                modelState = .ready
            } else {
                Task { [weak self] in
                    await self?.loadModel()
                }
            }
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

        // La detección ocurre aquí, al lanzar la traducción, y no mientras
        // se escribe: con frases a medias el detector confundía idiomas
        // cercanos (español ↔ italiano/portugués) y el picker saltaba de
        // idioma a mitad de escritura. Sobre el texto completo la detección
        // es mucho más fiable.
        if sourceLanguage == .autoDetect || settings.autoDetectLanguage {
            if let detected = detectLanguage(for: textSnapshot) {
                sourceLanguage = detected
            } else if sourceLanguage == .autoDetect {
                // Sin idioma concreto en el picker no podemos continuar.
                // Prependemos el emoji a mano (no entra en el catálogo) para
                // evitar colisiones de símbolos auto-generados con otras
                // entradas que solo se diferenciaban por el prefijo.
                outputText = "⚠️ " + String(
                    localized: "No se pudo detectar el idioma de origen.",
                    locale: settings.appLanguage.locale
                )
                return
            }
            // Si la detección no es concluyente pero el picker ya tiene un
            // idioma concreto, seguimos con ese sin molestar al usuario.
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
                let stream = try await self.activeEngine.translate(
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
            } catch EngineError.languagesNotInstalled(let source, let target) {
                // El traductor del sistema soporta el par pero falta
                // descargarlo: abrimos el flujo de descarga y reintentamos
                // al completarse.
                self.requestLanguageDownload(source: source, target: target)
            } catch {
                self.outputText = "⚠️ " + String(
                    localized: "Error: \(error.localizedDescription)",
                    locale: self.settings.appLanguage.locale
                )
            }
            self.isTranslating = false
        }
    }

    // MARK: - Descarga de idiomas del traductor del sistema

    /// Abre la ventana que pide al sistema descargar el par de idiomas y,
    /// si la descarga termina bien, relanza la traducción pendiente.
    private func requestLanguageDownload(source: Language, target: Language) {
        guard languageDownloadWindow == nil else { return }
        let controller = LanguageDownloadWindowController()
        languageDownloadWindow = controller
        controller.show(source: source, target: target) { [weak self] success in
            guard let self else { return }
            self.languageDownloadWindow = nil
            if success {
                self.translate()
            } else {
                self.outputText = "⚠️ " + String(
                    localized: "No se descargaron los idiomas de traducción.",
                    locale: self.settings.appLanguage.locale
                )
            }
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
    /// Solo se invoca cuando el usuario elige `.autoDetect` en el picker con
    /// texto ya escrito; mientras se teclea NO se detecta (ver `translate()`).
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
        // Restringimos las hipótesis a los idiomas que la app soporta y
        // sesgamos hacia el par que ya está en los pickers: con frases
        // cortas el reconocedor confundía español con italiano/portugués,
        // y lo más probable es que el usuario siga con su par habitual.
        languageRecognizer.languageConstraints = Self.supportedNLLanguages
        var hints: [NLLanguage: Double] = [:]
        if let source = sourceLanguage.nlLanguage { hints[source] = 0.4 }
        if let target = targetLanguage.nlLanguage { hints[target] = 0.2 }
        languageRecognizer.languageHints = hints
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

    /// Lista de idiomas que el detector puede proponer: exactamente los que
    /// la app soporta. Sin esta restricción el reconocedor puede sugerir
    /// idiomas fuera del catálogo (catalán, gallego…) que luego se descartan.
    private static let supportedNLLanguages: [NLLanguage] =
        Language.allCases.compactMap(\.nlLanguage)
}

/// Mapeo inverso al de `detectLanguage`: del enum propio de la app al tipo
/// de NaturalLanguage, para configurar constraints y hints del detector.
private extension Language {
    var nlLanguage: NLLanguage? {
        switch self {
        case .autoDetect: return nil
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
        case .chineseSimplified: return .simplifiedChinese
        case .chineseTraditional: return .traditionalChinese
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
