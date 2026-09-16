import Foundation
import OSLog

/// Utilidades para localizar, inspeccionar y eliminar la copia en disco del
/// modelo LLM.
///
/// El paquete swift-huggingface guarda los modelos en el caché estándar de
/// Hugging Face, que en apps sandboxed resuelve a
/// `Library/Caches/huggingface/hub` dentro del contenedor. Eso **no** nos
/// sirve: macOS se reserva el derecho a vaciar `Library/Caches` bajo presión
/// de disco, y aquí hay 2,5 GB que la app presenta al usuario como
/// instalados. Si el sistema los purgara, la traducción con IA dejaría de
/// funcionar sin ninguna explicación.
///
/// Por eso fijamos explícitamente la raíz del caché a Application Support
/// (ver ``hubCacheDirectory``) y se la pasamos al `HubClient` que usa
/// `MLXEngine`. La carpeta queda excluida de las copias de seguridad: son
/// pesos re-descargables, no datos del usuario.
///
/// `nonisolated` porque solo expone funciones puras sobre el sistema de
/// archivos y el actor `MLXEngine` necesita leerlas sin saltar al main actor
/// (la isolación por defecto del proyecto).
nonisolated enum ModelStorage {

    private static let log = Logger(subsystem: "LocalTranslator", category: "ModelStorage")

    /// ID del modelo que usa la app. Única fuente de verdad: `MLXEngine`
    /// lo toma como valor por defecto de su init.
    static let modelID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    /// Raíz del caché de Hugging Face que usa la app. Es el directorio que
    /// contiene directamente las carpetas `models--org--nombre`, o sea el
    /// equivalente de `~/.cache/huggingface/hub`.
    static var hubCacheDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("LocalTranslator")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
    }

    /// Ubicación que usaban las versiones anteriores (el default de
    /// swift-huggingface en sandbox). Solo se consulta para migrar.
    private static var legacyHubCacheDirectory: URL {
        URL.cachesDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
    }

    /// Nombre de carpeta del repo dentro del caché, con el patrón que usa
    /// Hugging Face: `models--{org}--{nombre}`.
    private static var repoFolderName: String {
        "models--" + modelID.replacingOccurrences(of: "/", with: "--")
    }

    /// Carpeta donde viven los pesos del modelo.
    static var modelDirectory: URL {
        hubCacheDirectory.appendingPathComponent(repoFolderName)
    }

    // MARK: - Preparación y migración

    /// Deja el almacenamiento listo antes de que nadie consulte el estado del
    /// modelo: crea la carpeta, la excluye de las copias de seguridad y sube
    /// el modelo de la ubicación antigua si viene de una versión previa.
    ///
    /// Debe llamarse una vez al arrancar, **antes** de construir el
    /// `TranslationViewModel` (su init ya pregunta si el modelo está
    /// descargado). Es idempotente y barato: el traslado es un `rename`
    /// dentro del mismo contenedor, no una copia de 2,5 GB.
    static func prepare() {
        do {
            try FileManager.default.createDirectory(
                at: hubCacheDirectory,
                withIntermediateDirectories: true
            )
            try excludeFromBackup(hubCacheDirectory)
            try migrateFromLegacyLocation()
        } catch {
            // No es fatal: si algo falla, el peor caso es que el modelo se
            // vuelva a descargar. Lo dejamos en el log y seguimos.
            log.error("No se pudo preparar el almacenamiento del modelo: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mueve el modelo desde `Library/Caches` a la ubicación nueva.
    ///
    /// Solo actúa cuando hay algo que mover y el destino aún no existe. Si el
    /// destino ya está, dejamos la copia antigua donde está: borrarla sería
    /// destruir datos que no acabamos de verificar, y al vivir en Caches el
    /// propio sistema la reclamará cuando necesite el espacio.
    private static func migrateFromLegacyLocation() throws {
        let legacy = legacyHubCacheDirectory.appendingPathComponent(repoFolderName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path) else { return }
        guard !fm.fileExists(atPath: modelDirectory.path) else {
            log.notice("Modelo ya presente en Application Support; se ignora la copia heredada en Caches")
            return
        }
        try fm.moveItem(at: legacy, to: modelDirectory)
        log.notice("Modelo migrado de Library/Caches a Application Support")
    }

    /// Marca la carpeta para que Time Machine e iCloud no la copien: son
    /// pesos re-descargables, no vale la pena meter 2,5 GB en cada backup.
    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    // MARK: - Consulta

    /// `true` si los pesos están completos en disco. No basta con que la
    /// carpeta exista (una descarga interrumpida deja solo configs): exigimos
    /// al menos un archivo `.safetensors`, que es donde están los pesos.
    static var isDownloaded: Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        ) else { return false }
        for case let url as URL in enumerator where url.pathExtension == "safetensors" {
            return true
        }
        return false
    }

    /// Tamaño total en bytes de la carpeta del modelo, o `nil` si no existe.
    /// Suma los archivos reales (resuelve el tamaño del archivo en disco),
    /// suficiente para mostrar "ocupa X GB" en Configuración.
    static func sizeOnDisk() -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: modelDirectory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return nil }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    /// Elimina la carpeta del modelo. Si no existe, no hace nada (no es un
    /// error: el objetivo — que no ocupe espacio — ya se cumple).
    ///
    /// Barre también la ubicación heredada: cuando el usuario pulsa
    /// "Eliminar" espera recuperar el espacio, y dejar una copia olvidada en
    /// Caches incumpliría esa promesa aunque el sistema acabe purgándola.
    static func deleteModel() throws {
        let fm = FileManager.default
        let legacy = legacyHubCacheDirectory.appendingPathComponent(repoFolderName)
        if fm.fileExists(atPath: legacy.path) {
            try? fm.removeItem(at: legacy)
        }
        guard fm.fileExists(atPath: modelDirectory.path) else { return }
        try fm.removeItem(at: modelDirectory)
    }
}
