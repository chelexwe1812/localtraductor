import Foundation
import Observation
import SwiftUI
import AppKit

/// Idioma de la interfaz de la app (independiente de los idiomas de
/// traducción). Por ahora solo español e inglés.
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish
    case english

    var id: String { rawValue }

    /// Nombre del idioma en su propia lengua, como es habitual en pickers
    /// de idioma para que cada usuario lo reconozca.
    var displayName: String {
        switch self {
        case .spanish: return "Español"
        case .english: return "English"
        }
    }

    /// `Locale` que aplicamos al entorno SwiftUI para que `Text("…")` busque
    /// las traducciones del idioma elegido en `Localizable.xcstrings`.
    var locale: Locale {
        switch self {
        case .spanish: return Locale(identifier: "es")
        case .english: return Locale(identifier: "en")
        }
    }

    /// Primer idioma soportado dentro de `Locale.preferredLanguages`. Si el
    /// sistema está configurado en algo que no tenemos traducido (japonés,
    /// francés…), caemos a inglés como mínimo común denominador. Se usa solo
    /// en el primer arranque, antes de que el usuario elija algo en
    /// Configuración.
    static var systemPreferred: AppLanguage {
        for code in Locale.preferredLanguages {
            let prefix = code.lowercased().prefix(2)
            if prefix == "es" { return .spanish }
            if prefix == "en" { return .english }
        }
        return .english
    }
}

/// Nombre legible del tono para mostrar en el menú. Vive aquí (capa SwiftUI)
/// para mantener `TranslationTone` libre de dependencias de UI.
extension TranslationTone {
    var displayName: LocalizedStringKey {
        switch self {
        case .neutral: return "Neutro"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .technical: return "Técnico"
        }
    }
}

/// Posición de la barra de herramientas en la pantalla del traductor.
/// `top` la coloca encima del input; `bottom` debajo del output.
enum ToolbarPosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    /// `LocalizedStringKey` para que `Text(...)` busque la traducción en el
    /// catálogo en vez de tratar el valor como literal.
    var displayName: LocalizedStringKey {
        switch self {
        case .top: return "Arriba"
        case .bottom: return "Abajo"
        }
    }
}

/// Preferencia del usuario para el modo de color de la UI.
enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Devolvemos `LocalizedStringKey` (no `String`) para que `Text(...)`
    /// realice la búsqueda en el catálogo de strings; con un `String` plano
    /// SwiftUI lo trataría como texto literal y nunca lo traduciría.
    var displayName: LocalizedStringKey {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    /// Devuelve un `ColorScheme` concreto siempre.
    ///
    /// Para `.system` resolvemos la apariencia activa de macOS en el momento
    /// de la consulta: si dejáramos `nil`, SwiftUI no tendría un valor al que
    /// reaccionar y los textos que ya cachearon su color (p. ej. el NSTextView
    /// que envuelve `TextEditor`) se quedarían con la apariencia anterior
    /// hasta cerrar/reabrir el popover.
    @MainActor
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            let matched = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return matched == .darkAqua ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Preferencias persistentes de la app.
///
/// Se expone como singleton `shared` para que UI y ViewModel observen la
/// misma instancia. Cada cambio se guarda automáticamente en
/// `UserDefaults`, así que las preferencias sobreviven a relanzamientos.
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    /// Traduce automáticamente con un pequeño debounce mientras escribes.
    /// Cuando es `false`, solo se traduce al pulsar Enter.
    var autoTranslate: Bool {
        didSet { UserDefaults.standard.set(autoTranslate, forKey: Keys.autoTranslate) }
    }

    /// Copia la traducción al portapapeles automáticamente al completarse.
    var autoCopy: Bool {
        didSet { UserDefaults.standard.set(autoCopy, forKey: Keys.autoCopy) }
    }

    /// Detecta el idioma del texto de entrada con `NLLanguageRecognizer`
    /// y actualiza la dirección de traducción sobre la marcha.
    var autoDetectLanguage: Bool {
        didSet { UserDefaults.standard.set(autoDetectLanguage, forKey: Keys.autoDetectLanguage) }
    }

    /// Vaciar entrada y salida cada vez que se oculta el popover, para
    /// poder escribir algo nuevo nada más reabrirlo sin tener que borrar.
    var clearOnDismiss: Bool {
        didSet { UserDefaults.standard.set(clearOnDismiss, forKey: Keys.clearOnDismiss) }
    }

    /// Al abrir el popover, si el portapapeles contiene texto distinto al
    /// de la última vez que lo vimos, se pega en la entrada y se lanza la
    /// traducción al instante.
    var translateClipboardOnOpen: Bool {
        didSet { UserDefaults.standard.set(translateClipboardOnOpen, forKey: Keys.translateClipboardOnOpen) }
    }

    /// Modo de color: sigue el sistema, fuerza claro o fuerza oscuro.
    var colorScheme: ColorSchemePreference {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    /// Idioma de la interfaz de la app (no confundir con los idiomas de
    /// traducción origen/destino).
    var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }

    /// Tono / registro con el que el modelo debe devolver la traducción.
    /// El `TranslationViewModel` lee este valor en cada llamada al motor.
    var translationTone: TranslationTone {
        didSet { UserDefaults.standard.set(translationTone.rawValue, forKey: Keys.translationTone) }
    }

    /// Posición de la barra de herramientas: arriba o debajo del par
    /// entrada/salida.
    var toolbarPosition: ToolbarPosition {
        didSet { UserDefaults.standard.set(toolbarPosition.rawValue, forKey: Keys.toolbarPosition) }
    }

    /// Indica si la pantalla de bienvenida ya se mostró en algún arranque
    /// previo. La primera vez que el usuario abre la app se queda en `false`
    /// para que vea la intro y la descarga del modelo; después se queda en
    /// `true` y la app arranca directamente al traductor.
    var hasShownWelcome: Bool {
        didSet { UserDefaults.standard.set(hasShownWelcome, forKey: Keys.hasShownWelcome) }
    }

    private init() {
        let d = UserDefaults.standard
        // .bool(forKey:) devuelve false si no existe → defaults seguros.
        self.autoTranslate = d.bool(forKey: Keys.autoTranslate)
        self.autoCopy = d.bool(forKey: Keys.autoCopy)
        self.autoDetectLanguage = Self.bool(d, key: Keys.autoDetectLanguage, default: true)
        self.clearOnDismiss = Self.bool(d, key: Keys.clearOnDismiss, default: true)
        self.translateClipboardOnOpen = Self.bool(d, key: Keys.translateClipboardOnOpen, default: true)
        if let raw = d.string(forKey: Keys.colorScheme),
           let pref = ColorSchemePreference(rawValue: raw) {
            self.colorScheme = pref
        } else {
            self.colorScheme = .system
        }
        if let raw = d.string(forKey: Keys.appLanguage),
           let lang = AppLanguage(rawValue: raw) {
            self.appLanguage = lang
        } else {
            self.appLanguage = .systemPreferred
        }
        if let raw = d.string(forKey: Keys.translationTone),
           let tone = TranslationTone(rawValue: raw) {
            self.translationTone = tone
        } else {
            self.translationTone = .neutral
        }
        if let raw = d.string(forKey: Keys.toolbarPosition),
           let pos = ToolbarPosition(rawValue: raw) {
            self.toolbarPosition = pos
        } else {
            self.toolbarPosition = .top
        }
        self.hasShownWelcome = d.bool(forKey: Keys.hasShownWelcome)
    }

    /// Lee un `Bool` aplicando un default explícito cuando la clave nunca se
    /// guardó. `UserDefaults.bool(forKey:)` devuelve `false` para claves
    /// inexistentes, lo que mezcla "el usuario lo desactivó" con "nunca lo
    /// tocó". Aquí distinguimos los dos casos con `object(forKey:) == nil`.
    private static func bool(_ defaults: UserDefaults, key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    private enum Keys {
        static let autoTranslate = "autoTranslate"
        static let autoCopy = "autoCopy"
        static let autoDetectLanguage = "autoDetectLanguage"
        static let clearOnDismiss = "clearOnDismiss"
        static let translateClipboardOnOpen = "translateClipboardOnOpen"
        static let colorScheme = "colorScheme"
        static let appLanguage = "appLanguage"
        static let translationTone = "translationTone"
        static let toolbarPosition = "toolbarPosition"
        static let hasShownWelcome = "hasShownWelcome"
    }
}
