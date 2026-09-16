# Changelog

Historial de cambios de LocalTranslator. El formato sigue las ideas de [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [1.1.0] — 2026-09-16

Primera versión que se distribuye como `.dmg`.

### Añadido

- **Abrir al iniciar sesión**: nueva opción en Configuración → Comportamiento. La app arranca con el Mac y queda lista en la barra de menús. Usa `SMAppService`, con la fuente de verdad en el sistema y no en las preferencias de la app: si revocas el permiso en Ajustes del Sistema, el interruptor lo refleja. Si macOS deja el registro pendiente de aprobación, aparece un enlace directo al panel correspondiente.
- **Script de publicación** (`scripts/release.sh`): archiva, empaqueta el `.dmg` y, si hay certificado de distribución, firma y notariza.

### Cambiado

- **Requisito mínimo: macOS 26.0** (antes 26.5). Cubre todo macOS Tahoe en vez de solo las últimas revisiones.
- **Traducciones de mayor fidelidad** con el motor del sistema: se adopta la estrategia `.highFidelity` del framework Translation, que usa los modelos de Apple Intelligence cuando están disponibles, sin descargas de idioma adicionales. En macOS 26.0–26.3, donde esa API no existe, se usa el comportamiento anterior.
- **Nuevo icono en la barra de menús**: glifo ⽂A, recortado a su contenido y con proporción respetada (20×16 pt). El item pasa a longitud variable para no encajonar un glifo más ancho que alto.
- **Nuevo icono de app preparado para Liquid Glass**: el arte plano de una sola capa opaca se separó en capas con alfa real (panel, glifo latino, glifo han) sobre un fondo de degradado. Sin capas con transparencia el material de vidrio no tenía nada que refractar y la variante Liquid Glass se veía como una losa plana.
- **La app ya no parpadea en el Dock al arrancar**: `LSUIElement` pasa al Info.plist en vez de aplicarse en tiempo de ejecución. `launchd` lo lee antes de ejecutar el código de la app, lo que importa justo al iniciar sesión.
- `NSApp.activate(ignoringOtherApps:)` se sustituye por `NSApp.activate()`, que es la API vigente.
- Se declara la categoría de la app (`productivity`).

### Corregido

- **Los pesos del modelo ya no viven en `Library/Caches`**, de donde macOS puede borrarlos sin avisar cuando falta espacio en disco: 2,5 GB que la app presentaba como instalados podían desaparecer y dejar la traducción con IA inservible sin explicación. Ahora están en Application Support y excluidos de las copias de seguridad. Si vienes de una versión anterior, el modelo se traslada solo al arrancar; es un renombrado instantáneo, no una copia.
- **Streaming mucho más ligero**: el texto traducido se refresca como máximo cada 50 ms en lugar de en cada token. Antes, cada token forzaba un redibujado completo del área de salida, una pasada de restauración de placeholders sobre todo el texto acumulado y una animación de scroll nueva.
- **El halo de traducción consume una fracción de lo que consumía**: estaba repintando dos capas difuminadas a la frecuencia del display (120 Hz en pantallas ProMotion) durante toda la traducción; ahora está limitado a 30 fps, sin diferencia visible.
- El flujo de descarga de idiomas del sistema pide los modelos con la misma estrategia con la que después se traduce, evitando que el sistema prepare unos y la sesión pida otros.

## [0.2] — 2026-07-26

### Añadido

- **Motor de traducción "Sistema (Apple)"**: alternativa al modelo de IA basada en el framework Translation de macOS (el mismo traductor de la app Traducir). Instantáneo, ligero y también 100% local. Se elige en Configuración → Motor de traducción.
- **Descarga guiada de idiomas del sistema**: si el par de idiomas elegido no está instalado en macOS, la app abre el diálogo de descarga del sistema y reintenta la traducción al completarse.
- **Gestión del modelo de IA local** en Configuración: muestra el espacio que ocupa en disco (~2.5 GB), permite eliminarlo para liberar espacio (libera también la RAM y cambia automáticamente al motor del sistema) y volver a descargarlo con barra de progreso. Con el modelo eliminado, la opción "IA local" queda desactivada con un aviso.
- **Bienvenida: continuar sin descargar**: opción discreta en el paso de descarga para empezar a usar la app con el traductor del sistema y descargar el modelo más adelante desde Configuración.
- **Icono propio en la barra de menús**: vector monocromo (A / 技) en modo template — se adapta solo a barra clara/oscura y al estado resaltado. Sustituye al símbolo de globo del sistema.
- **Nuevo icono de app**: diseño A / 技 con diagonal azul, integrado en formato Icon Composer con variantes claro, oscuro, transparente y tintado (Liquid Glass).

### Cambiado

- **Detección de idioma más fiable**: se detecta al lanzar la traducción (no mientras se escribe), restringida a los 12 idiomas soportados y sesgada hacia el par activo. Evita que frases a medio escribir salten a idiomas parecidos (español ↔ italiano/portugués).
- El menú de **tono** se oculta cuando el motor activo es el del sistema (los tonos son una capacidad del modelo de IA).
- Si se elige el motor del sistema, el modelo de IA **no se carga en memoria** al arrancar: la app queda lista al instante y no ocupa esos ~2.5 GB de RAM.
- "Cerrar LocalTranslator" pasa a ser **"Salir de LocalTranslator"**, siguiendo la convención de macOS.

### Corregido

- El botón de **copiar ya no se superpone** al texto traducido: el área de salida reserva su columna.
- Revisión completa de textos: opciones "Arriba"/"Abajo" sin traducción al inglés, mensajes de error del motor que salían siempre en español, y una frase ambigua en el ajuste de traducción automática.

## [0.1] — 2026-07-04

Primera versión interna.

- Traductor en la barra de menús para macOS (popover, sin Dock), con atajos globales reasignables: mostrar/ocultar (⌥⌘Espacio) y traducir el portapapeles (⇧⌥⌘C).
- Traducción 100% local con MLX sobre Apple Silicon usando Qwen3-4B Instruct 4-bit (~2.5 GB), con salida en streaming palabra a palabra.
- 12 idiomas con detección automática del idioma de origen (on-device).
- Tonos de traducción: neutro, formal, casual y técnico.
- Preservación de código, markdown y URLs a través de la traducción.
- Onboarding con descarga del modelo y barra de progreso.
- Comodidades opcionales: traducir al escribir, auto-copiar el resultado, traducir el portapapeles al abrir, vaciar al cerrar.
- Interfaz en español e inglés; modo claro/oscuro/sistema; posición de la barra de herramientas configurable.
