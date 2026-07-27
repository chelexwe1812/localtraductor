import SwiftUI
import KeyboardShortcuts

/// Pantalla de configuración. Se muestra dentro del mismo popover del
/// traductor (no en una ventana aparte). Recibe `onBack` para volver
/// a la pantalla del traductor.
struct SettingsView: View {
    @Bindable var settings = AppSettings.shared
    let onBack: () -> Void

    /// ViewModel de la app: aquí se usa para la gestión del modelo local
    /// (estado en disco, descarga y borrado).
    @Environment(TranslationViewModel.self) private var viewModel

    /// Controla el diálogo de confirmación antes de eliminar el modelo.
    @State private var showDeleteModelConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                Form {
                    Section("Motor de traducción") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Motor")
                                Text("\"IA local\" usa el modelo LLM descargado: mejor con matices, tonos y textos largos. \"Sistema (Apple)\" usa el traductor de macOS: instantáneo y ligero, pero sin tonos.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !viewModel.isModelDownloaded {
                                    Text("Para usar la traducción con IA es necesario descargar nuevamente el modelo.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            // Menu con Buttons en vez de Picker: los items de un
                            // Picker no se pueden desactivar individualmente, y
                            // "IA local" debe quedar inhabilitado sin modelo.
                            Menu {
                                ForEach(TranslationEngineKind.allCases) { kind in
                                    Button {
                                        settings.translationEngineKind = kind
                                    } label: {
                                        if kind == settings.translationEngineKind {
                                            Label(kind.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(kind.displayName)
                                        }
                                    }
                                    .disabled(kind == .localLLM && !viewModel.isModelDownloaded)
                                }
                            } label: {
                                Text(settings.translationEngineKind.displayName)
                            }
                            .fixedSize()
                        }

                        modelStorageRow
                    }

                    Section("Comportamiento") {
                        Toggle(isOn: $settings.autoTranslate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Traducir automáticamente al escribir")
                                Text("Tras una breve pausa al teclear se traduce solo. Si está desactivado, solo se traduce al pulsar Enter.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $settings.autoCopy) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Copiar la traducción al portapapeles")
                                Text("Al completarse una traducción, se copia automáticamente.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $settings.autoDetectLanguage) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Detectar el idioma automáticamente")
                                Text("Si está activado, la dirección de traducción cambia sola según lo que escribas. Si está desactivado, controlas la dirección manualmente con el botón ⇄.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $settings.clearOnDismiss) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vaciar al cerrar")
                                Text("Cuando se oculta la ventana (cambiando de app o pulsando el atajo), se borra el texto. Al reabrirla puedes escribir algo nuevo al instante.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $settings.translateClipboardOnOpen) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Traducir el portapapeles al abrir")
                                Text("Si tienes texto nuevo copiado, al abrir el popover se pega en la entrada y se traduce al instante.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Apariencia") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Modo de color")
                                Text("Cambia entre tema claro y oscuro. \"Sistema\" sigue la preferencia de macOS.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.colorScheme) {
                                ForEach(ColorSchemePreference.allCases) { pref in
                                    Text(pref.displayName).tag(pref)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Idioma de la app")
                                Text("Idioma de la interfaz de LocalTranslator. No afecta a los idiomas de traducción.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Posición de la barra de herramientas")
                                Text("Coloca los selectores de idioma y los botones de acción arriba o debajo del par entrada/salida.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.toolbarPosition) {
                                ForEach(ToolbarPosition.allCases) { pos in
                                    Text(pos.displayName).tag(pos)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }

                    Section("Atajos globales") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mostrar / ocultar LocalTranslator")
                                Text("Funciona desde cualquier app. Por defecto: ⌥⌘Espacio.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .toggleTranslator)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Traducir el portapapeles")
                                Text("Copia texto en otra app, pulsa este atajo y la traducción aparece al instante. Por defecto: ⇧⌥⌘C.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .translateClipboard)
                        }
                    }

                    Section {
                        Button(action: { NSApp.terminate(nil) }) {
                            Text("Salir de LocalTranslator")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .formStyle(.grouped)
            }
        }
        // El estado en disco puede cambiar fuera de esta pantalla (descarga
        // inicial de bienvenida, borrado manual del contenedor…): lo
        // releemos cada vez que se entra en Configuración.
        .onAppear { viewModel.refreshModelStorageInfo() }
        .confirmationDialog(
            "¿Eliminar el modelo de IA descargado?",
            isPresented: $showDeleteModelConfirmation
        ) {
            Button("Eliminar modelo", role: .destructive) {
                viewModel.deleteLocalModel()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se liberará el espacio que ocupa en disco. Podrás descargarlo de nuevo desde esta misma pantalla cuando lo necesites.")
        }
    }

    // MARK: - Fila de gestión del modelo local

    /// Estado del modelo LLM en disco con su acción correspondiente:
    /// eliminar (si está descargado), progreso (si se está descargando) o
    /// descargar de nuevo (si no está).
    @ViewBuilder
    private var modelStorageRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modelo de IA local")
                if viewModel.isDownloadingModel {
                    ProgressView(value: viewModel.downloadProgress)
                        .frame(maxWidth: 180)
                } else if viewModel.isModelDownloaded {
                    Text("Ocupa \(viewModel.modelSizeOnDisk ?? "—") en disco. Al eliminarlo se libera ese espacio y la traducción con IA queda desactivada hasta descargarlo de nuevo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("El modelo no está descargado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.modelActionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if viewModel.isDownloadingModel {
                Text(viewModel.downloadProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if viewModel.isModelDownloaded {
                Button(role: .destructive) {
                    showDeleteModelConfirmation = true
                } label: {
                    Text("Eliminar…")
                }
            } else {
                Button {
                    viewModel.downloadLocalModel()
                } label: {
                    Text("Descargar")
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Atrás")
                }
                .font(.body)
            }
            .buttonStyle(.borderless)
            .help("Volver al traductor")

            Spacer()

            Text("Configuración")
                .font(.headline)

            Spacer()

            // Hueco invisible para mantener el título centrado.
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Atrás")
            }
            .font(.body)
            .opacity(0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView(onBack: {})
        .environment(TranslationViewModel(engine: MockEngine()))
}
