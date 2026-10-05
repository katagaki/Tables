import Foundation
import Testing
@testable import Tables

@Suite("VBA indentation")
struct VBAIndenterTests {
    /// The text after pressing Return at the `|` in `text`, with the cursor
    /// marked the same way.
    private func pressReturn(_ text: String) -> String {
        let cursor = (text as NSString).range(of: "|").location
        let source = (text as NSString).replacingCharacters(in: NSRange(location: cursor, length: 1), with: "")
        let edit = VBAIndenter.returnEdit(in: source, selection: NSRange(location: cursor, length: 0))
        let result = (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result as NSString).replacingCharacters(in: NSRange(location: edit.cursor, length: 0), with: "|")
    }

    @Test("A block opener indents the next line")
    func opens() {
        #expect(pressReturn("Sub Main()|") == "Sub Main()\n    |")
        #expect(pressReturn("    For i = 1 To 3|") == "    For i = 1 To 3\n        |")
        #expect(pressReturn("Private Function F() As Long|") == "Private Function F() As Long\n    |")
        #expect(pressReturn("    If x Then ' check|") == "    If x Then ' check\n        |")
    }

    @Test("Single-line If and ordinary statements keep the indentation")
    func keeps() {
        #expect(pressReturn("    If x Then y = 1|") == "    If x Then y = 1\n    |")
        #expect(pressReturn("    x = 1|") == "    x = 1\n    |")
        #expect(pressReturn("    Exit For|") == "    Exit For\n    |")
        #expect(pressReturn("    s = \"Sub isn't\" ' Sub|") == "    s = \"Sub isn't\" ' Sub\n    |")
    }

    @Test("Closers snap back to their opener")
    func closes() {
        #expect(pressReturn("Sub Main()\n    x = 1\n    End Sub|") == "Sub Main()\n    x = 1\nEnd Sub\n|")
        #expect(pressReturn("    For i = 1 To 3\n        x = i\n        Next|")
                == "    For i = 1 To 3\n        x = i\n    Next\n    |")
        // Nested blocks find their own opener, not the outer one.
        #expect(pressReturn("Sub A()\n    If x Then\n        Do\n        Loop\n        End If|")
                == "Sub A()\n    If x Then\n        Do\n        Loop\n    End If\n    |")
    }

    @Test("Else lines up with its If and opens a block of its own")
    func middles() {
        #expect(pressReturn("    If x Then\n        y = 1\n        Else|") == "    If x Then\n        y = 1\n    Else\n        |")
        #expect(pressReturn("Select Case x\n    Case 1\n        y = 1\n        Case 2|")
                == "Select Case x\n    Case 1\n        y = 1\n    Case 2\n        |")
    }

    @Test("Text after the cursor moves to the new line, without its leading spaces")
    func splits() {
        #expect(pressReturn("Sub Main()|   x = 1") == "Sub Main()\n    |x = 1")
    }
}
