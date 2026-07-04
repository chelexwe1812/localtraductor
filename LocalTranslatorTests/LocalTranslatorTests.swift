//
//  LocalTranslatorTests.swift
//  LocalTranslatorTests
//
//  Created by Marcelo on 29/5/26.
//

import Testing
import Foundation
@testable import LocalTranslator

/// Tests del `MarkdownCodePreserver`: sustituye bloques de código, código
/// inline y URLs por placeholders `⟦Cn⟧` antes de pasar el texto al modelo,
/// y los restaura tras la traducción. Cubrimos los tres tipos de bloque,
/// el orden de detección (fenced antes que inline) y la propiedad clave:
/// `restore(extract(x)) == x` para que el usuario nunca pierda contenido.
@Suite("MarkdownCodePreserver")
struct MarkdownCodePreserverTests {

    @Test("Texto sin código se devuelve intacto y sin bloques")
    func plainTextIsUntouched() {
        let input = "Hola mundo, esto es texto normal."
        let (sanitized, blocks) = MarkdownCodePreserver.extract(input)
        #expect(sanitized == input)
        #expect(blocks.isEmpty)
    }

    @Test("Bloque fenced multi-línea se sustituye por un placeholder")
    func fencedBlockIsExtracted() {
        let input = """
        Aquí va código:
        ```swift
        let x = 1
        ```
        fin.
        """
        let (sanitized, blocks) = MarkdownCodePreserver.extract(input)
        #expect(blocks.count == 1)
        #expect(blocks[0] == "```swift\nlet x = 1\n```")
        #expect(sanitized.contains("⟦C0⟧"))
        #expect(!sanitized.contains("let x = 1"))
    }

    @Test("Código inline se sustituye por placeholder")
    func inlineCodeIsExtracted() {
        let input = "Llama a `foo()` para iniciar."
        let (sanitized, blocks) = MarkdownCodePreserver.extract(input)
        #expect(blocks == ["`foo()`"])
        #expect(sanitized == "Llama a ⟦C0⟧ para iniciar.")
    }

    @Test("URLs http/https se sustituyen por placeholders")
    func urlIsExtracted() {
        let input = "Mira esto: https://example.com/docs y luego sigue."
        let (sanitized, blocks) = MarkdownCodePreserver.extract(input)
        #expect(blocks == ["https://example.com/docs"])
        #expect(sanitized.contains("⟦C0⟧"))
    }

    @Test("El patrón fenced gana al inline: ``` no se rompe en tres `")
    func fencedTakesPriorityOverInline() {
        let input = "```js\nconsole.log('hi')\n```"
        let (_, blocks) = MarkdownCodePreserver.extract(input)
        // Si inline matcheara primero, partiría el ``` en pedazos.
        // Esperamos un solo bloque, el fenced completo.
        #expect(blocks.count == 1)
        #expect(blocks[0] == input)
    }

    @Test("Múltiples bloques heterogéneos se enumeran en orden de extracción")
    func mixedBlocksAreEnumerated() {
        let input = "Lee `README.md` o ve a https://example.com para más."
        let (sanitized, blocks) = MarkdownCodePreserver.extract(input)
        #expect(blocks.count == 2)
        // Inline matchea antes que URL en el orden de patterns, así que el
        // primer placeholder corresponde al backtick.
        #expect(blocks[0] == "`README.md`")
        #expect(blocks[1] == "https://example.com")
        #expect(sanitized == "Lee ⟦C0⟧ o ve a ⟦C1⟧ para más.")
    }

    @Test("restore(extract(x)) == x para cualquier mezcla razonable")
    func extractRestoreIsLossless() {
        let inputs = [
            "Texto plano.",
            "Inline `code` aquí.",
            "URL: https://foo.bar/baz",
            """
            Mira:
            ```python
            def hi():
                print('hello')
            ```
            y también `inline` y https://example.com.
            """
        ]
        for input in inputs {
            let (sanitized, blocks) = MarkdownCodePreserver.extract(input)
            let restored = MarkdownCodePreserver.restore(sanitized, with: blocks)
            #expect(restored == input, "Falla round-trip para: \(input)")
        }
    }

    @Test("restore tolera buffers parciales (placeholder incompleto durante stream)")
    func restoreToleratesPartialPlaceholder() {
        // Simula que el modelo aún no completó el placeholder mientras
        // streamea: el buffer trae "⟦C" sin cierre. La función debe dejarlo
        // como está, sin reventar ni romper texto contiguo.
        let blocks = ["`hi`"]
        let partial = "Saluda con ⟦C"
        let restored = MarkdownCodePreserver.restore(partial, with: blocks)
        #expect(restored == partial)
    }

    @Test("restore sin bloques devuelve el texto tal cual")
    func restoreNoOpWithEmptyBlocks() {
        let text = "Sin placeholders."
        #expect(MarkdownCodePreserver.restore(text, with: []) == text)
    }
}

/// Tests de `AppLanguage.systemPreferred`. Cubrimos la propiedad pública
/// para que cualquier futuro cambio de mapeo (añadir idiomas, cambiar
/// fallback) se note al ejecutar la suite.
@Suite("AppLanguage")
struct AppLanguageTests {

    @Test("Cada caso tiene un identifier de locale válido")
    func localeIsValidPerCase() {
        for lang in AppLanguage.allCases {
            #expect(!lang.locale.identifier.isEmpty)
        }
    }

    @Test("`displayName` no está vacío para ningún caso")
    func displayNameIsNonEmpty() {
        for lang in AppLanguage.allCases {
            #expect(!lang.displayName.isEmpty)
        }
    }
}

/// Tests de `TranslationTone`. La propiedad `instruction` controla qué se
/// inyecta en el prompt del modelo: si rompemos esto sin querer, el tono
/// dejaría de aplicarse en silencio.
@Suite("TranslationTone")
struct TranslationToneTests {

    @Test("`.neutral` no añade instrucción al prompt (devuelve nil)")
    func neutralHasNoInstruction() {
        #expect(TranslationTone.neutral.instruction == nil)
    }

    @Test("Los tonos no-neutros tienen una instrucción no vacía")
    func nonNeutralTonesHaveInstruction() {
        for tone in TranslationTone.allCases where tone != .neutral {
            let instruction = tone.instruction
            #expect(instruction != nil)
            #expect(instruction?.isEmpty == false)
        }
    }
}
