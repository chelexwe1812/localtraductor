import Foundation

/// Utilidades para inspeccionar y eliminar la copia en disco del modelo LLM.
///
/// El paquete swift-huggingface guarda los modelos en el caché estándar de
/// Hugging Face. En apps sandboxed (nuestro caso) eso se traduce a
/// `Library/Caches/huggingface/hub` dentro del contenedor de la app, con una
/// carpeta por modelo cuyo nombre sigue el patrón `models--{org}--{nombre}`.
/// Borrar esa carpeta es seguro: la próxima carga simplemente vuelve a
/// descargar los pesos desde Hugging Face.
enum ModelStorage {

    /// ID del modelo que usa la app. Única fuente de verdad: `MLXEngine`
    /// lo toma como valor por defecto de su init.
    static let modelID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    /// Carpeta del caché de Hugging Face donde viven los pesos del modelo.
    static var modelDirectory: URL {
        URL.cachesDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
            .appendingPathComponent("models--" + modelID.replacingOccurrences(of: "/", with: "--"))
    }

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
    static func deleteModel() throws {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else { return }
        try FileManager.default.removeItem(at: modelDirectory)
    }
}
