import SwiftUI
import KeyboardShortcuts

/// Pantalla de configuración. Se muestra dentro del mismo popover del
/// traductor (no en una ventana aparte). Recibe `onBack` para volver
/// a la pantalla del traductor.
struct SettingsView: View {
    @Bindable var settings = AppSettings.shared
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                Form {
                    Section("Comportamiento") {
                        Toggle(isOn: $settings.autoTranslate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Traducir automáticamente al escribir")
                                Text("Tras una breve pausa al teclear se traduce solo. Si está desactivado, se traduce solo al pulsar Enter.")
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
                            Text("Cerrar LocalTranslator")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .formStyle(.grouped)
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
}
