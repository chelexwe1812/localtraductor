import SwiftUI
import AppKit
import Translation

/// Ventana auxiliar que gestiona la descarga de paquetes de idioma del
/// traductor del sistema (framework Translation).
///
/// ¿Por qué una ventana propia y no el popover? El framework solo permite
/// pedir descargas desde una sesión creada por el modificador
/// `.translationTask` de una vista, y usa la ventana de esa vista para
/// presentar el diálogo de permiso y el progreso. El popover del traductor
/// es `.transient`: se cierra en cuanto pierde el foco (cosa que el propio
/// diálogo provocaría) y usar una sesión cuya vista desapareció termina en
/// `fatalError`. Una ventana flotante estable evita todo eso.
@MainActor
final class LanguageDownloadWindowController {

    private var window: NSWindow?
    private var onFinish: ((Bool) -> Void)?

    /// Muestra la ventana y arranca el flujo de descarga para el par dado.
    /// `completion` se llama exactamente una vez: `true` si los idiomas
    /// quedaron instalados, `false` si el usuario canceló o algo falló.
    func show(source: Language, target: Language, completion: @escaping (Bool) -> Void) {
        guard window == nil,
              let sourceLanguage = source.localeLanguage,
              let targetLanguage = target.localeLanguage else {
            completion(false)
            return
        }
        onFinish = completion

        let view = LanguageDownloadView(
            configuration: TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            ),
            sourceName: source.englishName,
            targetName: target.englishName,
            onFinish: { [weak self] success in
                self?.finish(success)
            }
        )
        .environment(\.locale, AppSettings.shared.appLanguage.locale)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(_ success: Bool) {
        window?.close()
        window = nil
        let completion = onFinish
        onFinish = nil
        completion?(success)
    }
}

/// Contenido de la ventana de descarga. El trabajo real lo hace el
/// modificador `.translationTask`: al aparecer la vista, el framework pide
/// permiso al usuario, muestra su propio progreso de descarga y
/// `prepareTranslation()` regresa cuando los idiomas quedan instalados.
private struct LanguageDownloadView: View {
    let configuration: TranslationSession.Configuration
    let sourceName: String
    let targetName: String
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Descargando idiomas de traducción…")
                .font(.headline)
            Text("\(sourceName) → \(targetName)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("macOS pedirá confirmación la primera vez. La descarga se hace una sola vez por idioma.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 340)
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                onFinish(true)
            } catch {
                onFinish(false)
            }
        }
    }
}
