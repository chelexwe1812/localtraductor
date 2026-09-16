import Foundation
import ServiceManagement
import AppKit

/// Registro de LocalTranslator como ítem de inicio de sesión.
///
/// Envuelve `SMAppService.mainApp` (macOS 13+), que es la API moderna que
/// sustituye a `SMLoginItemSetEnabled`. A diferencia del resto de
/// preferencias, aquí **la fuente de verdad es el sistema, no
/// `UserDefaults`**: el usuario puede revocar el permiso desde Ajustes del
/// Sistema › General › Ítems de inicio sin pasar por la app, así que
/// siempre consultamos `status` en vez de recordar lo último que elegimos.
@MainActor
enum LaunchAtLogin {

    /// Estado real del registro en `launchd`.
    ///
    /// `.requiresApproval` significa que el registro se hizo pero el usuario
    /// lo tiene desactivado en Ajustes del Sistema: no arrancará solo, por
    /// lo que lo tratamos como "desactivado" de cara al toggle.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` cuando el registro existe pero está pendiente de que el
    /// usuario lo autorice en Ajustes del Sistema. La UI lo usa para
    /// explicar por qué el interruptor no se quedó activado.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Activa o desactiva el arranque automático.
    ///
    /// Los casos "ya estaba en ese estado" se ignoran en silencio porque
    /// `register()` devuelve `kSMErrorAlreadyRegistered` y `unregister()`
    /// devuelve `kSMErrorJobNotFound`; ninguno es un fallo real.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    /// Abre el panel de Ajustes del Sistema donde el usuario puede aprobar
    /// el ítem de inicio cuando el registro quedó en `.requiresApproval`.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
