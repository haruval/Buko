import Foundation

@main struct MatrixProductChecks {
    static func main() {
        let product = MatrixProductCheck.evaluate("C = [2 1; 0 3], D = [1 4; 2 0]. CD =")!
        precondition(product.lines.last == "CD = [4 8; 6 0].")
        precondition(product.lines.first!.contains("(2 * 4) + (1 * 0) = 8"))
        let rectangular = MatrixProductCheck.evaluate("A = [1 -2 3; 0 1 2]. B = [2; 3; -1]. AB =")!
        precondition(rectangular.lines.last == "AB = [-7; 1].")
        precondition(MatrixProductCheck.evaluate("A = [1 2 3]. B = [1 2]. AB =")!.clarification.contains("confirm"))
        precondition(MatrixProductCheck.evaluate("A = [1 ?; 3 4]. B = [1 0; 0 1]. AB =") == nil)
        precondition(MatrixProductCheck.evaluate("A = [1 2; 3]. B = [1 0; 0 1]. AB =") == nil)
        precondition(MatrixProductCheck.evaluate("A = [1]. A = [2]. B = [3]. AB =") == nil)
        precondition(MatrixProductCheck.evaluate("A = [1]. B = [3]. AB = [3]") == nil)
        precondition(MatrixProductCheck.evaluate("What is a matrix product?") == nil)
        precondition(MatrixProductCheck.evaluate("A = [0.5 -2]. B = [4; 1]. AB =")!.lines.last == "AB = [0].")
        print("Matrix checks passed: rectangular products, signs, decimals, dimensions, and ambiguous-input rejection.")
    }
}
