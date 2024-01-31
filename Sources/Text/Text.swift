import Foundation

public typealias CharIndex = Int
public typealias RunIndex = UInt16
public typealias UTF16CharIndex = UInt32

public enum Affinity: Codable {
    case upstream
    case downstream
}

public struct Text: Equatable, Hashable, Sendable {
    
    public typealias Index = String.Index
    public typealias Attributes = [String : String]
        
    public struct Name: Hashable, ExpressibleByStringLiteral {
        public let value: String
        public init(stringLiteral value: String) {
            self.value = value
        }
    }
    
    public struct Run: Equatable, Hashable, Sendable {
        public var utf8Len: Int
        public var attrs: [String : String]
    }
    
    public struct Replaced: CustomDebugStringConvertible {
        public var at: CharIndex
        public var replaced: Text
        public var inserted: Text
        public var debugDescription: String {
            "at: \(at), replaced: \(replaced), inserted: \(inserted)"
        }
    }
    
    var _string: String
    var _runs: Runs
    
    public init(_ string: String = "") {
        self._string = string
        self._string.makeContiguousUTF8()
        self._runs = .plainText(_string.utf8.count)
    }
    
    public init(_ string: String, attributes: Attributes) {
        self._string = string
        self._string.makeContiguousUTF8()
        if _string.isEmpty {
            self._runs = .richText([])
        } else {
            self._runs = .richText([.init(
                attrs: attributes,
                utf8Len: _string.utf8.count
            )])
        }
    }
    
    init(_ string: String, runs: Runs) {
        self._string = string
        self._string.makeContiguousUTF8()
        self._runs = runs
    }
    
    public var isEmpty: Bool {
        _string.isEmpty
    }
    
    public var isPlain: Bool {
        switch _runs {
        case .plainText:
            return true
        case .richText:
            return false
        }
    }
        
    public var isRich: Bool {
        switch _runs {
        case .plainText:
            return false
        case .richText:
            return true
        }
    }
    
    public var hasAttributes: Bool {
        switch _runs {
        case .plainText:
            return false
        case .richText(let runs):
            for r in runs {
                if !r.isEmpty {
                    return true
                }
            }
            return false
        }
    }
    
    public var asPlain: Self {
        guard isRich else {
            return self
        }
        return .init(_string)
    }

    public var asRich: Self {
        guard isPlain else {
            return self
        }
        return .init(_string, attributes: [:])
    }

    // MARK: Indicies

    public var indices: DefaultIndices<String> {
        _string.indices
    }
    
    public var startIndex: Index {
        _string.startIndex
    }
    
    public var endIndex: Index {
        _string.endIndex
    }

    public func index(_ charIndex: CharIndex) -> Index {
        _string.index(
            _string.startIndex,
            offsetBy: charIndex
        )
    }

    public func range(_ range: Range<CharIndex>) -> Range<Index> {
        let startIndex = _string.startIndex
        
        let rangeStart = _string.index(
            startIndex,
            offsetBy: range.lowerBound
        )
        
        let rangeEnd = _string.index(
            rangeStart,
            offsetBy: range.count
        )
        
        return rangeStart..<rangeEnd
    }

    // MARK: Text

    public var count: Int {
        _string.count
    }

    public var string: String {
        _string
    }

    public subscript(range: Range<CharIndex>) -> Self {
        self[self.range(range)]
    }

    public subscript(range: Range<Index>) -> Self {
        var copy = self
        _ = copy.split(range.upperBound)
        return copy.split(range.lowerBound)
    }

    // MARK: Mutate Text

    @discardableResult
    public mutating func insert(
        _ s: Self,
        at index: CharIndex
    ) -> Replaced {
        insert(s, at: self.index(index))
    }

    @discardableResult
    public mutating func insert(
        _ s: Self,
        at index: Index
    ) -> Replaced {
        replaceSubrange(index..<index, with: s)
    }

    @discardableResult
    public mutating func replaceSubrange(
        _ range: Range<CharIndex>,
        with s: Text
    ) -> Replaced {
        replaceSubrange(self.range(range), with: s)
    }

    @discardableResult
    public mutating func replaceSubrange(
        _ range: some RangeExpression<Index>,
        with s: Text
    ) -> Replaced {
        if s.isRich && isPlain {
            self = asRich
        }
        
        let range = range.relative(to: _string)
        let tail = split(range.upperBound)
        let at = _string.distance(to: range.lowerBound)
        let replaced = split(range.lowerBound)
        _ = append(s)
        _ = append(tail)
        return .init(
            at: at,
            replaced: replaced,
            inserted: s
        )
    }
    
    public mutating func split(_ index: Index) -> Text {
        if index == _string.endIndex {
            return .init("")
        } else if index == _string.startIndex {
            let r = self
            self = .init("")
            return r
        }
        
        let split = String(_string[index...])
        _string.removeSubrange(index...)
        let utf8 = _string.utf8
        let startIndex = utf8.startIndex
        let byteIndex = utf8.distance(from: startIndex, to: index)
        return Text(split, runs: _runs.split(at: byteIndex))
    }

    @discardableResult
    public mutating func prepend(_ prepend: Text) -> Replaced {
        replaceSubrange(startIndex..<startIndex, with: prepend)
    }
    
    @discardableResult
    public mutating func append(_ append: Text) -> Replaced {
        let replaced = Replaced(
            at: _string.count,
            replaced: .init(""),
            inserted: append.asRich
        )
        
        guard !append.isEmpty else {
            return replaced
        }
        
        let atByte = _string.utf8.count
        let atRun = _runs.runs.count
        
        _string.append(append._string)
        _runs.append(append._runs)
        _runs.fixRunBoundariesAfterAppending(
            atByte: atByte,
            atRun: atRun,
            in: _string
        )
        
        // Does replaced need to be fixed for combining marks? My brain hurts...intention
        // is to use these Replaced results to implement undo. Will wait until implementing
        // undo to figure the details out.
        
        return replaced
    }
    
    public func appending(_ append: Self) -> Self {
        var s = self
        s.append(append)
        return s
    }
    
    // MARK: Attributes

    public var runs: [Run] {
        _runs.runs
    }

    public var runsWithRanges: [(
        run: Run,
        range: Range<Index>,
        cfRange: CFRange
    )] {
        _runs.runsWithRanges(in: _string)
    }

    public var runsWithSubstrings: [(Run, Substring)] {
        _runs.runsWithSubstrings(in: _string)
    }

    public func attribute(_ name: Name, at index: CharIndex, affinity: Affinity = .upstream) -> String? {
        attributes(at: self.index(index), affinity: affinity)?[name.value]
    }
    
    public func attribute(_ name: Name, at index: Index, affinity: Affinity = .upstream) -> String? {
        attributes(at: index, affinity: affinity)?[name.value]
    }

    public func attributes(at index: CharIndex, affinity: Affinity = .upstream) -> [String : String]? {
        attributes(at: self.index(index), affinity: affinity)
    }
    
    public func attributes(at index: Index, affinity: Affinity = .upstream) -> [String : String]? {
        let utf8 = _string.utf8
        let byte = utf8.distance(to: index)
        return _runs.attributes(at: byte, affinity: affinity)
    }

    public func longestEffectiveRange(
        at index: CharIndex,
        affinity: Affinity = .upstream
    ) -> Range<Index>? {
        longestEffectiveRange(at: self.index(index), affinity: affinity)
    }
    
    public func longestEffectiveRange(
        at index: Index,
        affinity: Affinity = .upstream
    ) -> Range<Index>? {
        let seek = attributes(at: index, affinity: affinity)
        return longestEffectiveRange(
            at: index,
            affinity: affinity
        ) { attributes in
            attributes == seek
        }
    }

    public func longestEffectiveRange(
        at index: CharIndex,
        affinity: Affinity = .upstream,
        where test: (Attributes) -> Bool
    ) -> Range<Index>? {
        longestEffectiveRange(
            at: self.index(index),
            affinity: affinity,
            where: test
        )
    }
    
    public func longestEffectiveRange(
        at index: Index,
        affinity: Affinity = .upstream,
        where test: (Attributes) -> Bool
    ) -> Range<Index>? {
        let utf8 = _string.utf8
        let byte = utf8.distance(to: index)
        guard let byteRange = _runs.longestEffectiveRange(at: byte, where: test) else {
            return nil
        }
        let startIndex = utf8.index(utf8.startIndex, offsetBy: byteRange.lowerBound)
        let endIndex = utf8.index(startIndex, offsetBy: byteRange.count)
        return startIndex..<endIndex
    }

    // MARK: Mutate Attributes

    public mutating func addAttribute(
        _ name: Name,
        value: String,
        range: some RangeExpression<Index>
    ) {
        modifyAttributes(range) {
            $0[name.value] = value
        }
    }
    
    public mutating func addAttributes(
        _ attrs: Attributes,
        range: some RangeExpression<Index>
    ) {
        modifyAttributes(range) {
            $0.merge(attrs) { _, new in
                new
            }
        }
    }

    public mutating func removeAttribute(
        _ name: Name,
        range: some RangeExpression<Index>
    ) {
        modifyAttributes(range) {
            $0.removeValue(forKey: name.value)
        }
    }

    public mutating func removeAttributes(
        _ names: [Name],
        range: some RangeExpression<Index>
    ) {
        modifyAttributes(range) {
            for n in names {
                $0.removeValue(forKey: n.value)
            }
        }
    }

    public mutating func setAttributes(
        _ attrs: Attributes,
        range: some RangeExpression<Index>
    ) {
        modifyAttributes(range) {
            $0 = attrs
        }
    }

    public mutating func modifyAttributes(
        _ range: Range<CharIndex>,
        modify: (inout [String : String]) -> ()
    ) {
        modifyAttributes(self.range(range), modify: modify)
    }
    
    public mutating func modifyAttributes(
        _ range: some RangeExpression<Index>,
        modify: (inout [String : String]) -> ()
    ) {
        let range = range.relative(to: _string)
        let utf8 = _string.utf8
        let startByte = utf8.distance(to: range.lowerBound)
        let endByte = utf8.distance(to: range.upperBound)
        _runs.modifyAttributes(
            startByte..<endByte,
            modify: modify
        )
    }

    @discardableResult
    public mutating func transformRuns(
        callback: (Substring, inout [String : String]) -> String?
    ) -> Replaced {
        transformRuns(startIndex..<endIndex, callback: callback)
    }

    @discardableResult
    public mutating func transformRuns(
        _ range: Range<CharIndex>,
        callback: (Substring, inout [String : String]) -> String?
    ) -> Replaced {
        transformRuns(self.range(range), callback: callback)
    }
    
    @discardableResult
    public mutating func transformRuns(
        _ range: Range<Index>,
        callback: (Substring, inout [String : String]) -> String?
    ) -> Replaced {
        let originalText = self[range]
        var replaceText = Self()

        for (run, substring) in originalText.runsWithSubstrings {
            var attrs = run.attrs
            if let transformedString = callback(substring, &attrs) {
                if !transformedString.isEmpty {
                    replaceText.append(.init(transformedString, attributes: attrs))
                }
            } else {
                replaceText.append(.init(String(substring), attributes: attrs))
            }
        }

        return replaceSubrange(range, with: replaceText)
    }
}

extension Text: ExpressibleByStringLiteral {
    
    public init(stringLiteral value: String) {
        self.init(value)
    }

}

extension Text.Run {
    
    public var isEmpty: Bool {
        utf8Len == 0
    }
    
    init(attrs: [String : String] = [:], utf8Len: Int) {
        self.attrs = attrs
        self.utf8Len = utf8Len
    }
    
    public subscript(index: Text.Name) -> String? {
        get {
            self.attrs[index.value]
        }
        set {
            self.attrs[index.value] = newValue
        }
    }

    mutating func split(index: Int) -> Self? {
        if index == 0 || index == utf8Len {
            return nil
        }
        var remainder = self
        remainder.utf8Len = utf8Len - index
        utf8Len = index
        return remainder
    }
    
}

extension Text: CustomDebugStringConvertible {
    
    public func validate() {
        _runs.validate(in: _string)
    }
    
    public var debugDescription: String {
        if _string.isEmpty {
            return "()"
        }
        
        var s = ""
        for (run, substring) in runsWithSubstrings {
            s.append("(")
            s.append(contentsOf: substring)
            if !run.attrs.isEmpty {
                assert(isRich)
                s.append("/")
                for key in run.attrs.keys.sorted() {
                    s.append("\(key):\(run.attrs[key]!),")
                }
                s.removeLast(1)
            } else if isRich {
                s.append("/")
            }
            s.append(")")
        }
        return s
    }
    
}

extension Collection {
    public func distance(to index: Index) -> Int { distance(from: startIndex, to: index) }
}
