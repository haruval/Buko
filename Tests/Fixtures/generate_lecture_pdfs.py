"""Rebuild the original, fictional lecture PDFs shipped for the portfolio demo.
These are source documents, not answer strings injected into recognition or RAG.
Run with reportlab installed. Every PDF has two physical, citable pages.
"""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor
from xml.sax.saxutils import escape

DEST = Path(__file__).resolve().parents[2] / "Buko/Resources/Lectures"
COURSES = {
    "programmingLanguages": ("Programming languages", [
        ("04 / Syntax and meaning", [
            ("Lexical analysis and parsing", "Lexical analysis groups characters into tokens such as identifiers, keywords and operators. Parsing checks the token sequence against a grammar and builds a syntax tree. In total = 3 + count, the lexer identifies the names and operators; the parser represents assignment and addition as structured expressions."),
            ("Abstract syntax trees", "An abstract syntax tree represents the essential structure of a program without every punctuation mark or grammar-production detail. An addition node has its operand expressions as children. Parentheses affect the tree's structure but need not remain separate nodes."),
            ("Ambiguous expression grammars", "E -> E + E | E * E | id is ambiguous because a string such as a + b * c has two different parse trees. One groups the addition first; another groups the multiplication first. A grammar that separates additive and multiplicative expressions can encode precedence."),
            ("Precedence and associativity", "Precedence determines which operators bind more tightly: multiplication typically binds more tightly than addition. Associativity resolves grouping among operators of the same precedence. Left-associative subtraction groups a - b - c as (a - b) - c."),
            ("Syntax and semantics", "Syntax specifies the legal form of a program. Semantics specifies what a program means or how it behaves. A syntactically valid expression can still have a type error, and two differently written expressions may have the same meaning."),
        ]),
        ("05 / Scope, types and functions", [
            ("Static scope and lexical binding", "Static scope, also called lexical scope, resolves a name using the program's nested source-code scopes. A use of x refers to the nearest enclosing declaration visible at that source position, regardless of which function called the current function."),
            ("Dynamic scope", "Dynamic scope resolves a name by searching active function calls, starting with the current call and proceeding through its callers. The binding can therefore change with the calling sequence. Under static scope, the relevant enclosing scopes come from source structure instead."),
            ("Closures", "A closure pairs a function with its captured lexical environment. For example, makeAdder(n) returns a function that computes n + x. Calling makeAdder(3) produces an add3 closure that remembers n = 3 even after makeAdder has returned."),
            ("Progress and preservation", "For a suitable typed language, progress states that a well-typed term is a value or can take a computation step. Preservation states that taking a step preserves its type. Together these properties establish type safety: well-typed evaluation does not become stuck in the errors excluded by the type system."),
            ("Capture-avoiding substitution", "Substitution replaces free occurrences of a variable while preserving binding relationships. If a replacement would cause a free variable to become bound, first rename the conflicting bound variable. This renaming is alpha-conversion; it avoids variable capture."),
        ]),
    ]),
    "operatingSystems": ("Operating systems", [
        ("06 / Processes and concurrency", [
            ("Process versus thread", "A process owns an address space and resources such as open files. Threads in one process share that address space and many resources, but each thread has its own program counter, registers and stack. Sharing makes communication efficient but also requires synchronization."),
            ("User mode and kernel mode", "User mode restricts access to privileged instructions and protected memory. Kernel mode lets the operating system manage devices, address spaces and scheduling. A system call enters a controlled kernel entry point, where arguments and permissions can be checked before a service is performed."),
            ("Mode switches and context switches", "A mode switch changes the processor's privilege level and need not change the running thread. A context switch changes the scheduled execution context. The OS saves and restores the program counter, stack pointer and registers, and may change address-space state when switching processes."),
            ("Race conditions", "A race condition occurs when a program's result depends on the timing or interleaving of concurrent operations. Two threads can both read an old counter value and then overwrite each other's increment. Protect the read-modify-write sequence with appropriate synchronization."),
        ]),
        ("07 / Synchronization and memory", [
            ("Mutual exclusion and critical sections", "Mutual exclusion allows only one participating thread at a time to execute a protected critical section. A mutex commonly enforces this rule. The lock must protect all accesses that participate in the shared-state invariant, not merely one writer."),
            ("Mutexes and semaphores", "A mutex protects exclusive ownership of a critical section and is ordinarily unlocked by the thread that acquired it. A semaphore maintains a count of available permits. A counting semaphore can limit access to several identical resources, and signaling can occur from another thread."),
            ("Four deadlock conditions", "Deadlock requires mutual exclusion, hold and wait, no preemption, and circular wait to hold simultaneously. A thread holds a resource while requesting another; resources cannot be forcibly taken away; and the waiting dependencies form a cycle. Preventing any one condition prevents this class of deadlock."),
            ("Page faults", "A page fault traps into the OS when a virtual-memory access cannot be completed using the current mapping. The OS checks whether the access is valid. It may load a missing page, update the page table and restart the instruction; an invalid access instead causes an error. Not every page fault requires disk I/O."),
            ("FIFO, LRU and locality", "FIFO evicts the page that entered memory earliest. LRU evicts the page whose most recent use was longest ago. Temporal locality means recently used data is likely to be used again; spatial locality means nearby addresses are likely to be accessed. Locality helps explain why caching pages can reduce slow memory transfers."),
        ]),
    ]),
    "linearAlgebra": ("Linear algebra", [
        ("08 / Matrix products", [
            ("Dimensions and composition", "If A is m by n and B is n by p, AB is m by p. Entry (i,j) is row i of A dotted with column j of B. When A is 2 by 3 and B is 3 by 2, AB is 2 by 2 while BA is 3 by 3. The shared inner dimension permits composition."),
            ("Worked matrix product", "For C = [2 1; 0 3] and D = [1 4; 2 0], compute each entry by row-column products: 2*1 + 1*2 = 4; 2*4 + 1*0 = 8; 0*1 + 3*2 = 6; 0*4 + 3*0 = 0. Therefore CD = [4 8; 6 0]."),
            ("Order matters", "Matrix multiplication is generally not commutative: AB need not equal BA, and one product may be undefined. Composing transformations in a different order can produce a different transformation. Even when both products exist, their dimensions or entries can differ."),
            ("Another product", "With A = [1 2; 3 4] and B = [2 0; 1 2], the row-column rule gives AB = [4 4; 10 8]. A useful check is to compute the dimensions before calculating entries, then verify one column as A applied to the corresponding column of B."),
        ]),
        ("09 / Systems and subspaces", [
            ("Span", "The span of a collection of vectors is the set of all their linear combinations. Each combination weights the vectors by scalars and adds the results. Two nonparallel vectors in the plane span the plane; two parallel nonzero vectors span only a line."),
            ("Linear independence", "Vectors are linearly independent when the only coefficients producing the zero vector are all zero. A nontrivial combination that equals zero demonstrates dependence. Independence means no vector in the collection can be expressed as a linear combination of the others."),
            ("Elimination example", "For x + 2y = 5 and 3x + 4y = 11, subtract three times the first equation from the second to obtain -2y = -4. Thus y = 2, and substitution in the first equation gives x = 1. These values satisfy both original equations."),
            ("Null space basis", "The null space of A is the set of vectors mapped to zero. For A = [1 2; 2 4], Ax = 0 reduces to x1 + 2x2 = 0. Set x2 = t to obtain x = t[-2; 1]. A basis for the null space is the single vector [-2; 1]."),
            ("Rank-nullity theorem", "For a matrix with n columns, rank(A) + nullity(A) = n. Rank is the dimension of the column space; nullity is the dimension of the null space. For A = [1 2; 2 4], rank is 1 and nullity is 1, summing to the two-dimensional input space."),
        ]),
    ]),
    "biology101": ("Introduction to biology", [
        ("01 / What is life?", [
            ("Characteristics of living systems", "Living systems have cellular organization, use energy, regulate internal conditions, respond to stimuli, grow and develop, and reproduce. Populations evolve across generations. Individual organisms can be alive even when they cannot reproduce; these characteristics describe living systems rather than a rigid checklist for each individual."),
            ("Homeostasis", "Homeostasis is the regulation of internal conditions within a functional range despite changes inside or outside the organism. Negative feedback counteracts a deviation from a regulated condition. Sweating supports temperature regulation because evaporation transfers heat away from the skin, helping cool an overheated body."),
            ("Prokaryotic and eukaryotic cells", "Prokaryotic cells lack a membrane-bound nucleus; their DNA occupies a nucleoid region. Eukaryotic cells have a membrane-bound nucleus and other membrane-bound organelles. Both kinds of cells have a plasma membrane, cytoplasm, genetic material and ribosomes."),
            ("Levels of organization", "An organism is an individual living entity. In multicellular organisms, specialized cells can form tissues, tissues form organs, and organs cooperate in organ systems. A unicellular organism carries out life's functions within one cell and does not have this tissue-organ hierarchy."),
        ]),
        ("02 / Asking biological questions", [
            ("Hypotheses and predictions", "A hypothesis is a testable proposed explanation for an observation. A prediction states an expected observation if the hypothesis and relevant assumptions are correct. A hypothesis about light and plant growth can predict that otherwise comparable plants receiving more light will grow taller."),
            ("Independent and dependent variables", "The independent variable is deliberately changed by the experimenter, such as the amount of light received by a plant. The dependent variable is the measured response, such as plant height or growth. Keep water, soil and plant type comparable to reduce alternative explanations for the result."),
            ("Control groups", "A control group provides a baseline for comparison with the treatment group. Holding other conditions comparable helps isolate the effect of the independent variable. Random assignment and suitable controls reduce systematic differences that could otherwise explain the observed outcome."),
            ("Repeating experiments", "Repeating an experiment helps estimate random variation and reveals whether a result is reproducible. Independent repetitions reduce the influence of a single unusual observation and can reveal anomalies. Repetition alone does not remove a systematic bias; improving controls or methods may also be necessary."),
            ("Observation, inference and evidence", "An observation records information gathered through senses or instruments. An inference interprets observations using reasoning. Evidence can support or challenge a hypothesis, but a single favorable result does not establish universal certainty. Interpret results together with the study's controls and limitations."),
        ]),
    ]),
}

body = ParagraphStyle("body", fontName="Helvetica", fontSize=10.5, leading=15, textColor=HexColor("#283936"))
heading = ParagraphStyle("heading", fontName="Helvetica-Bold", fontSize=12, leading=16, textColor=HexColor("#143D32"))
DEST.mkdir(parents=True, exist_ok=True)
for key, (title, pages) in COURSES.items():
    pdf = canvas.Canvas(str(DEST / f"{key}.pdf"), pagesize=(612, 792), invariant=1)
    pdf.setTitle(f"{title} - Buko sample lecture")
    pdf.setAuthor("Buko / original fictional teaching material")
    for number, (subtitle, sections) in enumerate(pages, 1):
        pdf.setFillColor(HexColor("#143D32")); pdf.rect(0, 760, 612, 32, fill=1, stroke=0)
        pdf.setFillColor(HexColor("#FFFFFF")); pdf.setFont("Helvetica-Bold", 9)
        pdf.drawString(48, 772, "BUKO  /  SAMPLE LECTURE SERIES")
        pdf.setFillColor(HexColor("#143D32")); pdf.setFont("Helvetica-Bold", 25)
        pdf.drawString(48, 715, title)
        pdf.setFont("Helvetica", 12); pdf.drawString(48, 690, subtitle)
        pdf.setStrokeColor(HexColor("#B9CFC3")); pdf.line(48, 672, 564, 672)
        y = 650
        for label, text in sections:
            for content, style in [(label, heading), (text, body)]:
                para = Paragraph(escape(content), style)
                _, height = para.wrap(516, 700)
                y -= height
                assert y >= 90, (key, number, label, y)
                para.drawOn(pdf, 48, y)
                y -= 5
            y -= 13
        pdf.setStrokeColor(HexColor("#B9CFC3")); pdf.line(48, 65, 564, 65)
        pdf.setFillColor(HexColor("#65756B")); pdf.setFont("Helvetica", 8)
        pdf.drawString(48, 48, "Original mock course material for a portfolio demo. Not an institutional handout.")
        pdf.drawRightString(564, 32, f"{number} / {len(pages)}")
        pdf.showPage()
    pdf.save()
    print(DEST / f"{key}.pdf")
