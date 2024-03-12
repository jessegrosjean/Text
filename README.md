# Text

Simple attributed string, not well tested.

Maybe useful as an alternative to Swift's AttributedString, if you have many short (paragraph sized) attributed strings. It's quite a bit faster to init than AttributedString for small strings.


```
var t = Text("ab")
t.append("c")
t.insert(.init("Hello ", attributes: ["a" : "b"]), at: 0)
t.replaceSubrange(1..<2, with: "o")
t.modifyAttributes(0..<1) { attrs in
    attrs["c"] = "d"
}
XCTAssertEqual(t.debugDescription, "(H/a:b,c:d)(ollo /a:b)(abc/)")
```
