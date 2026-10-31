import Foundation

enum WrapAudit {
    static func run() throws {
        func rows(_ first: String = "Lookup follows the", _ second: String = "active calling sequence.",
                  x: Double = 580, page: String = "p1") -> [SpatialLine] {
            [SpatialLine(blockID:"S1",text:"Alpha resolves names.",page:"p1",rect:[60,100,370,25]),
             SpatialLine(blockID:"S2",text:"Beta resolves names.",page:"p1",rect:[560,100,370,25]),
             SpatialLine(blockID:"S3",text:first,page:"p1",rect:[580,140,350,25]),
             SpatialLine(blockID:"S4",text:second,page:page,rect:[x,180,350,25])]
        }
        func normalize(_ lines:[SpatialLine]) throws -> (lines:[SpatialLine],origins:[[String]]) {
            try SpatialGroups.coalescedWraps(lines,transcript:GapTranscript(selected:lines.map(\.text).joined(separator:"\n"),context:""))
        }
        func unchanged(_ lines:[SpatialLine]) throws {
            let result = try normalize(lines); precondition(result.lines.count == lines.count)
        }
        let joined = try normalize(rows())
        precondition(joined.lines.count == 3)
        precondition(joined.origins == [["S1"],["S2"],["S3","S4"]])
        precondition(joined.lines[2].rect == [580,140,350,65])
        precondition(joined.lines[2].text == "Lookup follows the active calling sequence.")
        try unchanged(rows("Lookup follows the."))
        try unchanged(rows("Lookup follows the","Active calling sequence."))
        try unchanged(rows(x:610))
        try unchanged(rows(page:"p2"))
        try unchanged(rows("Lookup:"))
        try unchanged(rows("Lookup follows the","- active calling sequence."))
        try unchanged(rows(String(repeating:"a",count:230)))
        // A union rectangle could enlarge a proximity threshold and swallow a
        // different paragraph. The original partition must win in that case.
        let separated = ["A sentence begins","and continues","then finishes.","Another topic."].enumerated().map {
            SpatialLine(blockID:"S\($0.offset+1)",text:$0.element,page:"p1",rect:[60,[100.0,120,140,190][$0.offset],100,10])
        }
        try unchanged(separated)
        print("WRAP GUARDS 12/12")
    }
}
