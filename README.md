# LocalTranslator

Traductor privado para macOS que vive en la barra de menús. Corre un modelo de lenguaje **100% local** sobre Apple Silicon: tu texto nunca sale de tu Mac.

## Características

- **Privacidad total** — La inferencia ocurre en tu Mac con [MLX](https://github.com/ml-explore/mlx-swift). Sin nube, sin cuentas, sin telemetría. Tras la descarga inicial del modelo funciona sin internet.
- **Dos motores de traducción** — El modelo de IA local (matices, tonos, textos largos) o el traductor del sistema de macOS (framework Translation: instantáneo y ligero, también offline). Se cambia en Configuración; el modelo de IA se puede eliminar para liberar los ~2.5 GB y re-descargar cuando quieras.
- **12 idiomas** — Inglés, español, francés, alemán, italiano, portugués, ruso, japonés, coreano, árabe y chino (simplificado y tradicional), con detección automática del idioma de origen (on-device, con `NLLanguageRecognizer`).
- **Tonos de traducción** — Neutro, formal, casual o técnico: el registro de la salida se ajusta con un clic.
- **Streaming** — La traducción aparece palabra a palabra según la genera el modelo.
- **Preserva código y URLs** — Los bloques de código (fenced e inline), la estructura markdown y los enlaces pasan intactos a través de la traducción.
- **Atajos globales** — Funciona desde cualquier app:
  - `⌥⌘Espacio` — mostrar / ocultar el traductor.
  - `⇧⌥⌘C` — traducir el contenido del portapapeles al instante.
  - Ambos reasignables en Configuración.
- **Comodidades opcionales** — Traducción automática al escribir (con debounce), copiar el resultado al portapapeles, pegar y traducir el portapapeles al abrir, vaciar al cerrar.
- **Interfaz en español e inglés**, modo claro / oscuro / sistema.

## El modelo

La primera vez que abres la app, una pantalla de bienvenida descarga **Qwen3-4B Instruct cuantizado a 4-bit** (`mlx-community/Qwen3-4B-Instruct-2507-4bit`, ~2.5 GB) desde Hugging Face y lo guarda en el contenedor local de la app. Las siguientes aperturas cargan directo desde disco.

## Requisitos

- Mac con **Apple Silicon** (la inferencia usa Metal vía MLX).
- **macOS 26** o posterior.
- Para compilar: **Xcode 26** o posterior.

## Compilar y ejecutar

1. Clona el repositorio y abre `LocalTranslator.xcodeproj` en Xcode.
2. Espera a que se resuelvan los paquetes Swift (mlx-swift-lm, swift-transformers, KeyboardShortcuts…). Xcode pedirá aprobar el plugin de compilación de `mlx-swift` y las macros de `mlx-swift-lm` la primera vez: acepta con *Trust & Enable*.
3. Compila y ejecuta (`⌘R`). La app aparece como un icono A/技 en la barra de menús; no tiene ventana principal ni icono en el Dock.

Los tests unitarios (framework Swift Testing) se corren con `⌘U`.

## Arquitectura

```
LocalTranslator/
├── LocalTranslatorApp.swift      Punto de entrada; AppDelegate monta la barra de menús y los atajos
├── StatusBarController.swift     Icono en la barra de menús + popover (AppKit)
├── ContentView.swift             UI del traductor (SwiftUI): entrada, salida en streaming, barra de acciones
├── SettingsView.swift            Configuración, dentro del mismo popover
├── WelcomeView.swift             Onboarding con descarga del modelo y barra de progreso
├── WelcomeWindowController.swift Ventana independiente de la bienvenida
├── TranslationViewModel.swift    Estado observable + orquestación (debounce, detección de idioma,
│                                 preservación de código/markdown vía MarkdownCodePreserver)
├── TranslationEngine.swift       Protocolo del motor + tonos de traducción
├── MLXEngine.swift               Motor real: actor que corre Qwen3-4B con MLX
├── MockEngine.swift              Motor simulado para previews de SwiftUI
├── AppSettings.swift             Preferencias persistentes (UserDefaults, @Observable)
├── Language.swift                Idiomas soportados
├── ModelState.swift              Estados del ciclo de vida del modelo
└── GlobalShortcut.swift          Definición de los atajos globales (KeyboardShortcuts)
```

La UI habla con el motor solo a través del protocolo `TranslationEngine`, así que el modelo real (`MLXEngine`) y el simulado (`MockEngine`) son intercambiables.

## Privacidad

LocalTranslator no tiene analytics ni hace peticiones de red, con una única excepción: la descarga inicial del modelo desde Hugging Face. Todo lo que traduces se procesa y se queda en tu Mac.

## Historial de cambios

Versión actual: **0.2** (en verificación, aún sin publicar). El detalle de cada versión está en el [CHANGELOG](CHANGELOG.md).
