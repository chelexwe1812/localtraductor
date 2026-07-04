import SwiftUI
import AppKit
import KeyboardShortcuts

@main
struct LocalTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI exige declarar al menos una Scene. Toda la UI vive en
        // el popover gestionado por `StatusBarController`, así que aquí
        // dejamos una scene Settings "stub" por si el usuario pulsa ⌘,
        // por reflejo — le indicamos dónde está realmente la configuración.
        Settings {
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("La configuración está dentro del popover.")
                    .font(.callout)
                Text("Abre LocalTranslator desde el icono de la barra de menús o con ⌥⌘Espacio, y pulsa el engranaje.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(width: 360)
            .environment(\.locale, AppSettings.shared.appLanguage.locale)
        }
    }
}

// MARK: - AppDelegate

/// Mantiene la app viva (no hay scenes principales), monta el icono de
/// la barra de menús con su popover y conecta el atajo global.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var viewModel: TranslationViewModel?
    private var statusBar: StatusBarController?
    /// Controlador de la ventana de bienvenida. `nil` cuando ya se cerró
    /// o cuando no se debía mostrar. Lo retenemos aquí para que la ventana
    /// no se libere antes de tiempo.
    private var welcomeWindow: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // ViewModel a nivel de app: el modelo MLX permanece cargado
            // en RAM entre apariciones/ocultamientos del popover.
            let vm = TranslationViewModel(engine: MLXEngine())
            self.viewModel = vm

            // Icono en la barra de menús + popover anclado con ContentView dentro.
            statusBar = StatusBarController(
                rootView: ContentView().environment(vm),
                onPopoverDidClose: { [weak vm] in
                    guard let vm else { return }
                    // Al cerrarse el popover, siempre volvemos a la pantalla
                    // del traductor (para que la próxima apertura no empiece
                    // en Configuración).
                    vm.resetToTranslator()
                    // Y si el usuario activó "Vaciar al cerrar", limpiamos textos.
                    if AppSettings.shared.clearOnDismiss {
                        vm.clearInput()
                    }
                },
                onPopoverWillShow: { [weak vm] in
                    // Si el portapapeles trae texto nuevo, lo pega y traduce.
                    vm?.translateClipboardOnOpenIfNeeded()
                    // Devolvemos el foco al input para que el atajo global
                    // permita teclear sin hacer click primero.
                    vm?.requestInputFocus()
                },
                onOpenSettings: { [weak vm] in
                    vm?.screen = .settings
                }
            )

            // Atajo global (por defecto ⌥⌘Espacio, reasignable en Configuración)
            KeyboardShortcuts.onKeyDown(for: .toggleTranslator) { [weak self] in
                self?.statusBar?.toggle()
            }

            // Atajo para traducir el contenido del portapapeles (⇧⌥⌘C por defecto).
            KeyboardShortcuts.onKeyDown(for: .translateClipboard) { [weak self] in
                Task { @MainActor in
                    self?.translateClipboard()
                }
            }

            // La pantalla de bienvenida solo aparece en el primer arranque
            // (mientras `hasShownWelcome == false`). Después se va directo
            // al traductor cargando el modelo en background.
            if !AppSettings.shared.hasShownWelcome {
                showWelcomeWindow(viewModel: vm)
            } else {
                await vm.loadModel()
            }
        }
    }

    @MainActor
    private func showWelcomeWindow(viewModel: TranslationViewModel) {
        let controller = WelcomeWindowController(
            viewModel: viewModel,
            onFinish: { [weak self, weak viewModel] in
                AppSettings.shared.hasShownWelcome = true
                self?.welcomeWindow = nil

                // Al terminar la bienvenida abrimos el popover del traductor
                // para que el usuario pueda empezar a traducir al instante,
                // y disparamos el halo Siri de bienvenida (dura ~1 s).
                self?.statusBar?.show()
                viewModel?.celebrateFirstOpen()
            }
        )
        welcomeWindow = controller
        controller.show()
    }

    @MainActor
    private func translateClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        viewModel?.inputText = text
        statusBar?.show()
        viewModel?.translate()
    }
}
