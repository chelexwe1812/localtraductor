import AppKit
import KeyboardShortcuts

/// Nombre del atajo global para mostrar/ocultar LocalTranslator.
///
/// `KeyboardShortcuts` persiste automáticamente la asignación del atajo
/// en `UserDefaults` bajo esta clave ("toggleTranslator"). Si el usuario
/// no ha personalizado nada, se usa el `default` indicado.
extension KeyboardShortcuts.Name {
    static let toggleTranslator = Self(
        "toggleTranslator",
        default: .init(.space, modifiers: [.option, .command])
    )

    /// Atajo para traducir el contenido actual del portapapeles.
    /// Por defecto ⇧⌥⌘C.
    static let translateClipboard = Self(
        "translateClipboard",
        default: .init(.c, modifiers: [.shift, .option, .command])
    )
}
