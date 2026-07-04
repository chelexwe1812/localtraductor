// AppKit aporta NSEvent.ModifierFlags (.option, .command, .shift) usados
// en las combinaciones por defecto de los atajos.
import AppKit
import KeyboardShortcuts

/// Nombre del atajo global para mostrar/ocultar LocalTranslator.
///
/// `KeyboardShortcuts` persiste automáticamente la asignación del atajo
/// en `UserDefaults` bajo esta clave ("toggleTranslator"). Si el usuario
/// no ha personalizado nada, se usa el `initial` indicado.
extension KeyboardShortcuts.Name {
    static let toggleTranslator = Self(
        "toggleTranslator",
        initial: .init(.space, modifiers: [.option, .command])
    )

    /// Atajo para traducir el contenido actual del portapapeles.
    /// Por defecto ⇧⌥⌘C.
    static let translateClipboard = Self(
        "translateClipboard",
        initial: .init(.c, modifiers: [.shift, .option, .command])
    )
}
