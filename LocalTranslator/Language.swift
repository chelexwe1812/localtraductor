import Foundation

enum Language: String, CaseIterable, Identifiable {
    /// Detección automática del idioma de entrada. Solo válido como
    /// `sourceLanguage`: la UI lo filtra del picker de destino.
    case autoDetect = "auto"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"

    var id: String { rawValue }

    /// Nombre legible para mostrar en la UI (en su propio idioma).
    var displayName: String {
        switch self {
        case .autoDetect: return "Auto Detect"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        }
    }

    /// Nombre del idioma en inglés (para construir prompts consistentes
    /// hacia el modelo, que recibe sus instrucciones en inglés).
    var englishName: String {
        switch self {
        case .autoDetect: return "Auto Detect"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .chineseSimplified: return "Simplified Chinese"
        case .chineseTraditional: return "Traditional Chinese"
        }
    }

    /// Etiqueta legible que combina el nombre en inglés con el nombre en
    /// el idioma propio entre paréntesis. Útil para reconocer idiomas
    /// cuyo nombre nativo está en alfabetos no latinos.
    /// Si ambos coinciden (caso del inglés), se muestra solo uno.
    var displayLabel: String {
        englishName == displayName ? englishName : "\(englishName) (\(displayName))"
    }
}
