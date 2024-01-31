import XCTest
@testable import Text

final class TextTests: XCTestCase {
    
    func testEmpty() {
        let t1 = Text("")
        XCTAssertTrue(t1.isPlain)
        XCTAssertEqual(t1.runs.count, 0)
        t1.validate()

        let t2 = Text("", attributes: ["a" : "b"])
        XCTAssertTrue(t2.isRich)
        XCTAssertEqual(t2.runs.count, 0)
        t2.validate()

        let t3 = Text("", attributes: [:])
        XCTAssertTrue(t3.isRich)
        XCTAssertEqual(t3.runs.count, 0)
        t3.validate()
    }

    func testSingle() {
        let t1 = Text("Hello")
        XCTAssertTrue(t1.isPlain)
        XCTAssertEqual(t1.runs.count, 1)
        XCTAssertEqual(t1.debugDescription, "(Hello)")
        t1.validate()

        let t2 = Text("Hello", attributes: ["a" : "b"])
        XCTAssertTrue(t2.isRich)
        XCTAssertEqual(t2.runs[0].attrs, ["a" : "b"])
        XCTAssertEqual(t2.runs.count, 1)
        XCTAssertEqual(t2.debugDescription, "(Hello/a:b)")
        t2.validate()

        let t3 = Text("Hello", attributes: [:])
        XCTAssertTrue(t3.isRich)
        XCTAssertEqual(t3.runs[0].attrs, [:])
        XCTAssertEqual(t3.runs.count, 1)
        XCTAssertEqual(t3.debugDescription, "(Hello/)")
        t3.validate()
    }
    
    func testAddAttributeFirst() {
        var s = Text("abc")
        s.modifyAttributes(0..<1) { attributes in
            attributes["new"] = "a"
        }
        s.modifyAttributes(2..<3) { attributes in
            attributes["new"] = "c"
        }
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.debugDescription, "(a/new:a)(b/)(c/new:c)")
        XCTAssertEqual(s.attribute("new", at: 0, affinity: .upstream), "a")
        XCTAssertEqual(s.attribute("new", at: 0, affinity: .downstream), "a")
        XCTAssertEqual(s.attribute("new", at: 1, affinity: .upstream), "a")
        XCTAssertEqual(s.attribute("new", at: 1, affinity: .downstream), nil)
        XCTAssertEqual(s.attribute("new", at: 2, affinity: .upstream), nil)
        XCTAssertEqual(s.attribute("new", at: 2, affinity: .downstream), "c")
        XCTAssertEqual(s.attribute("new", at: 3, affinity: .upstream), "c")
        XCTAssertEqual(s.attribute("new", at: 3, affinity: .downstream), "c")
    }
    
    func testAddAttributeMiddle() throws {
        var s = Text("abc")
        s.modifyAttributes(1..<2) { attributes in
            attributes["new"] = "attr"
        }
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.debugDescription, "(a/)(b/new:attr)(c/)")
        XCTAssertEqual(s.attribute("new", at: 0), nil)
        XCTAssertEqual(s.attribute("new", at: 1), nil)
        XCTAssertEqual(s.attribute("new", at: 2), "attr")
        XCTAssertEqual(s.attribute("new", at: 3), nil)
    }

    func testAddAttributeEnd() throws {
        var s = Text("abc")
        s.modifyAttributes(1..<3) { attributes in
            attributes["new"] = "attr"
        }
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.debugDescription, "(a/)(bc/new:attr)")
    }

    func testInsertTextStart() throws {
        var s = Text("abc")
        s.insert(Text("z", attributes: ["new":"attr"]), at: 0)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.debugDescription, "(z/new:attr)(abc/)")
    }

    func testLongestEffectiveRange() throws {
        var s = Text("abc")
        s.modifyAttributes(0..<1) { attributes in
            attributes["a"] = "a"
        }
        s.modifyAttributes(1..<3) { attributes in
            attributes["bc"] = "bc"
        }
        
        XCTAssertEqual(s[s.longestEffectiveRange(at: 0) { $0.keys.contains("a") }!].string, "a")
        XCTAssertEqual(s[s.longestEffectiveRange(at: 1) { $0.keys.contains("a") }!].string, "a")
        XCTAssertEqual(s.longestEffectiveRange(at: 2) { $0.keys.contains("a") }, nil)
        XCTAssertEqual(s.longestEffectiveRange(at: 1) { $0.keys.contains("bc") }, nil)
        XCTAssertEqual(s[s.longestEffectiveRange(at: 2) { $0.keys.contains("bc") }!].string, "bc")
        XCTAssertEqual(s[s.longestEffectiveRange(at: 3) { $0.keys.contains("bc") }!].string, "bc")
    }
    
    func testReplaceAllClearsAttributes() throws {
        var s = Text("abc")
        s.modifyAttributes(0..<3) { attributes in
            attributes["a"] = "a"
        }
        s.replaceSubrange(0..<3, with: .init(""))
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.debugDescription, "()")
    }

    func testReplaceRangeEmpty() {
        var s = Text("")
        XCTAssertEqual(s.replaceSubrange(0..<0, with: .init("a")).debugDescription, "at: 0, replaced: (), inserted: (a)")
        XCTAssertEqual(s.debugDescription, "(a)")
    }

    func testReplaceRangeFirst() {
        var s = Text("abc")
        XCTAssertEqual(s.replaceSubrange(0..<1, with: .init("Z")).debugDescription, "at: 0, replaced: (a), inserted: (Z)")
        XCTAssertEqual(s.debugDescription, "(Zbc)")
    }

    func testReplaceRangeMiddle() {
        var s = Text("abc")
        XCTAssertEqual(s.replaceSubrange(1..<2, with: .init("Z")).debugDescription, "at: 1, replaced: (b), inserted: (Z)")
        XCTAssertEqual(s.debugDescription, "(aZc)")
    }

    func testReplaceRangeMiddleEmpty() {
        var s = Text("abc")
        XCTAssertEqual(s.replaceSubrange(1..<1, with: .init("Z")).debugDescription, "at: 1, replaced: (), inserted: (Z)")
        XCTAssertEqual(s.debugDescription, "(aZbc)")
    }

    func testReplaceRangeEnd() {
        var s = Text("abc")
        XCTAssertEqual(s.replaceSubrange(2..<3, with: .init("Z")).debugDescription, "at: 2, replaced: (c), inserted: (Z)")
        XCTAssertEqual(s.debugDescription, "(abZ)")
    }
    
    func testSubscripts() {
        var a = Text("a", attributes: ["a" : "a"])
        a.append(.init("b", attributes: ["b" : "b"]))

        XCTAssertEqual(a[0..<0].debugDescription, "()")
        XCTAssertEqual(a[0..<1].debugDescription, "(a/a:a)")
        XCTAssertEqual(a[0..<2].debugDescription, "(a/a:a)(b/b:b)")
        XCTAssertEqual(a[1..<2].debugDescription, "(b/b:b)")
        XCTAssertEqual(a[2..<2].debugDescription, "()")
    }
    
    func testPlainAppend() {
        var a = Text("a")
        let b = Text("b")
        a.append(b)
        a.validate()
        XCTAssertEqual(a.string, "ab")
    }

    func testRichAppend() {
        var a = Text("a", attributes: ["a" : "a"])
        let b = Text("b", attributes: ["b" : "b"])
        a.append(b)
        a.validate()
        XCTAssertEqual(a.string, "ab")
        XCTAssertEqual(a.debugDescription, "(a/a:a)(b/b:b)")
    }

    func testCombiningPrepend() {
        var s = Text("\u{0302}")
        XCTAssertEqual(s.prepend("\u{0302}").debugDescription, "at: 0, replaced: (), inserted: (\u{0302})")
        XCTAssertEqual(s.debugDescription, "(\u{0302}\u{0302})")
        XCTAssertEqual(s.prepend("e").debugDescription, "at: 0, replaced: (), inserted: (e)")
        XCTAssertEqual(s.debugDescription, "(e\u{0302}\u{0302})")
        s.validate()
    }

    func testCombiningAppend() {
        var a = Text("\u{1F469}", attributes: ["a" : "a"])
        let b = Text("\u{1F3FB}\u{200D}\u{1F692}", attributes: ["b" : "b"])
        a.append(b)
        a.validate()
        XCTAssertEqual(a.string, "👩🏻‍🚒")
        XCTAssertEqual(a.debugDescription, "(👩🏻‍🚒/a:a)")
    }

    func testCombiningAppendWith() {
        let x = Text("\u{1F469}", attributes: ["woman" : "woman"])
        let y = Text("\u{1F3FB}\u{200D}\u{1F692}", attributes: ["skinzerofire" : "skinzerofire"])
        let z = x.appending(y)
        z.validate()
        XCTAssertEqual(z.debugDescription, "(\u{1F469}\u{1F3FB}\u{200D}\u{1F692}/woman:woman)")
    }
    
    func testReplaceWithCombiningAccent() {
        var s = Text("abc")

        XCTAssertEqual(
            s.replaceSubrange(0..<1, with: "\u{0302}").debugDescription,
            "at: 0, replaced: (a), inserted: (\u{0302})"
        )
        
        XCTAssertEqual(s.debugDescription, "(\u{0302}bc)")
        
        XCTAssertEqual(
            s.replaceSubrange(2..<3, with: "\u{0302}").debugDescription,
            "at: 2, replaced: (c), inserted: (\u{0302})"
        )
        
        XCTAssertEqual(s.debugDescription, "(\u{0302}b\u{0302})")
        
        XCTAssertEqual(
            s.replaceSubrange(2..<2, with: "\u{0302}\u{0302}").debugDescription,
            "at: 2, replaced: (), inserted: (\u{0302}\u{0302})"
        )
        
        XCTAssertEqual(s.debugDescription, "(\u{0302}b\u{0302}\u{0302}\u{0302})")
        
        s.validate()
    }
    
    func testSplit() {
        var a = Text("a", attributes: ["a" : "a"])
        a.append(.init("b", attributes: ["b" : "b"]))

        var s = a
        s.split(s.startIndex).validate()
        s.validate()

        var e = a
        e.split(e.endIndex).validate()
        e.validate()

        for i in a.indices {
            var z = a
            z.split(i).validate()
            z.validate()
        }
    }
    
    func testReplace() {
        var s = Text("a", attributes: ["a" : "a"])
        s.append(.init("b", attributes: ["b" : "b"]))
        s.append(.init("c", attributes: ["c" : "c"]))

        var t1 = s
        let r1 = t1.replaceSubrange(0..<1, with: .init("z"))
        XCTAssertEqual(r1.debugDescription, "at: 0, replaced: (a/a:a), inserted: (z)")
        XCTAssertEqual(t1.debugDescription, "(z/)(b/b:b)(c/c:c)")

        var t2 = s
        let r2 = t2.replaceSubrange(0..<2, with: .init("z"))
        XCTAssertEqual(r2.debugDescription, "at: 0, replaced: (a/a:a)(b/b:b), inserted: (z)")
        XCTAssertEqual(t2.debugDescription, "(z/)(c/c:c)")
    }
    
    func testModifyAttributes() {
        var s = Text("abc", attributes: [:])

        s.modifyAttributes(0..<1) { $0["1"] = "1" }
        XCTAssertEqual(s.debugDescription, "(a/1:1)(bc/)")

        s.modifyAttributes(1..<3) { $0["3"] = "3" }
        XCTAssertEqual(s.debugDescription, "(a/1:1)(bc/3:3)")

        s.modifyAttributes(1..<2) { $0["2"] = "2" }
        XCTAssertEqual(s.debugDescription, "(a/1:1)(b/2:2,3:3)(c/3:3)")
    }
    
}
