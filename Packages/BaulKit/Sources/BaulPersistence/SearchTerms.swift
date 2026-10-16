import GRDB

/// Convierte lo que escribe el usuario en condiciones SQL.
///
/// Cada palabra debe aparecer en algún campo (Y entre palabras, O entre campos).
/// Las palabras de 3 o más letras usan el índice FTS5 de trigramas; las más
/// cortas no se pueden indexar con trigramas y caen a `LIKE`.
struct SearchTerms: Equatable {
    let terms: [String]

    init(_ text: String) {
        terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { terms.isEmpty }

    /// Condición para filas de `clip` (debe estar en el FROM como `clip`).
    func clipCondition() -> SQL {
        conjunction { term in clipMatch(term) }
    }

    /// Condición para un JOIN `boardEntry` + `clip`: cada palabra puede estar
    /// en el elemento original o en el título/texto editado de la entrada.
    func entryCondition() -> SQL {
        conjunction { term in
            "(\(clipMatch(term)) OR \(entryMatch(term)))"
        }
    }

    private func conjunction(_ condition: (String) -> SQL) -> SQL {
        guard let first = terms.first else { return "1" }
        return terms.dropFirst().reduce(condition(first)) { "\($0) AND \(condition($1))" }
    }

    private func clipMatch(_ term: String) -> SQL {
        if term.count >= 3 {
            return "clip.id IN (SELECT rowid FROM clipFTS WHERE clipFTS MATCH \(Self.phrase(term)))"
        }
        let like = Self.likePattern(term)
        return """
            (clip.text LIKE \(like) ESCAPE '\\' \
            OR clip.linkTitle LIKE \(like) ESCAPE '\\' \
            OR clip.sourceAppName LIKE \(like) ESCAPE '\\')
            """
    }

    private func entryMatch(_ term: String) -> SQL {
        if term.count >= 3 {
            return "boardEntry.id IN (SELECT rowid FROM boardEntryFTS WHERE boardEntryFTS MATCH \(Self.phrase(term)))"
        }
        let like = Self.likePattern(term)
        return """
            (boardEntry.customTitle LIKE \(like) ESCAPE '\\' \
            OR boardEntry.customText LIKE \(like) ESCAPE '\\')
            """
    }

    /// Frase FTS5 literal: las comillas internas se duplican, así no se interpreta como sintaxis.
    static func phrase(_ term: String) -> String {
        "\"" + term.replacing("\"", with: "\"\"") + "\""
    }

    static func likePattern(_ term: String) -> String {
        let escaped = term
            .replacing("\\", with: "\\\\")
            .replacing("%", with: "\\%")
            .replacing("_", with: "\\_")
        return "%\(escaped)%"
    }
}
