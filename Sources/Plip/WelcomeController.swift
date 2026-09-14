import AppKit

/// A drop carries references to existing files, never imported file contents.
enum PlistFileDrop {
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return [] }
        guard urls.allSatisfy({ url in
            url.isFileURL && url.pathExtension.lowercased() == "plist" &&
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }) else { return [] }
        return urls
    }
}

final class WelcomeController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 480), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Welcome to Plip"
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        super.init(window: window)
        let content = window.contentView!
        let drop = PlistDropView()
        drop.onOpen = { [weak self] in self?.chooseFile(nil) }
        drop.onDrop = { [weak self] urls in self?.open(urls) }
        let title = NSTextField(labelWithString: "Your property lists, made simple.")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Open a plist to explore and edit its contents.")
        subtitle.textColor = .secondaryLabelColor
        let create = NSButton(title: "Create a New Plist", target: self, action: #selector(createNew(_:)))
        create.bezelStyle = .rounded
        for view in [title, subtitle, drop, create] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: content.centerXAnchor), title.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            subtitle.centerXAnchor.constraint(equalTo: content.centerXAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            drop.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 28), drop.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36), drop.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            drop.bottomAnchor.constraint(equalTo: create.topAnchor, constant: -24),
            create.centerXAnchor.constraint(equalTo: content.centerXAnchor), create.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28)
        ])
        window.initialFirstResponder = drop
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func chooseFile(_ sender: Any?) { NSDocumentController.shared.openDocument(sender) }
    @objc func createNew(_ sender: Any?) { NSDocumentController.shared.newDocument(sender) }

    func open(_ urls: [URL]) {
        for url in urls {
            // NSDocumentController retains the original URL and reuses an already-open document.
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
                if let error { NSApp.presentError(error) }
                else if document != nil { self?.close() }
            }
        }
    }
}

final class PlistDropView: NSView {
    var onOpen: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    private var highlighted = false { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open a plist. Drag a plist here or click to choose a file.")
        setAccessibilityHelp("Opens the original file in place.")
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)!)
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "Drag a plist here to edit")
        title.font = .systemFont(ofSize: 20, weight: .medium)
        let link = NSTextField(labelWithString: "or click here to open a plist")
        link.textColor = .controlAccentColor; link.font = .systemFont(ofSize: 14)
        let note = NSTextField(labelWithString: "Opens the original file in its current location.")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [icon, title, link, note])
        stack.orientation = .vertical; stack.spacing = 10
        stack.setCustomSpacing(18, after: icon); stack.setCustomSpacing(16, after: link)
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42), icon.heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { onOpen?() }
    override func accessibilityPerformPress() -> Bool { onOpen?(); return true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.charactersIgnoringModifiers == " " { onOpen?() }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 18, yRadius: 18)
        NSColor.controlAccentColor.withAlphaComponent(highlighted ? 0.14 : 0.045).setFill(); path.fill()
        (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = highlighted ? 2 : 1
        path.setLineDash([7, 5], count: 2, phase: 0); path.stroke()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = !PlistFileDrop.urls(from: sender.draggingPasteboard).isEmpty
        return highlighted ? .link : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !PlistFileDrop.urls(from: sender.draggingPasteboard).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        return acceptDrop(from: sender.draggingPasteboard)
    }
    func acceptDrop(from pasteboard: NSPasteboard) -> Bool {
        let urls = PlistFileDrop.urls(from: pasteboard)
        guard !urls.isEmpty, let onDrop else { return false }
        onDrop(urls)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { highlighted = false }
}
