import SwiftUI
import AppKit

/// Gestiona la `NSWindow` independiente de la pantalla de bienvenida.
///
/// Es una ventana flotante, centrada y de tamaño fijo. No tiene minimize
/// ni resize: solo el botón de cerrar (rojo). El controlador se mantiene
/// vivo desde el `AppDelegate` para que la ventana no se libere antes de
/// tiempo.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {

    private let window: NSWindow
    private let viewModel: TranslationViewModel
    private let onFinish: () -> Void
    /// Evita que pulsar el botón de cerrar dispare `onFinish` dos veces
    /// si el usuario primero pulsa "Empezar a usar" y la ventana se cierra
    /// programáticamente justo después.
    private var didFinish = false

    init(viewModel: TranslationViewModel,
         onFinish: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onFinish = onFinish

        let size = NSSize(width: 560, height: 640)
        let initialRect = NSRect(origin: .zero, size: size)

        // Ventana con título pero sin minimize/maximize/resize: queremos
        // que sea estable durante la onboarding y no se pueda colapsar.
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "" // ocultamos el título: la vista trae su propia jerarquía
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        self.window = window

        super.init()

        window.delegate = self

        let hosting = NSHostingController(
            rootView: WelcomeRootView(
                viewModel: viewModel,
                onFinish: { [weak self] in
                    self?.finishAndClose()
                }
            )
        )
        window.contentViewController = hosting
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finishAndClose() {
        guard !didFinish else { return }
        didFinish = true
        window.close()
        onFinish()
    }

    // MARK: - NSWindowDelegate

    /// Si el usuario cierra la ventana con el botón rojo antes de terminar,
    /// tratamos ese cierre como "finalizado" para que el AppDelegate libere
    /// el controller y siga con el flujo normal. La carga del modelo, que
    /// ya está en marcha, sigue su curso en background.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !didFinish else { return }
            didFinish = true
            onFinish()
        }
    }
}
