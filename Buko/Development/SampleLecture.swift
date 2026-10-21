import PencilKit

/// UUID-scoped, independently resettable development notes.
enum SampleLecture: String, CaseIterable, Identifiable {
    case programmingLanguages, operatingSystems, linearAlgebra, biology101
    var id: String { rawValue }
    var title: String {
        switch self {
        case .programmingLanguages: "Test PPL Lecture"
        case .operatingSystems: "Test Operating Systems Lecture"
        case .linearAlgebra: "Test Linear Algebra Lecture"
        case .biology101: "Test Biology 101 Lecture"
        }
    }
    var storageKey: String {
        switch self {
        case .programmingLanguages: "pplTestNoteID"
        case .operatingSystems: "osTestNoteID"
        case .linearAlgebra: "linearAlgebraTestNoteID"
        case .biology101: "biology101TestNoteID"
        }
    }
    var resetIdentifier: String {
        switch self {
        case .programmingLanguages: "recreateTestNote"
        case .operatingSystems: "recreateOperatingSystemsNote"
        case .linearAlgebra: "recreateLinearAlgebraNote"
        case .biology101: "recreateBiologyNote"
        }
    }
    var pages: [[String]] {
        switch self {
        case .programmingLanguages: PPLTestNote.pages
        case .operatingSystems: Self.operatingSystemsPages
        case .linearAlgebra: Self.linearAlgebraPages
        case .biology101: Self.biologyPages
        }
    }
    func drawing() -> PKDrawing { LectureHandwriting.drawing(pages: pages) }

    static let operatingSystemsPages: [[String]] = [
        ["OPERATING SYSTEMS", "Lecture 06 - processes and concurrency", "",
         "A process is a running program with its own", "address space and execution state.",
         "Threads within a process share memory.", "Process vs thread:", "", "",
         "User mode vs kernel mode:", "", "",
         "A system call requests a kernel service.", "Why is a mode switch needed?", "", "",
         "Context switch: save and restore CPU state.", "What must the OS save?", "", "",
         "Race condition:", "", ""],
        ["OPERATING SYSTEMS", "Lecture 07 - synchronization and memory", "",
         "A critical section accesses shared state.", "Mutual exclusion:", "", "",
         "Semaphore vs mutex:", "", "",
         "Deadlock: threads wait forever for resources.", "Four necessary conditions for deadlock:", "", "",
         "Virtual memory gives each process an", "independent view of its address space.",
         "Page fault: what happens next?", "", "",
         "FIFO vs LRU page replacement:", "", "Explain why locality matters."],
        ["CONCURRENCY - GAP PRACTICE", "Operating Systems", "",
         "Process: owns an address space and resources.",
         "Thread:", "", "", "",
         "Mutex: protects exclusive ownership of a critical section.",
         "Semaphore:", "", "", "",
         "Process vs thread:", "", "", "",
         "Mutex vs semaphore:", "", "", ""]
    ]
    static let linearAlgebraPages: [[String]] = [
        ["LINEAR ALGEBRA", "Lecture 08 - matrix products", "",
         "An m by n matrix maps n inputs to m outputs.", "AB exists when columns of A = rows of B.",
         "Entry (i,j) is row i of A dot column j of B.", "",
         "Worked example: A = [1 2; 3 4]", "B = [2 0; 1 2]", "AB = [4 4; 10 8]", "",
         "Try: C = [2 1; 0 3], D = [1 4; 2 0]", "CD =", "", "",
         "A is 2 by 3 and B is 3 by 2.", "Dimensions of AB and BA:", "", "",
         "Why is matrix multiplication not commutative?", "", ""],
        ["LINEAR ALGEBRA", "Lecture 09 - linear systems and subspaces", "",
         "A linear combination is a weighted sum", "of vectors: c1 v1 + c2 v2.", "Span:", "", "",
         "Linear independence:", "", "",
         "Solve: x + 2y = 5, 3x + 4y = 11", "Subtract 3 times row 1 from row 2:", "", "",
         "For A = [1 2; 2 4], find its null space.", "Ax = 0 implies x1 + 2x2 = 0.", "A basis for the null space:", "", "",
         "Rank-nullity theorem:", "", ""]
    ]
    static let biologyPages: [[String]] = [
        ["INTRO TO BIOLOGY 101", "Week 1 - what is life?", "",
         "Biology is the scientific study of life.", "Living things are made of one or more cells.",
         "A cell is the smallest unit of life.", "Characteristics shared by living things:", "", "",
         "Organisms use energy and respond to stimuli.", "Homeostasis:", "", "",
         "Example: sweating helps cool the body.", "How does this support homeostasis?", "", "",
         "Prokaryotic vs eukaryotic cells:", "", "",
         "Cell -> tissue -> organ -> organ system", "Organism:", ""],
        ["INTRO TO BIOLOGY 101", "Week 1 - how biologists ask questions", "",
         "An observation is information we gather.", "An inference is an interpretation of it.",
         "A scientific hypothesis must be testable.", "Hypothesis vs prediction:", "", "",
         "Question: does light affect plant growth?", "Prediction: plants with more light grow taller.",
         "Independent variable:", "", "Dependent variable:", "", "",
         "Keep water, soil, and plant type the same.", "Why do we need a control group?", "", "",
         "Why repeat an experiment?", "", "Evidence can support or challenge a hypothesis."],
        ["BIOLOGY - GAP PRACTICE", "Introduction to Biology", "",
         "Independent variable: the light given to a plant.",
         "Dependent variable:", "", "", "", "",
         "Prokaryotic vs eukaryotic cells:", "", "", "", ""]
    ]
}
