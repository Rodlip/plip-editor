import AppKit

final class ItemEditor: NSObject {
    let node: PlistNode
    let parent: PlistNode?
    let editor: EditorController
    let isNew: Bool
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
    let keyField = NSTextField()
    let typePicker = NSPopUpButton()
    let value = NSTextView()
    let hint = NSTextField(wrappingLabelWithString: "")
    let error = NSTextField(wrappingLabelWithString: "")
    var drafts: [PlistKind: String] = [:]
    var draftKind: PlistKind

    static func present(node: PlistNode, parent: PlistNode?, in editor: EditorController, isNew: Bool) {
        guard let window = editor.window, window.attachedSheet == nil else { return }
        let sheet = ItemEditor(node: node, parent: parent, editor: editor, isNew: isNew)
        window.beginSheet(sheet.panel) { _ in sheet.panel.orderOut(nil) }
        sheet.panel.makeFirstResponder(parent?.kind == .dictionary ? sheet.keyField : sheet.value)
    }

    init(node: PlistNode, parent: PlistNode?, editor: EditorController, isNew: Bool) {
        self.node = node; self.parent = parent; self.editor = editor; self.isNew = isNew; self.draftKind = node.kind
        super.init()
        buildUI()
    }

    func buildUI() {
        panel.title = isNew ? "Add Item" : "Edit Item"
        guard let content = panel.contentView else { return }
        let title = NSTextField(labelWithString: isNew ? "Add a property" : "Edit property")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let keyLabel = NSTextField(labelWithString: "Key")
        keyField.stringValue = parent?.kind == .dictionary ? node.key : parent == nil ? "Root" : "Array item (position determines its name)"
        keyField.isEnabled = parent?.kind == .dictionary
        keyField.setAccessibilityLabel("Property key")
        let typeLabel = NSTextField(labelWithString: "Type")
        typePicker.addItems(withTitles: PlistKind.allCases.map(\.rawValue))
        typePicker.selectItem(withTitle: node.kind.rawValue)
        typePicker.target = self; typePicker.action = #selector(typeChanged(_:))
        typePicker.setAccessibilityLabel("Property type")
        let grid = NSGridView(views: [[keyLabel, keyField], [typeLabel, typePicker]])
        grid.column(at: 0).width = 48; grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .leading; grid.column(at: 1).xPlacement = .fill
        let valueLabel = NSTextField(labelWithString: "Value")
        valueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        value.isRichText = false; value.isAutomaticQuoteSubstitutionEnabled = false; value.isAutomaticDashSubstitutionEnabled = false
        value.isAutomaticTextReplacementEnabled = false; value.isAutomaticSpellingCorrectionEnabled = false
        value.isContinuousSpellCheckingEnabled = false
        value.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        value.textContainerInset = NSSize(width: 10, height: 10)
        value.isVerticallyResizable = true; value.isHorizontallyResizable = false
        value.autoresizingMask = [.width]
        value.textContainer?.widthTracksTextView = true
        value.setAccessibilityLabel("Property value")
        scroll.documentView = value
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        error.font = .systemFont(ofSize: 11); error.textColor = .systemRed
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:))); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: isNew ? "Add Item" : "Apply", target: self, action: #selector(apply(_:))); save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        for view in [title, grid, valueLabel, scroll, hint, error, cancel, save] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 22), title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20), grid.leadingAnchor.constraint(equalTo: title.leadingAnchor), grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            valueLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20), valueLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 7), scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: grid.trailingAnchor), scroll.heightAnchor.constraint(equalToConstant: 150),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8), hint.leadingAnchor.constraint(equalTo: title.leadingAnchor), hint.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            error.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 7), error.leadingAnchor.constraint(equalTo: title.leadingAnchor), error.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            save.trailingAnchor.constraint(equalTo: grid.trailingAnchor), save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8), cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor)
        ])
        value.string = node.kind.isContainer ? "" : node.text
        updateHint()
    }

    @objc func typeChanged(_ sender: Any?) {
        drafts[draftKind] = value.string
        draftKind = PlistKind(rawValue: typePicker.titleOfSelectedItem!)!
        value.string = drafts[draftKind] ?? (draftKind == node.kind ? node.text : PlistNode.empty(draftKind).text)
        if draftKind.isContainer { value.string = "" }
        error.stringValue = ""
        updateHint()
    }
    func updateHint() {
        value.isEditable = !draftKind.isContainer
        value.backgroundColor = draftKind.isContainer ? .controlBackgroundColor : .textBackgroundColor
        switch draftKind {
        case .dictionary: hint.stringValue = "A collection of unique keys. Add child properties from the main window."
        case .array: hint.stringValue = "An ordered collection. Use Edit → Move Item Up / Down to reorder children."
        case .string: hint.stringValue = "Plain text. Line breaks and whitespace are preserved."
        case .integer: hint.stringValue = "A whole number, such as 42 or −7."
        case .real: hint.stringValue = "A decimal number, such as 3.14 or 1.5e3."
        case .boolean: hint.stringValue = "Enter true or false."
        case .date: hint.stringValue = "ISO 8601 with a time zone, e.g. 2026-01-01T12:00:00Z. Displayed in UTC."
        case .data: hint.stringValue = "Hexadecimal bytes, e.g. DE AD BE EF. Whitespace is optional."
        }
        if node.kind.isContainer && node.kind != draftKind && !node.children.isEmpty {
            hint.stringValue += draftKind.isContainer ? " Changing collection type will change child keys." : " Applying this type will remove the current child items."
        }
    }
    @objc func cancel(_ sender: Any?) { panel.sheetParent?.endSheet(panel, returnCode: .cancel) }
    @objc func apply(_ sender: Any?) {
        let key = parent?.kind == .dictionary ? keyField.stringValue : node.key
        if parent?.kind == .dictionary, parent!.children.contains(where: { $0 !== node && $0.key == key }) {
            error.stringValue = "This dictionary already has a property named “\(key)”. Choose a unique key."
            panel.makeFirstResponder(keyField); return
        }
        do {
            let scalar = draftKind == node.kind && value.string == node.text ? node.scalar : try PlistNode.parse(value.string, as: draftKind)
            if !isNew && key == node.key && draftKind == node.kind && (draftKind.isContainer || value.string == node.text) { cancel(nil); return }
            editor.plist.change(isNew ? "Add Item" : "Edit Item") {
                if node.kind != draftKind {
                    if node.kind.isContainer && draftKind.isContainer {
                        if draftKind == .dictionary {
                            for (index, child) in node.children.enumerated() { child.key = "Item \(index)" }
                        }
                    } else { node.children = [] }
                }
                node.key = key; node.kind = draftKind; node.scalar = scalar
                if isNew, let parent { node.parent = parent; parent.children.append(node) }
            }
            editor.search.stringValue = ""; editor.reload(); editor.select(node)
            panel.sheetParent?.endSheet(panel, returnCode: .OK)
            editor.window?.makeFirstResponder(editor.outline)
        } catch { self.error.stringValue = error.localizedDescription }
    }
}
