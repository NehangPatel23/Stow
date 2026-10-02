import Foundation

enum SyntaxTokenKind: Equatable, Sendable {
    case plain
    case keyword
    case string
    case comment
    case number
}

struct SyntaxRun: Equatable, Sendable {
    var text: String
    var kind: SyntaxTokenKind
}

enum SyntaxHighlighter {
    static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "return", "class", "struct", "enum",
        "import", "def", "function", "const", "for", "while", "switch", "case",
        "public", "private", "async", "await", "true", "false", "nil", "null",
        "fn", "in", "new", "try", "catch", "throw", "package", "select", "from",
    ]

    static func runs(for source: String) -> [SyntaxRun] {
        var runs: [SyntaxRun] = []
        let characters = Array(source)
        var index = 0

        func emit(_ text: String, _ kind: SyntaxTokenKind) {
            guard !text.isEmpty else { return }
            if let last = runs.last, last.kind == kind {
                runs[runs.count - 1].text += text
            } else {
                runs.append(SyntaxRun(text: text, kind: kind))
            }
        }

        while index < characters.count {
            if characters[index] == "/" && index + 1 < characters.count && characters[index + 1] == "/" {
                var end = index
                while end < characters.count && characters[end] != "\n" { end += 1 }
                emit(String(characters[index..<end]), .comment)
                index = end
                continue
            }
            if characters[index] == "/" && index + 1 < characters.count && characters[index + 1] == "*" {
                var end = index + 2
                while end + 1 < characters.count && !(characters[end] == "*" && characters[end + 1] == "/") {
                    end += 1
                }
                end = min(characters.count, end + 2)
                emit(String(characters[index..<end]), .comment)
                index = end
                continue
            }
            if characters[index] == "\"" || characters[index] == "'" {
                let quote = characters[index]
                var end = index + 1
                while end < characters.count {
                    if characters[end] == "\\" && end + 1 < characters.count {
                        end += 2
                        continue
                    }
                    if characters[end] == quote {
                        end += 1
                        break
                    }
                    if characters[end] == "\n" { break }
                    end += 1
                }
                emit(String(characters[index..<end]), .string)
                index = end
                continue
            }
            if characters[index].isNumber {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." {
                    end += 1
                }
                emit(String(characters[index..<end]), .number)
                index = end
                continue
            }
            if characters[index].isLetter || characters[index] == "_" {
                var end = index
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                    end += 1
                }
                let word = String(characters[index..<end])
                emit(word, keywords.contains(word) ? .keyword : .plain)
                index = end
                continue
            }
            emit(String(characters[index]), .plain)
            index += 1
        }
        return runs
    }
}
