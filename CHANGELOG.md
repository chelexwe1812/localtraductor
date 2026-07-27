# Changelog

Historial de cambios de LocalTranslator. El formato sigue las ideas de [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [0.2] — 2026-07-26

> **En verificación** — versión aún no publicada; seguimos comprobando que todo funcione bien.

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
