import AppKit

@main
enum PlipTests {
    static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }
            checks += 1
        }
        func rejects(_ value: String, _ kind: PlistKind) {
            do { _ = try PlistNode.parse(value, as: kind); fatalError("Accepted invalid \(kind): \(value)") }
            catch { checks += 1 }
        }
        let fixture: [String: Any] = [
            "Name": "Plip & <friends>\nUnicode: 🦋", "Enabled": true, "Disabled": false,
            "Count": NSNumber(value: Int64.min), "MaxUnsigned": NSNumber(value: UInt64.max),
            "Ratio": 3.14159, "WholeReal": 2.0,
            "Created": Date(timeIntervalSince1970: 1700000000), "Payload": Data([0, 127, 128, 255]),
            "Nested": ["Empty": [String: Any](), "Items": ["hello", 12, false] as [Any]],
            "EmptyArray": [Any](), "EmptyData": Data()
        ]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let input = try PropertyListSerialization.data(fromPropertyList: fixture, format: format, options: 0)
            let document = PlistDocument()
            try document.read(from: input, ofType: "com.apple.property-list")
            expect(document.format == format, "preserve format")
            let output = try document.data(ofType: "com.apple.property-list")
            let decoded = try PropertyListSerialization.propertyList(from: output, format: nil) as! NSDictionary
            expect(decoded.isEqual(to: fixture), "all types round trip in \(format)")
            expect(document.root.children.first(where: { $0.key == "Enabled" })?.kind == .boolean, "boolean detection")
            expect(document.root.children.first(where: { $0.key == "Count" })?.kind == .integer, "integer detection")
            expect(document.root.children.first(where: { $0.key == "WholeReal" })?.kind == .real, "whole real detection")
            expect(document.root.children.allSatisfy { $0.parent === document.root }, "parent links")
            let copy = document.root.copyTree()
            copy.children[0].key = "Changed"
            expect(document.root.children[0].key != "Changed", "independent snapshot")
            expect(copy.children[0].parent === copy, "snapshot parent links")
            expect(copy.id == document.root.id, "snapshot preserves UI identity")
            let duplicate = document.root.copyTree(preservingIdentity: false)
            expect(duplicate.id != document.root.id && duplicate.children[0].id != document.root.children[0].id, "duplicate receives new identities")
            document.undoManager?.beginUndoGrouping()
            document.change("Change Value") { document.root.children.append(PlistNode.empty(.string, key: "Added")) }
            document.undoManager?.endUndoGrouping()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            expect(document.isDocumentEdited, "document tracks unsaved edits")
            expect(document.root.children.contains { $0.key == "Added" }, "edit applied")
            document.undoManager?.undo()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            expect(!document.root.children.contains { $0.key == "Added" }, "undo restores tree")
            expect(!document.isDocumentEdited, "undo restores clean state")
            document.undoManager?.redo()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            expect(document.root.children.contains { $0.key == "Added" }, "redo restores edit")
        }
        for (text, kind) in [("18446744073709551615", PlistKind.integer), ("-9223372036854775808", .integer), ("2.0", .real), ("1.5e3", .real), ("false", .boolean), ("true", .boolean), ("2026-01-01T12:00:00Z", .date), ("2026-01-01T12:00:00.125+02:00", .date), ("DE AD\nBE EF", .data), ("", .data), ("  hello\n", .string)] {
            let scalar = try PlistNode.parse(text, as: kind)
            let node = PlistNode(key: "x", kind: kind, scalar: scalar)
            _ = try PlistNode.parse(node.text, as: kind)
            checks += 1
        }
        for text in ["1.2", "", "18446744073709551616", "-9223372036854775809"] { rejects(text, .integer) }
        for text in ["nan", "inf", "1e999", "hello"] { rejects(text, .real) }
        rejects("yes", .boolean); rejects("tomorrow", .date); rejects("FF0", .data); rejects("GG", .data); rejects("ＦＦ", .data)
        for root: Any in [[1, 2, 3], "scalar", true, Data([1, 2])] {
            let node = try PlistNode.decode(root)
            let bytes = try PropertyListSerialization.data(fromPropertyList: node.object(), format: .binary, options: 0)
            _ = try PropertyListSerialization.propertyList(from: bytes, format: nil)
            checks += 1
        }
        do { try PlistDocument().read(from: Data("not a plist".utf8), ofType: "com.apple.property-list"); fatalError("Accepted invalid file") }
        catch { checks += 1 }
        let dict = PlistNode(key: "Root", kind: .dictionary, children: [PlistNode.empty(.string), PlistNode.empty(.string, key: "New Item 2")])
        expect(dict.availableKey("New Item") == "New Item 3", "unique dictionary keys")
        expect(NSClassFromString("PlistDocument") == PlistDocument.self, "document class registration")
        print("Passed \(checks) checks: XML/binary round trips, types, validation, undo/redo, and document registration.")
    }
}
