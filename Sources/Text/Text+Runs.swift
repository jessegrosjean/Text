import Foundation

extension Text {
        
    enum Runs: Equatable, Hashable, Sendable {
        case plainText(Int)
        case richText([Run])
    }
    
}

extension Text.Runs {

    typealias Run = Text.Run
    typealias Attributes = Text.Attributes

    var runs: [Run] {
        switch self {
        case .plainText(let len):
            if len == 0 { return [] }
            return [.init(utf8Len: len)]
        case .richText(let runs):
            return runs
        }
    }

    func runsWithRanges(in string: String) -> [(
        run: Run,
        range: Range<Text.Index>,
        cfRange: CFRange
    )] {
        let utf16 = string.utf16
        let utf8 = string.utf8
        var cfIndex: CFIndex = 0
        var i = utf8.startIndex
        return runs.map { run in
            let end = utf8.index(i, offsetBy: run.utf8Len)
            let cfLength = utf16.distance(from: i, to: end)
            let range = i..<end
            let cfRange = CFRange(location: cfIndex, length: cfLength)
            i = end
            cfIndex += cfLength
            return (run, range, cfRange)
        }
    }
    
    func runsWithSubstrings(in string: String) -> [(Run, Substring)] {
        let utf8 = string.utf8
        var i = utf8.startIndex
        return runs.map { run in
            let end = utf8.index(i, offsetBy: run.utf8Len)
            let substring = string[i..<end]
            i = end
            return (run, substring)
        }
    }

    func longestEffectiveRange(
        at byte: Int,
        affinity: Affinity = .upstream,
        where predicate: (Attributes) -> Bool
    ) -> Range<Int>? {
        func longestEffectiveRange(_ runIndex: Int, _ runStart: Int) -> Range<Int>? {
            if !predicate(runs[runIndex].attrs) {
                return nil
            }
            
            var minRunIndex = runIndex
            var maxRunIndex = runIndex
            
            while minRunIndex > 0, predicate(runs[minRunIndex - 1].attrs) {
                minRunIndex -= 1
            }

            while maxRunIndex < runs.count - 1, predicate(runs[maxRunIndex + 1].attrs) {
                maxRunIndex += 1
            }

            var minByteIndex = Int.max
            var maxByteIndex = Int.min
            var byte = 0
            
            for i in runs.indices {
                let runLen = runs[i].utf8Len
                if i == minRunIndex {
                    minByteIndex = byte
                }

                byte += runLen

                if i == maxRunIndex {
                    maxByteIndex = byte
                    return minByteIndex..<maxByteIndex
                }
            }

            fatalError()
        }
        
        var runEnd = 0
        for (i, run) in runs.enumerated() {
            runEnd += run.utf8Len
            if runEnd > byte {
                return longestEffectiveRange(i, runEnd - run.utf8Len)
            } else if runEnd == byte {
                switch affinity {
                case .upstream:
                    return longestEffectiveRange(i, runEnd - run.utf8Len)
                case .downstream:
                    if i + 1 < runs.count {
                        return longestEffectiveRange(i + 1, runEnd - run.utf8Len)
                    } else {
                        return longestEffectiveRange(i, runEnd - run.utf8Len)
                    }
                }
            }
        }
        
        fatalError()
    }
    
    func attributes(at byte: Int, affinity: Affinity = .upstream) -> [String : String]? {
        var runEnd = 0
        for (i, run) in runs.enumerated() {
            runEnd += run.utf8Len
            
            if runEnd > byte {
                return run.attrs
            } else if runEnd == byte {
                switch affinity {
                case .upstream:
                    return run.attrs
                case .downstream:
                    if i + 1 < runs.count {
                        return runs[i + 1].attrs
                    } else {
                        return run.attrs
                    }
                }
            }
        }
        
        fatalError()
    }
    
    mutating func append(_ runs: Self) {
        switch (self, runs) {
        case (.plainText(let len1), .plainText(let len2)):
            self = .plainText(len1 + len2)
        case (.plainText(let len1), .richText(var runs)):
            if runs[0].attrs.isEmpty {
                runs[0].utf8Len += len1
            } else {
                if len1 > 0 {
                    runs.insert(.init(utf8Len: len1), at: 0)
                }
            }
            self = .richText(runs)
        case (.richText(var runs), .plainText(let len2)):
            runs[runs.count - 1].utf8Len += len2
            self = .richText(runs)
        case (.richText(var runs1), .richText(var runs2)):
            if runs1.last?.attrs == runs2.last?.attrs {
                runs2[0].utf8Len += runs1.last?.utf8Len ?? 0
                runs1.removeLast()
                self = .richText(runs1 + runs2)
            } else {
                self = .richText(runs1 + runs2)
            }
        }
    }
    
    mutating func split(at splitIndex: Int) -> Self {
        switch self {
        case .plainText(let len):
            self = .plainText(splitIndex)
            return .plainText(len - splitIndex)
        case .richText(var runs):
            var runEnd = 0
            for i in runs.indices {
                runEnd += runs[i].utf8Len
                if runEnd == splitIndex {
                    let splitRuns = Array(runs[(i + 1)...])
                    runs.removeSubrange((i + 1)...)
                    self = .richText(runs)
                    return .richText(splitRuns)
                } else if runEnd > splitIndex {
                    let diff = runEnd - splitIndex
                    var splitRuns = Array(runs[i...])
                    
                    splitRuns[0].utf8Len -= diff
                    if splitRuns[0].isEmpty {
                        splitRuns.remove(at: 0)
                    }
                    
                    runs.removeSubrange(i...)
                    
                    runs[runs.count - 1].utf8Len += diff
                    if runs[runs.count - 1].isEmpty {
                        runs.remove(at: runs.count - 1)
                    }

                    self = .richText(runs)
                    return .richText(splitRuns)
                }
            }
            fatalError()
        }
    }
    
    mutating func fixRunBoundariesAfterAppending(atByte: Int, atRun: Int, in string: String) {
        guard case .richText(var runs) = self else {
            return
        }
        
        let utf8 = string.utf8
        let startIndex = string.startIndex
        let endIndex = string.endIndex
        let appendIndex = utf8.index(utf8.startIndex, offsetBy: atByte)
        
        // When append one string to another the suffix of the first string can be combined
        // (at character level) with the prefix of appended string. Our runs are specified
        // as byte lengths, but we always want them to lie at character boundaries...
        //
        // That is what this code is doing. Text was just appended atByte. The new atRun
        // starts at that byte. This code checks for combining. Adds combined characters to
        // atRun - 1 and removes those bytes from atRun (and following runs) until all
        // combined bytes are accounted with.
        
        if appendIndex != utf8.startIndex {
            let prevCharIndex = string.index(appendIndex, offsetBy: -1, limitedBy: startIndex) ?? startIndex
            let nextCharIndex = string.index(prevCharIndex, offsetBy: 1, limitedBy: endIndex) ?? endIndex
            
            if nextCharIndex > appendIndex {
                let combineBytes = utf8.distance(from: appendIndex, to: nextCharIndex)
                
                // Extend original run to include combined bytes
                runs[atRun - 1].utf8Len += combineBytes

                // Now remove those bytes from following runs until all accounted for
                var i = atRun
                var removingBytes = combineBytes
                while i < runs.count, removingBytes > 0 {
                    let removed = min(runs[i].utf8Len, removingBytes)
                    runs[i].utf8Len -= removed
                    removingBytes -= removed
                    i += 1
                }
                
                self = .richText(runs.filter { !$0.isEmpty })
            }
        }
    }
    
    mutating func modifyAttributes(
        _ byteRange: Range<Int>,
        modify: (inout Attributes) -> ()
    ) {
        ensureBoundary(at: byteRange.lowerBound)
        ensureBoundary(at: byteRange.upperBound)

        var runs = runs
        var runStart = 0

        for i in runs.indices {
            let runEnd = runStart + runs[i].utf8Len
            if runStart >= byteRange.lowerBound && runEnd <= byteRange.upperBound {
                modify(&runs[i].attrs)
            }
            runStart = runEnd
            if byteRange.upperBound == runEnd {
                self = .richText(runs)
                return
            }
        }
    }

    mutating func ensureBoundary(at byte: Int) {
        var runs = runs
        var runStart = 0
        
        for i in runs.indices {
            let runEnd = runStart + runs[i].utf8Len
            if byte < runEnd {
                if let split = runs[i].split(index: byte - runStart) {
                    runs.insert(split, at: i + 1)
                    self = .richText(runs)
                }
                return
            }
            runStart = runEnd
        }
    }

    func validate(in string: String) {
        let utf8 = string.utf8
        let validIndicies = Set(string.indices)
        
        func validateOnCharBoundary(offset: Int) {
            let offsetIndex = utf8.index(utf8.startIndex, offsetBy: offset)
            assert(validIndicies.contains(offsetIndex) || string.endIndex == offsetIndex)
        }
        
        var runStart = 0
        for run in runs {
            let runEnd = runStart + run.utf8Len
            validateOnCharBoundary(offset: runStart)
            validateOnCharBoundary(offset: runEnd)
            runStart = runEnd
        }
    }

}
