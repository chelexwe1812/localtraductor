import SwiftUI
import AppKit

/// Gestiona el icono en la barra de menús superior y el popover
/// que aparece anclado a él, con la UI del traductor dentro.
///
/// Comportamiento:
/// - **Click izquierdo** (o atajo global) → muestra/oculta el popover.
/// - **Click derecho** (o ⌃+click) → menú contextual con "Configuración" y "Cerrar app".
/// - Click fuera del popover → se cierra solo (`NSPopover.behavior = .transient`).
/// - Cuando el popover se cierra, se notifica via `onPopoverDidClose`.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let onPopoverDidClose: () -> Void
    private let onPopoverWillShow: () -> Void
    private let onOpenSettings: () -> Void

    /// Monitor global de clics. `addGlobalMonitorForEvents` solo recibe
    /// eventos que van a OTRAS apps, así que un click fuera del popover lo
    /// dispara siempre, incluso cuando el `behavior = .transient` se queda
    /// "atontado" tras abrir un `Menu`/`Picker` de SwiftUI (es el caso del
    /// menú de tonos: tras seleccionar una opción, el popover dejaba de
    /// cerrarse al pinchar en otra ventana).
    private var globalClickMonitor: Any?

    init<RootView: View>(
        rootView: RootView,
        onPopoverDidClose: @escaping () -> Void = {},
        onPopoverWillShow: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.onPopoverDidClose = onPopoverDidClose
        self.onPopoverWillShow = onPopoverWillShow
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        popover = NSPopover()
        // Compacto y de altura fija para que los dos cuadros (input/output)
        // de 120 pt sean siempre iguales y el popover no crezca.
        popover.contentSize = NSSize(width: 460, height: 400)
        popover.behavior = .transient  // auto-dismiss al perder foco
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: rootView)

        super.init()

        popover.delegate = self

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "globe",
                accessibilityDescription: "LocalTranslator"
            )
            button.target = self
            button.action = #selector(handleClick(_:))
            // Por defecto el botón solo dispara con click izquierdo.
            // Habilitamos también click derecho para el menú contextual.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // `NSPopover.behavior = .transient` debería cerrar el popover al
        // perder foco, pero deja de detectarlo de forma fiable después de
        // que se haya abierto un Menu/Picker dentro. Como red de seguridad,
        // cerramos manualmente cuando la app pasa a background.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // Aplicamos la preferencia de tema y nos suscribimos a cambios para
        // que tanto la chrome del popover (flecha, marco) como su contenido
        // SwiftUI sigan la elección del usuario incluso en caliente.
        applyColorSchemeFromSettings()
        observeColorScheme()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc private func handleAppResignActive(_ notification: Notification) {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    /// Llamado por el icono O por el atajo global.
    func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    /// Muestra el popover sin importar su estado actual.
    func show() {
        guard let button = statusItem.button else { return }
        // Avisamos antes de mostrar para que el ViewModel pueda preparar el
        // estado (p.ej. auto-pegar el portapapeles si procede).
        onPopoverWillShow()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Pasamos foco a la ventana del popover para que reciba teclas.
        popover.contentViewController?.view.window?.makeKey()
        startGlobalClickMonitor()
    }

    // MARK: - Monitor de clics fuera de la app

    private func startGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // El monitor global solo recibe eventos de otras apps, así que
            // cualquier click aquí es por definición fuera del popover.
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func stopGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick =
            event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            showContextMenu()
        } else {
            toggle()
        }
    }

    // MARK: - Menú contextual

    private func showContextMenu() {
        let menu = NSMenu()
        // El menú de NSMenu vive fuera de SwiftUI: el `\.locale` del
        // environment no se aplica aquí, así que traducimos manualmente
        // con el locale del idioma elegido por el usuario.
        let locale = AppSettings.shared.appLanguage.locale

        let configItem = NSMenuItem(
            // Mismo key que el título de la pantalla; el "…" tras el texto
            // lo añadimos manualmente para no duplicar entradas en el catálogo
            // (que generaba colisión de símbolos auto-generados).
            title: String(localized: "Configuración", locale: locale) + "…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Cerrar LocalTranslator", locale: locale),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Lo mostramos anclado al botón del status item.
        if let button = statusItem.button {
            let location = NSPoint(x: 0, y: button.bounds.height + 4)
            menu.popUp(positioning: nil, at: location, in: button)
        }
    }

    @objc private func openSettings() {
        // Cambiamos el screen del ViewModel a `.settings` y mostramos el popover.
        // No abrimos una ventana aparte — todo vive en el mismo popover.
        onOpenSettings()
        show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            stopGlobalClickMonitor()
            onPopoverDidClose()
        }
    }

    nonisolated func popoverDidShow(_ notification: Notification) {
        MainActor.assumeIsolated {
            tintPopoverFrame()
        }
    }

    // MARK: - Tinte de la flecha / chrome del popover
    /// Pinta la vista de marco del popover con la misma tinta blanca sutil
    /// que el SwiftUI aplicaba al panel de entrada. Así la flecha que
    /// conecta el popover con el icono del menubar se ve del mismo color
    /// que la sección del input que tiene justo debajo.
    ///
    /// Acceder a `view.superview` de un NSPopover es una técnica frágil que
    /// depende de la jerarquía interna de AppKit; si Apple cambia esa
    /// jerarquía en una futura macOS, este tinte simplemente no se aplicará
    /// (la app seguirá funcionando, solo perderá el detalle visual).
    @MainActor
    private func tintPopoverFrame() {
        guard let frameView = popover.contentViewController?.view.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    }

    // MARK: - Apariencia (modo claro / oscuro / sistema)
    @MainActor
    private func applyColorSchemeFromSettings() {
        let appearance: NSAppearance?
        switch AppSettings.shared.colorScheme {
        case .system:
            // Resolvemos la apariencia del sistema en este instante y la
            // aplicamos explícitamente. Si dejáramos `nil`, NSPopover seguiría
            // al sistema pero SwiftUI no recibiría ninguna notificación de
            // cambio, así que los textos cacheados (NSTextView dentro de
            // `TextEditor`) se quedarían con los colores anteriores hasta
            // cerrar y reabrir el popover.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        popover.appearance = appearance
    }

    /// Observa cambios en `AppSettings.shared.colorScheme` mediante el
    /// framework `Observation`. Como `withObservationTracking` solo dispara
    /// una vez, nos re-registramos tras cada cambio.
    @MainActor
    private func observeColorScheme() {
        withObservationTracking {
            _ = AppSettings.shared.colorScheme
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyColorSchemeFromSettings()
                self.observeColorScheme()
            }
        }
    }
}
