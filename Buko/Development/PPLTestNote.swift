import PencilKit

/// Deterministic single-line hand-lettering made of editable pen strokes.
/// This text is ONLY the fixture authoring source; inference never reads it.
enum PPLTestNote {
    static let pages: [[String]] = [
        ["PRINCIPLES OF PROGRAMMING LANGUAGES", "Lecture 04 - syntax and meaning", "",
         "A language is more than its syntax.", "Syntax = form. Semantics = meaning.", "",
         "Lexical Analysis vs Parsing:", "", "",
         "Tokens: identifiers, keywords, operators.", "Example: total = 3 + count;", "Lexer -> tokens -> parser -> syntax tree", "",
         "Abstract syntax tree (AST):", "", "",
         "Ambiguous grammar: one string, two parse trees.", "Why is E -> E + E | E * E | id ambiguous?", "",
         "Precedence vs associativity:", "", "Review the expression grammar before Friday."],
        ["LECTURE 05 - SCOPE, TYPES, AND FUNCTIONS", "Principles of Programming Languages", "",
         "Static scope:", "", "",
         "Dynamic scope follows the calling sequence.", "A binding connects a name to an entity.", "",
         "A closure stores a function and its", "lexical environment, even after return.", "",
         "Example of a closure:", "", "",
         "Type safety prevents invalid operations.", "Static type checking happens before execution.", "",
         "Progress + preservation imply:", "", "Exam in 12 days - review lambda calculus.", "TODO: finish the substitution example."],
        ["SCOPE - GAP PRACTICE", "Principles of Programming Languages", "",
         "Static scoping: follows lexical nesting in source code.",
         "Dynamic scoping:", "", "", "", "",
         "Lexical analysis: groups characters into tokens.",
         "Parsing:", "", "", "", "",
         "Lexical analysis vs parsing:", "", "", ""],
        ["SCOPE - REVERSED GAP", "Principles of Programming Languages", "",
         "Dynamic scoping: searches the active calling sequence.",
         "Static scoping:", "", "", "", ""]
    ]

    static func drawing() -> PKDrawing { LectureHandwriting.drawing(pages: pages) }
}
