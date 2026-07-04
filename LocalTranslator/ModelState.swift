import Foundation

/// Representa en qué fase está el motor de traducción.
/// La UI reacciona a estos estados (mostrar spinner, error, etc.)
enum ModelState: Equatable {
    case idle          // aún no se ha iniciado la carga
    case loading       // cargando el modelo en memoria
    case ready         // listo para traducir
    case failed(String) // algo falló, con mensaje de error
}
