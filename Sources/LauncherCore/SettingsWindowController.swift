import AppKit

@MainActor
public final class SettingsWindowController: NSWindowController {
    public var onSave: (() -> Void)?
    let dshField = NSTextField()
    let workspaceField = NSTextField()
    let serverURLField = NSTextField()
    let errorLabel = NSTextField(labelWithString: "")
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 295),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Settings"
        window.center()
        buildContent()
        let settings = store.load()
        dshField.stringValue = settings.dshPath ?? ""
        workspaceField.stringValue = settings.workspacePath
        serverURLField.stringValue = settings.existingServerURL ?? ""
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    private func buildContent() {
        guard let window else { return }
        let intro = NSTextField(labelWithString: "Choose how the launcher finds dsh and its web server.")
        intro.font = .systemFont(ofSize: 14)

        dshField.placeholderString = "Automatically find dsh"
        workspaceField.placeholderString = "~/.dsh/workspace"
        serverURLField.placeholderString = "Optional token URL for a server started elsewhere"
        dshField.setAccessibilityLabel("dsh executable")
        workspaceField.setAccessibilityLabel("Workspace directory")
        serverURLField.setAccessibilityLabel("Existing server URL")

        let dshBrowse = NSButton(title: "Browse…", target: self, action: #selector(browseDsh(_:)))
        let workspaceBrowse = NSButton(title: "Browse…", target: self, action: #selector(browseWorkspace(_:)))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "dsh executable"), dshField, dshBrowse],
            [NSTextField(labelWithString: "Workspace"), workspaceField, workspaceBrowse],
            [NSTextField(labelWithString: "Existing server URL"), serverURLField, NSView()]
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 14
        grid.column(at: 0).width = 125
        grid.column(at: 2).width = 85

        let note = NSTextField(wrappingLabelWithString:
            "Leave the URL empty for automatic discovery. Token URLs are saved in your Keychain.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, save])
        buttons.spacing = 10
        buttons.alignment = .centerY
        let stack = NSStackView(views: [intro, grid, note, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    @objc func save(_ sender: Any?) {
        let settings = LauncherSettings(
            dshPath: dshField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            workspacePath: workspaceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            existingServerURL: serverURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try store.save(settings)
            errorLabel.stringValue = ""
            close()
            onSave?()
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func cancel(_ sender: Any?) { close() }

    @objc private func browseDsh(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window!) { [weak self] result in
            if result == .OK { self?.dshField.stringValue = panel.url?.path ?? "" }
        }
    }

    @objc private func browseWorkspace(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.beginSheetModal(for: window!) { [weak self] result in
            if result == .OK { self?.workspaceField.stringValue = panel.url?.path ?? "" }
        }
    }
}
