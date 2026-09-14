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
        // Local date presentation and absolute-date persistence across DST boundaries.
        let newYork = TimeZone(identifier: "America/New_York")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let instant = try PlistNode.parse("2026-01-01T02:30:00Z", as: .date) as! Date
        let local = PlistNode.localDateText(instant, locale: Locale(identifier: "en_GB"), timeZone: newYork)
        let universal = PlistNode.localDateText(instant, locale: Locale(identifier: "en_GB"), timeZone: utc)
        expect(local.contains("31 Dec 2025") && universal.contains("1 Jan 2026"), "local display crosses the calendar day correctly")
        let french = PlistNode.localDateText(instant, locale: Locale(identifier: "fr_FR"), timeZone: utc)
        expect(french != universal && french.contains("janv"), "date display respects locale")
        for (month, hourUTC) in [(1, 17), (7, 16)] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = newYork
            let localNoon = calendar.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 12, minute: 30, second: 15))!
            var utcCalendar = Calendar(identifier: .gregorian); utcCalendar.timeZone = utc
            expect(utcCalendar.component(.hour, from: localNoon) == hourUTC, "local input uses the date's daylight-saving offset")
            for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
                let document = PlistDocument()
                document.root = PlistNode(key: "Root", kind: .dictionary, children: [PlistNode(key: "When", kind: .date, scalar: localNoon)])
                document.format = format
                let bytes = try document.data(ofType: "com.apple.property-list")
                let read = try PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: Any]
                expect(read["When"] as? Date == localNoon, "local date edit saves the same instant in XML and binary")
                if format == .xml { expect(String(decoding: bytes, as: UTF8.self).contains("Z</date>"), "XML stores UTC") }
            }
        }
        let dateDocument = PlistDocument()
        let precise = Date(timeIntervalSince1970: 1700000000.123456)
        let dateNode = PlistNode(key: "When", kind: .date, scalar: precise)
        dateDocument.root.children = [dateNode]; dateNode.parent = dateDocument.root
        let dateController = EditorController(document: dateDocument)
        let dateSheet = ItemEditor(node: dateNode, parent: dateDocument.root, editor: dateController, isNew: false)
        expect(dateSheet.datePicker.timeZone == TimeZone.current, "native picker uses local timezone")
        expect(dateSheet.dateArea.isHidden == false && dateSheet.valueScroll.isHidden, "date editing uses the native control")
        dateSheet.keyField.stringValue = "Renamed"
        dateSheet.apply(nil)
        expect(dateNode.scalar as? Date == precise, "renaming preserves subsecond precision")
        let changed = precise.addingTimeInterval(3600)
        dateSheet.datePicker.dateValue = changed; dateSheet.dateChanged(nil); dateSheet.apply(nil)
        expect(dateNode.scalar as? Date == changed, "native picker edits persist")
        dateSheet.typePicker.selectItem(withTitle: "String"); dateSheet.typeChanged(nil)
        dateSheet.typePicker.selectItem(withTitle: "Date"); dateSheet.typeChanged(nil)
        expect(dateSheet.dateDraft == changed, "date draft survives switching types")
        let literal = PlistNode(key: "Text", kind: .string, scalar: "2026-01-01T20:30:00Z")
        expect(literal.displayText == literal.text && literal.kind == .string, "date-like strings are not converted")

        // Dropped items retain their original file URLs. Reject text, remote URLs, folders, and mixed drops.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Original.plist")
        let original = try PropertyListSerialization.data(fromPropertyList: ["Value": "Original"], format: .xml, options: 0)
        try original.write(to: file)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([file as NSURL])
        expect(PlistFileDrop.urls(from: pasteboard) == [file], "drop retains the original path")
        let dropView = PlistDropView()
        var received: [URL] = []
        dropView.onDrop = { received = $0 }
        expect(dropView.acceptDrop(from: pasteboard), "drop handler accepts a file reference")
        expect(received == [file], "drop handler passes the original URL to document opening")
        let opened = try PlistDocument(contentsOf: file, ofType: "com.apple.property-list")
        expect(opened.fileURL == file, "opening retains original document URL")
        let afterOpen = try Data(contentsOf: file)
        expect(afterOpen == original, "opening does not modify the original")
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        expect(fileNames == ["Original.plist"], "opening creates no imported copy")
        pasteboard.clearContents(); pasteboard.writeObjects([folder as NSURL])
        expect(PlistFileDrop.urls(from: pasteboard).isEmpty, "reject directory drops")
        pasteboard.clearContents(); pasteboard.setString("Original.plist", forType: .string)
        expect(PlistFileDrop.urls(from: pasteboard).isEmpty, "reject plain text drops")
        let missing = folder.appendingPathComponent("Missing.plist")
        pasteboard.clearContents(); pasteboard.writeObjects([file as NSURL, missing as NSURL])
        expect(PlistFileDrop.urls(from: pasteboard).isEmpty, "reject mixed valid and invalid drops")
        received = []
        expect(!dropView.acceptDrop(from: pasteboard) && received.isEmpty, "invalid drop never invokes document opening")
        print("Passed \(checks) checks: XML/binary round trips, types, validation, undo/redo, and document registration.")
    }
}
