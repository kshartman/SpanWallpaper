import AppKit

final class AboutPanel {
    static let shared = AboutPanel()
    private var panel: NSPanel?

    func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        p.title = "About SpanWallpaper"
        p.isReleasedWhenClosed = false
        p.center()

        let content = NSView(frame: p.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        let nameLabel = NSTextField(labelWithString: "SpanWallpaper")
        nameLabel.font = .boldSystemFont(ofSize: 16)
        nameLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: "Version \(BuildInfo.version)")
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let dateLabel = NSTextField(labelWithString: "Built \(BuildInfo.date)")
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .tertiaryLabelColor
        dateLabel.alignment = .center

        let descLabel = NSTextField(labelWithString: "Multi-monitor wallpaper manager")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center

        let copyrightLabel = NSTextField(labelWithString: "\u{00A9} 2026 Shane Hartman — MIT License")
        copyrightLabel.font = .systemFont(ofSize: 10)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center

        let stack = NSStackView(views: [nameLabel, versionLabel, dateLabel, descLabel, copyrightLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        p.contentView = content
        panel = p
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
