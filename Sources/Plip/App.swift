import AppKit
import UniformTypeIdentifiers

#if !TESTING
@main
enum PlipApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var welcome: WelcomeController?

    func showWelcome() {
        if welcome == nil { welcome = WelcomeController() }
        welcome?.showWindow(nil)
        welcome?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func documentBecameMain(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.windowController?.document is NSDocument {
            welcome?.close()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(documentBecameMain(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        if let url = Bundle.main.url(forResource: "PlipIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item)
            return submenu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            menu.addItem(item)
        }
        let app = menu("Plip")
        add(app, "About Plip", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services"); app.addItem(services)
        NSApp.servicesMenu = services.submenu
        app.addItem(.separator())
        add(app, "Hide Plip", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Plip", #selector(NSApplication.terminate(_:)), "q")

        let file = menu("File")
        add(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        add(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self
        recent.submenu = recentMenu; file.addItem(recent)
        add(recentMenu, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        file.addItem(.separator())
        add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(file, "Save", #selector(NSDocument.save(_:)), "s")
        add(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        add(file, "Revert to Saved…", #selector(NSDocument.revertToSaved(_:)))

        let edit = menu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, "Edit Item…", #selector(EditorController.editItem(_:)), "e")
        add(edit, "Add Item…", #selector(EditorController.addItem(_:)), "=", .command)
        add(edit, "Duplicate Item", #selector(EditorController.duplicateItem(_:)), "d")
        add(edit, "Delete Item", #selector(EditorController.deleteItem(_:)), "\u{8}", .command)
        add(edit, "Move Item Up", #selector(EditorController.moveItemUp(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option])
        add(edit, "Move Item Down", #selector(EditorController.moveItemDown(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option])

        let view = menu("View")
        add(view, "Expand All", #selector(EditorController.expandAll(_:)))
        add(view, "Collapse All", #selector(EditorController.collapseAll(_:)))
        add(view, "Find…", #selector(EditorController.focusSearch(_:)), "f")
        let window = menu("Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url; item.target = self; item.toolTip = url.path
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
    }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { showWelcome(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }
}

@objc(PlistDocument)
final class PlistDocument: NSDocument {
    var root = PlistNode.empty(.dictionary, key: "Root")
    var format: PropertyListSerialization.PropertyListFormat = .xml
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        let controller = EditorController(document: self)
        addWindowController(controller)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        var detected = PropertyListSerialization.PropertyListFormat.xml
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: &detected)
        root = try PlistNode.decode(value)
        format = detected == .binary ? .binary : .xml
        for controller in windowControllers { (controller as? EditorController)?.reload() }
    }

    override func data(ofType typeName: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: root.object(), format: format, options: 0)
    }

    func change(_ name: String, _ edit: () -> Void) {
        let previous = root.copyTree(), previousFormat = format
        undoManager?.registerUndo(withTarget: self) { target in target.restore(previous, format: previousFormat, action: name) }
        undoManager?.setActionName(name)
        edit()
        for controller in windowControllers { (controller as? EditorController)?.reload() }
    }

    private func restore(_ previous: PlistNode, format previousFormat: PropertyListSerialization.PropertyListFormat, action: String) {
        change(action) { root = previous.copyTree(); format = previousFormat }
    }
}

final class EditorController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    let plist: PlistDocument
    let outline = PropertyOutlineView()
    let search = NSSearchField()
    let status = NSTextField(labelWithString: "")
    let formatPicker = NSPopUpButton()
    let editButton = NSButton(title: "Edit Value", target: nil, action: nil)
    let removeButton = NSButton()
    var query: String { search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    var selected: PlistNode? { outline.item(atRow: outline.selectedRow) as? PlistNode }

    init(document: PlistDocument) {
        self.plist = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 740, height: 440)
        window.title = "Untitled"
        window.subtitle = "Property List Editor"
        window.center()
        super.init(window: window)
        buildUI()
        reload()
        outline.expandItem(plist.root)
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.initialFirstResponder = outline
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func buildUI() {
        guard let content = window?.contentView else { return }
        let header = NSView()
        let title = NSTextField(labelWithString: "Property List")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Select an item to edit its key, type, and value.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12)
        let titles = NSStackView(views: [title, subtitle]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 5
        search.placeholderString = "Filter keys and values"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Filter property list")

        let add = NSButton(title: "Add Item", image: NSImage(systemSymbolName: "plus", accessibilityDescription: nil)!, target: self, action: #selector(addItem(_:)))
        add.bezelStyle = .rounded
        editButton.target = self; editButton.action = #selector(editItem(_:)); editButton.bezelStyle = .rounded
        editButton.setAccessibilityLabel("Edit Value")
        editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        editButton.imagePosition = .imageLeading
        removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete item")
        removeButton.target = self; removeButton.action = #selector(deleteItem(_:)); removeButton.bezelStyle = .rounded
        removeButton.toolTip = "Delete selected item (⌘⌫)"
        let actions = NSStackView(views: [add, editButton, removeButton]); actions.spacing = 8
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        outline.style = .fullWidth
        outline.rowHeight = 34; outline.intercellSpacing = NSSize(width: 12, height: 2)
        outline.usesAlternatingRowBackgroundColors = true
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.allowsMultipleSelection = false
        outline.autosaveName = "PlipTreeColumns"; outline.autosaveTableColumns = true
        for (id, label, width) in [("key", "Key", 300.0), ("type", "Type", 130.0), ("value", "Value", 480.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = label; column.width = width; column.minWidth = 90
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.dataSource = self; outline.delegate = self
        outline.target = self; outline.doubleAction = #selector(editItem(_:))
        outline.setAccessibilityLabel("Property list tree")
        scroll.documentView = outline
        let context = NSMenu()
        for (title, action) in [("Edit Item…", #selector(editItem(_:))), ("Add Item…", #selector(addItem(_:))), ("Duplicate Item", #selector(duplicateItem(_:))), ("Delete Item", #selector(deleteItem(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; context.addItem(item)
        }
        outline.menu = context
        let footer = NSView()
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 11)
        let formatLabel = NSTextField(labelWithString: "Save format")
        formatLabel.font = .systemFont(ofSize: 11); formatLabel.textColor = .secondaryLabelColor
        formatPicker.addItems(withTitles: ["XML", "Binary"])
        formatPicker.controlSize = .small; formatPicker.target = self; formatPicker.action = #selector(changeFormat(_:))
        formatPicker.setAccessibilityLabel("Save format")
        formatPicker.toolTip = "Existing XML and binary formats are preserved unless you change this setting."
        let line = NSBox(); line.boxType = .separator
        for view in [header, scroll, footer, line] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        for view in [titles, search, actions] { view.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(view) }
        for view in [status, formatLabel, formatPicker] { view.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(view) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor), header.leadingAnchor.constraint(equalTo: content.leadingAnchor), header.trailingAnchor.constraint(equalTo: content.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 116),
            titles.topAnchor.constraint(equalTo: header.topAnchor, constant: 20), titles.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            search.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24), search.centerYAnchor.constraint(equalTo: titles.centerYAnchor), search.widthAnchor.constraint(equalToConstant: 260),
            actions.leadingAnchor.constraint(equalTo: titles.leadingAnchor), actions.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            line.topAnchor.constraint(equalTo: header.bottomAnchor), line.leadingAnchor.constraint(equalTo: content.leadingAnchor), line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor), footer.leadingAnchor.constraint(equalTo: content.leadingAnchor), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor), footer.heightAnchor.constraint(equalToConstant: 38),
            status.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24), status.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            formatPicker.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20), formatPicker.centerYAnchor.constraint(equalTo: footer.centerYAnchor), formatPicker.widthAnchor.constraint(equalToConstant: 86),
            formatLabel.trailingAnchor.constraint(equalTo: formatPicker.leadingAnchor, constant: -8), formatLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    func matches(_ node: PlistNode) -> Bool {
        query.isEmpty || node.displayKey.localizedCaseInsensitiveContains(query) || node.displayText.localizedCaseInsensitiveContains(query) || node.text.localizedCaseInsensitiveContains(query) || node.children.contains(where: matches)
    }
    func visibleChildren(_ node: PlistNode?) -> [PlistNode] {
        let children = node?.children ?? [plist.root]
        return query.isEmpty ? children : children.filter(matches)
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { visibleChildren(item as? PlistNode).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { visibleChildren(item as? PlistNode)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? PlistNode)?.kind.isContainer == true }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? PlistNode, let column = tableColumn else { return nil }
        let id = column.identifier
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: id.rawValue == "key" ? node.displayKey : id.rawValue == "type" ? node.kind.rawValue : node.displayText)
        field.lineBreakMode = .byTruncatingTail
        field.font = id.rawValue == "value" && [.integer, .real, .data, .date].contains(node.kind) ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13, weight: id.rawValue == "key" && node.kind.isContainer ? .medium : .regular)
        field.textColor = id.rawValue == "type" || node.kind.isContainer && id.rawValue == "value" ? .secondaryLabelColor : .labelColor
        field.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(field); cell.textField = field
        cell.toolTip = field.stringValue
        var leading: CGFloat = 2
        if id.rawValue == "key" {
            let icon = NSImageView(image: NSImage(systemSymbolName: node.kind.symbol, accessibilityDescription: node.kind.rawValue) ?? NSImage())
            icon.contentTintColor = node.kind.isContainer ? .controlAccentColor : .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(icon); cell.imageView = icon
            NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), icon.widthAnchor.constraint(equalToConstant: 17), icon.heightAnchor.constraint(equalToConstant: 17), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            leading = 28
        }
        NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading), field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) { updateStatus() }
    func controlTextDidChange(_ obj: Notification) { reload(); if !query.isEmpty { outline.expandItem(nil, expandChildren: true) } }
    func reload() {
        let selectionID = selected?.id
        var expanded = Set<UUID>()
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? PlistNode, outline.isItemExpanded(node) { expanded.insert(node.id) }
        }
        outline.reloadData()
        var restoredSelection: PlistNode?
        func restore(_ node: PlistNode) {
            if expanded.contains(node.id) || node === plist.root { outline.expandItem(node) }
            if node.id == selectionID { restoredSelection = node }
            for child in node.children { restore(child) }
        }
        restore(plist.root)
        select(restoredSelection ?? plist.root)
        formatPicker.selectItem(at: plist.format == .binary ? 1 : 0)
        updateStatus()
    }
    func updateStatus() {
        let total = plist.root.descendantCount
        status.stringValue = "\(total) \(total == 1 ? "item" : "items")" + (selected.map { "  •  \($0.displayKey) · \($0.kind.rawValue)" } ?? "")
        editButton.isEnabled = selected != nil
        removeButton.isEnabled = selected?.parent != nil
    }
    func select(_ node: PlistNode) {
        var parents: [PlistNode] = []; var parent = node.parent
        while let current = parent { parents.append(current); parent = current.parent }
        for ancestor in parents.reversed() { outline.expandItem(ancestor) }
        let row = outline.row(forItem: node)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); outline.scrollRowToVisible(row) }
    }
    var actionNode: PlistNode? { selected }
    @objc func editItem(_ sender: Any?) {
        guard let node = actionNode else { return }
        ItemEditor.present(node: node, parent: node.parent, in: self, isNew: false)
    }
    @objc func addItem(_ sender: Any?) {
        let node = actionNode ?? plist.root
        guard let parent = node.kind.isContainer ? node : node.parent else { NSSound.beep(); return }
        let child = PlistNode.empty(.string, key: parent.availableKey("New Item"))
        ItemEditor.present(node: child, parent: parent, in: self, isNew: true)
    }
    @objc func duplicateItem(_ sender: Any?) {
        guard let node = actionNode, let parent = node.parent, let index = parent.children.firstIndex(where: { $0 === node }) else { return }
        let copy = node.copyTree(preservingIdentity: false); copy.key = parent.availableKey(node.key + " Copy"); copy.parent = parent
        plist.change("Duplicate Item") { parent.children.insert(copy, at: index + 1) }
        select(copy)
    }
    @objc func deleteItem(_ sender: Any?) {
        guard let node = actionNode, let parent = node.parent else { return }
        plist.change("Delete Item") { parent.children.removeAll { $0 === node } }
        select(parent)
    }
    @objc func moveItemUp(_ sender: Any?) { move(-1) }
    @objc func moveItemDown(_ sender: Any?) { move(1) }
    func move(_ offset: Int) {
        guard let node = selected, let parent = node.parent, parent.kind == .array, let index = parent.children.firstIndex(where: { $0 === node }), parent.children.indices.contains(index + offset) else { return }
        plist.change("Move Item") { parent.children.swapAt(index, index + offset) }
        select(node)
    }
    @objc func expandAll(_ sender: Any?) { outline.expandItem(nil, expandChildren: true) }
    @objc func collapseAll(_ sender: Any?) { outline.collapseItem(nil, collapseChildren: true); outline.expandItem(plist.root) }
    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search) }
    @objc func changeFormat(_ sender: Any?) {
        let format: PropertyListSerialization.PropertyListFormat = formatPicker.indexOfSelectedItem == 1 ? .binary : .xml
        guard format != plist.format else { return }
        plist.change("Change Save Format") { plist.format = format }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(deleteItem(_:)), #selector(duplicateItem(_:)): return actionNode?.parent != nil
        case #selector(editItem(_:)): return actionNode != nil
        case #selector(addItem(_:)): return (actionNode ?? plist.root).kind.isContainer || actionNode?.parent != nil
        case #selector(moveItemUp(_:)), #selector(moveItemDown(_:)):
            guard let node = selected, let parent = node.parent, parent.kind == .array, let index = parent.children.firstIndex(where: { $0 === node }) else { return false }
            return parent.children.indices.contains(index + (menuItem.action == #selector(moveItemUp(_:)) ? -1 : 1))
        default: return true
        }
    }
}

final class PropertyOutlineView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return super.menu(for: event)
    }
}
