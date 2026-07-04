import SwiftUI

/// Vista raíz de la pantalla de bienvenida. Vive dentro de una `NSWindow`
/// independiente y centrada gestionada por `WelcomeWindowController`.
///
/// Se compone de tres pasos:
/// - `.intro`: explica brevemente qué es la app y la característica de tonos.
/// - `.confirm`: resume el modelo y pide confirmación antes de descargar.
/// - `.downloading`: muestra una barra de progreso mientras se descarga el
///   modelo. Cuando termina aparece el botón "Empezar a usar".
struct WelcomeRootView: View {

    let viewModel: TranslationViewModel
    let onFinish: () -> Void

    @State private var step: Step = .intro

    /// Coreografía de la transición al completarse la descarga: el icono
    /// de descarga se encoge, se sustituye por el check verde con un "pop"
    /// y en paralelo la explosión de burbujas verdes celebra el evento.
    @State private var showCheck: Bool = false
    @State private var iconScale: CGFloat = 1.0
    @State private var completionTask: Task<Void, Never>?

    private let settings = AppSettings.shared

    enum Step: Hashable {
        case intro
        case confirm
        case downloading
    }

    /// Progreso real de la descarga reportado por el `TranslationViewModel`.
    private var progress: Double {
        viewModel.downloadProgress
    }

    /// `true` cuando la descarga ha terminado y el botón "Empezar a usar"
    /// debe aparecer.
    private var isReady: Bool {
        viewModel.modelState == .ready
    }

    var body: some View {
        ZStack {
            switch step {
            case .intro:
                introPane
                    .transition(.opacity)
            case .confirm:
                confirmPane
                    .transition(.opacity)
            case .downloading:
                downloadingPane
                    .transition(.opacity)
            }
        }
        .frame(width: 560, height: 640)
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .background(backgroundLayer)
        .preferredColorScheme(settings.colorScheme.colorScheme)
        // En primer arranque, `appLanguage` arranca desde `systemPreferred`:
        // español si la Mac está en español, inglés en cualquier otro idioma.
        // Reusamos el mismo locale que el resto de la app para que la
        // onboarding mantenga coherencia con lo que el usuario verá después.
        .environment(\.locale, settings.appLanguage.locale)
    }

    /// Fondo de la ventana: capa base + gradiente sutil hacia azul oscuro
    /// en la parte inferior para dar profundidad.
    private var backgroundLayer: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0/255, green: 80/255, blue: 200/255).opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    /// Degradado azul vibrante para el icono del globo (#00A3FF → #007AFF).
    private var globeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0x00/255.0, green: 0xA3/255.0, blue: 0xFF/255.0),
                Color(red: 0x00/255.0, green: 0x7A/255.0, blue: 0xFF/255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Pantalla 1: Intro

    private var introPane: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            // Globo grande con degradado azul vibrante y halo de brillo
            // sutil para sensación premium.
            Image(systemName: "globe")
                .font(.system(size: 84, weight: .light))
                .foregroundStyle(globeGradient)
                .shadow(
                    color: Color(red: 0/255, green: 0xA3/255, blue: 0xFF/255).opacity(0.45),
                    radius: 18, x: 0, y: 0
                )

            VStack(spacing: 6) {
                Text("LocalTranslator")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .multilineTextAlignment(.center)

                Text("Tu traductor privado impulsado por IA en tu Mac")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                Text("Traduce al instante con inteligencia artificial que nunca abandona tu dispositivo. **Máxima privacidad. Cero datos en la nube.**")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.85))

                Text("Y lo mejor: **dale exactamente el tono que necesitas**. Formal para emails importantes, casual para conversaciones reales, o técnico para documentación y código.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .font(.callout)
            .padding(.horizontal, 4)

            // Tres iconos resumiendo los pilares: privacidad, velocidad, tonos.
            HStack(spacing: 28) {
                benefitIcon(systemName: "lock.shield.fill", label: "Privacidad")
                benefitIcon(systemName: "bolt.fill", label: "Velocidad")
                benefitIcon(systemName: "slider.horizontal.3", label: "Tonos")
            }
            .padding(.top, 2)

            // Badge "100% Local · Sin internet"
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("100% Local · Sin internet")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.14), in: Capsule())

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    step = .confirm
                }
            } label: {
                Text("Siguiente")
                    .fontWeight(.semibold)
                    .frame(minWidth: 200)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Icono pequeño con etiqueta debajo. Sirve como destacado visual de
    /// cada uno de los tres pilares de la app en la pantalla de intro.
    private func benefitIcon(systemName: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pantalla intermedia: Confirmación

    /// Resume claramente qué modelo se va a usar y qué pasará antes de
    /// disparar la descarga. Da un botón de cancelar para volver atrás. Así
    /// el usuario nunca cae en la pantalla de descarga por sorpresa.
    private var confirmPane: some View {
        VStack(spacing: 16) {
            // Header fijo arriba: icono, título y badge con el modelo.
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(globeGradient)
                    .shadow(
                        color: Color(red: 0/255, green: 0xA3/255, blue: 0xFF/255).opacity(0.35),
                        radius: 12, x: 0, y: 0
                    )

                Text("¿Listo para instalar LocalTranslator?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Modelo: Qwen3-4B (2.5 GB)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
            }

            // El cuerpo va dentro de un ScrollView para que aunque crezca
            // el contenido (idiomas, descripciones), los botones de acción
            // siempre estén accesibles abajo sin recortar la ventana.
            ScrollView {
                VStack(spacing: 14) {
                    whyCard

                    benefitsCard

                    Text("Podrás empezar a traducir en cuanto termine la descarga.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)

            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .downloading
                    }
                    startDownload()
                } label: {
                    Text("Descargar Qwen3-4B")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .intro
                    }
                } label: {
                    Text("Cancelar")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
            // Limitamos el ancho del grupo de botones para que no se
            // estiren a todo el alto del padding: con esto los dos quedan
            // exactamente del mismo tamaño, ajustados al texto principal.
            .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tarjeta con la explicación de por qué elegimos este modelo concreto.
    /// Borde sutil + tinte de acento para distinguirla de la lista de
    /// beneficios y que el usuario perciba la sección como diferenciada.
    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("¿Por qué elegimos Qwen3-4B?")
                    .font(.headline)
            }

            whyBullet(
                title: "Ligero pero potente",
                detail: "Con 4 mil millones de parámetros y cuantizado a 2.5 GB, ofrece un excelente equilibrio entre velocidad y calidad de traducción."
            )
            whyBullet(
                title: "Excelente en multilingüe",
                detail: "Soporta 12 idiomas: inglés, español, francés, alemán, italiano, portugués, ruso, japonés, coreano, árabe y chino (simplificado y tradicional)."
            )
            whyBullet(
                title: "Diseñado para uso local",
                detail: "Su arquitectura permite inferencia rápida en Macs con Apple Silicon, manteniendo alta calidad sin conexión a internet."
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    /// Lista de beneficios concretos de la descarga: una sola vez,
    /// localmente, privado, y tiempo estimado.
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            confirmBullet(systemName: "1.circle.fill",
                          title: "Una sola vez",
                          subtitle: "Solo se descarga una vez")
            confirmBullet(systemName: "internaldrive.fill",
                          title: "Se guardará localmente",
                          subtitle: "Todo queda en tu dispositivo")
            confirmBullet(systemName: "lock.shield.fill",
                          title: "Privacidad total",
                          subtitle: "Ningún dato sale de tu Mac")
            confirmBullet(systemName: "clock.fill",
                          title: "Tiempo estimado",
                          subtitle: "3 a 8 minutos (depende de tu conexión)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Bullet de la tarjeta "¿Por qué Qwen3-4B?": título en bold y un
    /// detalle más largo debajo, en color secundario.
    private func whyBullet(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bullet de la lista de beneficios: icono SF Symbol en círculo + título
    /// y un subtítulo más sutil debajo explicando el detalle.
    private func confirmBullet(systemName: String,
                               title: LocalizedStringKey,
                               subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Pantalla 2: Descarga

    private var downloadingPane: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            // Icono central. Durante la descarga se ve quieto. Al terminar,
            // se encoge brevemente, reaparece como check verde con un "pop"
            // y al mismo tiempo lanzamos la explosión de burbujas verdes.
            ZStack {
                CelebrationBurst(isActive: showCheck)

                Image(systemName: showCheck ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(showCheck ? Color.green : Color.accentColor)
                    .scaleEffect(iconScale)
            }
            .frame(width: 200, height: 200)
            .onChange(of: isReady) { _, newValue in
                guard newValue else { return }
                runCompletionTransition()
            }

            Text(isReady ? "¡Listo!" : "Descargando Qwen3-4B")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            VStack(spacing: 8) {
                Text(isReady
                     ? "Qwen3-4B ya está en tu Mac. Ya puedes empezar a traducir."
                     : "Estamos descargando **Qwen3-4B** directamente en tu Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.85))

                Text("Así podrás traducir sin internet y con total privacidad.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Text("Este proceso solo se hace una vez. ¡Gracias por tu paciencia!")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 4)

            // Bloque de progreso: porcentaje XL en negrita y debajo la
            // barra lineal. Sin tiempo estimado: prefiero no enseñar una
            // cifra que puede ser engañosa hasta tener más muestras.
            VStack(spacing: 10) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: progress))

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)

            Button {
                onFinish()
            } label: {
                Text("Empezar a usar")
                    .fontWeight(.semibold)
                    .frame(minWidth: 200)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!isReady)
            .opacity(isReady ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.2), value: isReady)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Coreografía de finalización

    /// Cambia el icono de descarga por el check verde con un pop, y en
    /// paralelo dispara la explosión de burbujas verdes. La sustitución no
    /// usa `contentTransition(.symbolEffect(.replace))` porque preferimos
    /// controlar manualmente la escala para que se sincronice con el burst.
    private func runCompletionTransition() {
        completionTask?.cancel()

        // Reset por si volviéramos a entrar (p. ej. al re-mostrar la welcome).
        showCheck = false
        iconScale = 1.0

        completionTask = Task { @MainActor in
            // 1) El icono de descarga se encoge.
            withAnimation(.easeIn(duration: 0.18)) {
                iconScale = 0
            }

            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }

            // 2) Conmutamos a check verde y lanzamos el burst (CelebrationBurst
            //    se activa con `isActive: showCheck`). Pop con spring marcado.
            showCheck = true
            iconScale = 0
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                iconScale = 1.08
            }

            try? await Task.sleep(for: .milliseconds(140))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                iconScale = 1.0
            }
        }
    }


    // MARK: - Lógica

    /// Lanza la descarga real en background. El ViewModel ya gestiona
    /// `modelState` y `downloadProgress`, que esta vista observa.
    private func startDownload() {
        iconScale = 1.0
        Task { await viewModel.loadModel() }
    }
}

#Preview("Intro") {
    WelcomeRootView(
        viewModel: TranslationViewModel(engine: MockEngine()),
        onFinish: {}
    )
}
// MARK: - CelebrationBurst

/// Explosión de burbujitas verdes que se proyectan radialmente desde el
/// centro al activar `isActive`. Se dispara una sola vez por instancia de
/// la vista. La paleta se mantiene dentro de la gama del verde (igual que
/// el check de "listo") para que la celebración se sienta como una emanación
/// del propio icono y no como un confeti aleatorio.
private struct CelebrationBurst: View {
    let isActive: Bool

    @State private var bubbles: [Bubble] = []
    @State private var progress: CGFloat = 0
    @State private var hasFired: Bool = false

    /// Paleta de verdes: distintos tonos para que las burbujas no parezcan
    /// idénticas pero todas sigan "siendo" el verde del check.
    private let palette: [Color] = [
        .green,
        .mint,
        Color(red: 0.12, green: 0.72, blue: 0.38),
        Color(red: 0.20, green: 0.85, blue: 0.45),
        Color(red: 0.45, green: 0.95, blue: 0.55),
        Color(red: 0.10, green: 0.60, blue: 0.32)
    ]

    var body: some View {
        ZStack {
            ForEach(bubbles) { bubble in
                Circle()
                    .fill(bubble.color)
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(
                        x: cos(bubble.angle) * bubble.distance * progress,
                        y: sin(bubble.angle) * bubble.distance * progress
                    )
                    .opacity(Double(1.0 - progress))
                    .scaleEffect(1.0 - progress * 0.4)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, newValue in
            guard newValue, !hasFired else { return }
            hasFired = true
            fire()
        }
    }

    private func fire() {
        let count = 18
        bubbles = (0..<count).map { i in
            // Ángulos repartidos uniformemente alrededor del círculo más un
            // pequeño jitter para evitar un patrón demasiado simétrico.
            let baseAngle = Double(i) / Double(count) * 2 * .pi
            let jitter = Double.random(in: -0.2...0.2)
            return Bubble(
                angle: baseAngle + jitter,
                distance: CGFloat.random(in: 55...92),
                size: CGFloat.random(in: 7...13),
                color: palette.randomElement() ?? .green
            )
        }
        progress = 0
        withAnimation(.easeOut(duration: 0.95)) {
            progress = 1
        }
    }

    private struct Bubble: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let color: Color
    }
}

