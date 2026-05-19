import AppKit
import SpanWallpaperLib

class DropZoneView: NSView {
    var isDragHighlighted = false
    var onDrop: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isDragHighlighted
            ? NSColor.controlBackgroundColor.blended(withFraction: 0.1, of: .white) ?? .controlBackgroundColor
            : NSColor.controlBackgroundColor
        bg.setFill()
        bounds.fill()

        let inset = bounds.insetBy(dx: 16, dy: 12)
        let dash = NSBezierPath(roundedRect: inset, xRadius: 12, yRadius: 12)
        dash.lineWidth = 2
        let pattern: [CGFloat] = [6, 5]
        dash.setLineDash(pattern, count: 2, phase: 0)
        (isDragHighlighted
            ? NSColor.controlAccentColor
            : NSColor.separatorColor
        ).setStroke()
        dash.stroke()

        let text = "Drop image or folder"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: isDragHighlighted
                ? NSColor.controlAccentColor
                : NSColor.secondaryLabelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func droppedFileURLs(from info: NSDraggingInfo) -> [URL] {
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return [] }
        return urls
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = droppedFileURLs(from: sender)
        let valid = urls.contains { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue || imageExtensions.contains(url.pathExtension.lowercased())
        }
        isDragHighlighted = valid
        needsDisplay = true
        return valid ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        needsDisplay = true
        let urls = droppedFileURLs(from: sender)
        guard let url = urls.first else { return false }
        onDrop?(url)
        return true
    }
}

class PreferencesController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    private let dropZone = DropZoneView(frame: .zero)
    private let pathLabel = NSTextField(labelWithString: "No selection")
    private let browseButton = NSButton(title: "Choose...", target: nil, action: nil)
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalLabel = NSTextField(labelWithString: "Rotate:")
    private let playModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let playModeLabel = NSTextField(labelWithString: "Order:")
    private let displayModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let displayModeLabel = NSTextField(labelWithString: "Display:")
    private let appearanceLabel = NSTextField(labelWithString: "Theme:")
    private let appearanceSegment = NSSegmentedControl(labels: ["System", "Dark", "Light"], trackingMode: .selectOne, target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let retireButton = NSButton(title: "Retire", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop Rotation", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let separator = NSBox()

    private let filterToggle = NSButton(title: "\u{25B6}  Filters", target: nil, action: nil)
    private let filterContainer = NSView()
    private let recursiveCheckbox = NSButton(checkboxWithTitle: "Scan subfolders", target: nil, action: nil)
    private let excludeLabel = NSTextField(labelWithString: "Exclude:")
    private let excludeFixedTag = NSTextField(labelWithString: "retired")
    private let excludePlusLabel = NSTextField(labelWithString: "+")
    private let excludeField = NSTextField()
    private let minSizeLabel = NSTextField(labelWithString: "Min size:")
    private let minWidthField = NSTextField()
    private let minWidthSuffix = NSTextField(labelWithString: "W")
    private let minSizeX = NSTextField(labelWithString: "\u{00D7}")
    private let minHeightField = NSTextField()
    private let minHeightSuffix = NSTextField(labelWithString: "H")
    private let maxSizeLabel = NSTextField(labelWithString: "Max size:")
    private let maxWidthField = NSTextField()
    private let maxWidthSuffix = NSTextField(labelWithString: "W")
    private let maxSizeX = NSTextField(labelWithString: "\u{00D7}")
    private let maxHeightField = NSTextField()
    private let maxHeightSuffix = NSTextField(labelWithString: "H")

    private let cacheToggle = NSButton(title: "\u{25B6}  Cache", target: nil, action: nil)
    private let cacheContainer = NSView()
    private let autoClearCheckbox = NSButton(checkboxWithTitle: "Auto-clear wallpaper cache on rotation", target: nil, action: nil)
    private let cacheButton = NSButton(title: "Clear Cache Now", target: nil, action: nil)

    private let displaysToggle = NSButton(title: "\u{25B6}  Displays", target: nil, action: nil)
    private let displaysContainer = NSView()
    private let debugCheckbox = NSButton(checkboxWithTitle: "Debug log", target: nil, action: nil)
    private let display1Label = NSTextField(labelWithString: "1:")
    private let display1Path = NSTextField(labelWithString: "Not set")
    private let display1Button = NSButton(title: "Choose...", target: nil, action: nil)
    private let display1Clear = NSButton(title: "\u{2715}", target: nil, action: nil)
    private let display2Label = NSTextField(labelWithString: "2:")
    private let display2Path = NSTextField(labelWithString: "Not set")
    private let display2Button = NSButton(title: "Choose...", target: nil, action: nil)
    private let display2Clear = NSButton(title: "\u{2715}", target: nil, action: nil)
    private let display3Label = NSTextField(labelWithString: "3:")
    private let display3Path = NSTextField(labelWithString: "Not set")
    private let display3Button = NSButton(title: "Choose...", target: nil, action: nil)
    private let display3Clear = NSButton(title: "\u{2715}", target: nil, action: nil)

    private var filtersExpanded = false
    private var cacheExpanded = false
    private var displaysExpanded = false
    private var filterContainerHeight: NSLayoutConstraint!
    private var cacheContainerHeight: NSLayoutConstraint!
    private var displaysContainerHeight: NSLayoutConstraint!
    private var selectedPath: String?
    private var selectedIsFolder = false

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "SpanWallpaper"
        window.center()
        window.isReleasedWhenClosed = false

        let content = window.contentView!
        content.wantsLayer = true

        for v: NSView in [dropZone, pathLabel, browseButton, intervalLabel,
                          intervalPopup, playModeLabel, playModePopup,
                          displayModeLabel, displayModePopup,
                          appearanceLabel, appearanceSegment,
                          filterToggle, filterContainer,
                          cacheToggle, cacheContainer,
                          displaysToggle, displaysContainer,
                          debugCheckbox,
                          applyButton, nextButton, backButton, retireButton, stopButton,
                          statusLabel, separator] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        for v: NSView in [recursiveCheckbox, excludeLabel, excludeFixedTag, excludePlusLabel, excludeField,
                          minSizeLabel, minWidthField, minWidthSuffix, minSizeX, minHeightField, minHeightSuffix,
                          maxSizeLabel, maxWidthField, maxWidthSuffix, maxSizeX, maxHeightField, maxHeightSuffix] {
            v.translatesAutoresizingMaskIntoConstraints = false
            filterContainer.addSubview(v)
        }

        for v: NSView in [autoClearCheckbox, cacheButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cacheContainer.addSubview(v)
        }

        for v: NSView in [display1Label, display1Path, display1Button, display1Clear,
                          display2Label, display2Path, display2Button, display2Clear,
                          display3Label, display3Path, display3Button, display3Clear] {
            v.translatesAutoresizingMaskIntoConstraints = false
            displaysContainer.addSubview(v)
        }

        setupDropZone()
        setupPathRow()
        setupSeparator()
        setupIntervalRow()
        setupDisplayRow()
        setupAppearanceRow()
        setupFilterSection()
        setupCacheSection()
        setupDisplaysSection()
        setupDebugRow()
        setupActionRow()
        setupStatusRow()
        layoutConstraints()

        NotificationCenter.default.addObserver(self, selector: #selector(externalSyncUI),
                                               name: .spanWallpaperSyncUI, object: nil)
        syncUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func externalSyncUI() {
        syncUI()
    }

    private func setupDropZone() {
        dropZone.onDrop = { [weak self] url in self?.handleFile(url) }
    }

    private func setupPathRow() {
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.maximumNumberOfLines = 1

        browseButton.target = self
        browseButton.action = #selector(browseTapped)
        browseButton.bezelStyle = .rounded
        browseButton.controlSize = .regular
    }

    private func setupSeparator() {
        separator.boxType = .separator
    }

    private func setupIntervalRow() {
        intervalLabel.textColor = .secondaryLabelColor
        intervalLabel.font = NSFont.systemFont(ofSize: 13)

        intervalPopup.removeAllItems()
        for preset in IntervalPreset.all {
            intervalPopup.addItem(withTitle: preset.title)
        }
        let savedInterval = RotationManager.shared.config?.intervalSeconds ?? AppConfig.defaultInterval
        intervalPopup.selectItem(at: IntervalPreset.indexForSeconds(savedInterval))

        playModeLabel.textColor = .secondaryLabelColor
        playModeLabel.font = NSFont.systemFont(ofSize: 13)

        playModePopup.removeAllItems()
        playModePopup.addItem(withTitle: "Shuffle")
        playModePopup.addItem(withTitle: "Sequential")
        let savedMode = RotationManager.shared.config?.playMode ?? .shuffle
        playModePopup.selectItem(at: savedMode == .shuffle ? 0 : 1)
        playModePopup.target = self
        playModePopup.action = #selector(playModeChanged)
    }

    private func setupDisplayRow() {
        displayModeLabel.textColor = .secondaryLabelColor
        displayModeLabel.font = NSFont.systemFont(ofSize: 13)

        displayModePopup.removeAllItems()
        displayModePopup.addItem(withTitle: "Span (all monitors)")
        displayModePopup.addItem(withTitle: "Fit (letterbox)")
        displayModePopup.addItem(withTitle: "Fill (crop)")
        let savedDisplay = RotationManager.shared.config?.displayMode ?? .span
        switch savedDisplay {
        case .span: displayModePopup.selectItem(at: 0)
        case .fit: displayModePopup.selectItem(at: 1)
        case .fill: displayModePopup.selectItem(at: 2)
        }
        displayModePopup.target = self
        displayModePopup.action = #selector(displayModeChanged)
    }

    private func setupAppearanceRow() {
        appearanceLabel.textColor = .secondaryLabelColor
        appearanceLabel.font = NSFont.systemFont(ofSize: 13)

        let config = RotationManager.shared.config ?? AppConfig()
        switch config.appearanceMode {
        case .system: appearanceSegment.selectedSegment = 0
        case .dark: appearanceSegment.selectedSegment = 1
        case .light: appearanceSegment.selectedSegment = 2
        }
        appearanceSegment.target = self
        appearanceSegment.action = #selector(appearanceChanged)
        applyAppearance(config.appearanceMode)
    }

    @objc private func appearanceChanged() {
        let mode: AppearanceMode
        switch appearanceSegment.selectedSegment {
        case 1: mode = .dark
        case 2: mode = .light
        default: mode = .system
        }
        applyAppearance(mode)
        if RotationManager.shared.config == nil {
            RotationManager.shared.config = AppConfig()
        }
        RotationManager.shared.config?.appearanceMode = mode
        RotationManager.shared.config?.save()
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: window.appearance = nil
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        case .light: window.appearance = NSAppearance(named: .aqua)
        }
    }

    private func setupFilterSection() {
        filterToggle.isBordered = false
        filterToggle.setButtonType(.momentaryPushIn)
        filterToggle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        filterToggle.contentTintColor = .secondaryLabelColor
        filterToggle.alignment = .left
        filterToggle.target = self
        filterToggle.action = #selector(filterToggleTapped)

        filterContainer.isHidden = true
        filterContainerHeight = filterContainer.heightAnchor.constraint(equalToConstant: 0)
        filterContainerHeight.isActive = true

        recursiveCheckbox.target = self
        recursiveCheckbox.action = #selector(filterChanged)
        recursiveCheckbox.contentTintColor = .secondaryLabelColor

        let dimLabels: [NSTextField] = [excludeLabel, excludePlusLabel, minSizeLabel, maxSizeLabel,
                                         minWidthSuffix, minHeightSuffix, maxWidthSuffix, maxHeightSuffix,
                                         minSizeX, maxSizeX]
        for label in dimLabels {
            label.textColor = .tertiaryLabelColor
            label.font = NSFont.systemFont(ofSize: 12)
        }

        excludeFixedTag.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        excludeFixedTag.textColor = .tertiaryLabelColor
        excludeFixedTag.drawsBackground = true
        excludeFixedTag.backgroundColor = .quaternaryLabelColor
        excludeFixedTag.isBordered = false
        excludeFixedTag.isEditable = false
        excludeFixedTag.isSelectable = false
        excludeFixedTag.alignment = .center
        excludeFixedTag.wantsLayer = true
        excludeFixedTag.layer?.cornerRadius = 3

        excludePlusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        for field in [excludeField, minWidthField, minHeightField, maxWidthField, maxHeightField] {
            field.font = NSFont.systemFont(ofSize: 12)
            field.isBordered = true
            field.drawsBackground = true
            field.backgroundColor = .controlBackgroundColor
            field.textColor = .labelColor
            field.focusRingType = .none
        }

        for field in [excludeField, minWidthField, minHeightField, maxWidthField, maxHeightField] {
            field.delegate = self
        }

        excludeField.placeholderString = "temp, old-*"
        minWidthField.placeholderString = "width"
        minHeightField.placeholderString = "height"
        maxWidthField.placeholderString = "width"
        maxHeightField.placeholderString = "height"

        let config = RotationManager.shared.config ?? AppConfig()
        recursiveCheckbox.state = config.recursive ? .on : .off
        let additionalPatterns = config.excludePatterns.filter { $0 != "retired" }
        excludeField.stringValue = additionalPatterns.joined(separator: ", ")
        minWidthField.stringValue = config.minWidth.map(String.init) ?? ""
        minHeightField.stringValue = config.minHeight.map(String.init) ?? ""
        maxWidthField.stringValue = config.maxWidth.map(String.init) ?? ""
        maxHeightField.stringValue = config.maxHeight.map(String.init) ?? ""
    }

    private func activeFilterCount() -> Int {
        let config = RotationManager.shared.config ?? AppConfig()
        var count = 0
        if !config.recursive { count += 1 }
        if config.excludePatterns != ["retired"] { count += 1 }
        if config.minWidth != nil { count += 1 }
        if config.minHeight != nil { count += 1 }
        if config.maxWidth != nil { count += 1 }
        if config.maxHeight != nil { count += 1 }
        return count
    }

    private func updateFilterToggleTitle() {
        let count = activeFilterCount()
        let arrow = filtersExpanded ? "\u{25BC}" : "\u{25B6}"
        filterToggle.title = count > 0 ? "\(arrow)  Filters (\(count) active)" : "\(arrow)  Filters"
    }

    @objc private func filterToggleTapped() {
        filtersExpanded = !filtersExpanded
        let expandedHeight: CGFloat = 140
        let delta = filtersExpanded ? expandedHeight : -expandedHeight

        filterContainer.isHidden = !filtersExpanded
        filterContainerHeight.constant = filtersExpanded ? expandedHeight : 0

        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta
        window.setFrame(frame, display: true, animate: true)
        updateFilterToggleTitle()
    }

    @objc private func filterChanged() {
        saveFiltersToConfig()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        saveFiltersToConfig()
    }

    private func saveFiltersToConfig() {
        var config = RotationManager.shared.config ?? AppConfig()
        config.recursive = recursiveCheckbox.state == .on

        let raw = excludeField.stringValue
        let additional = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "retired" }
        config.excludePatterns = ["retired"] + additional

        config.minWidth = Int(minWidthField.stringValue)
        config.minHeight = Int(minHeightField.stringValue)
        config.maxWidth = Int(maxWidthField.stringValue)
        config.maxHeight = Int(maxHeightField.stringValue)

        RotationManager.shared.config = config
        config.save()

        FolderImageCache.shared.invalidate()
        updateFilterToggleTitle()
        syncUI()
    }

    private func setupCacheSection() {
        cacheToggle.isBordered = false
        cacheToggle.setButtonType(.momentaryPushIn)
        cacheToggle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        cacheToggle.contentTintColor = .secondaryLabelColor
        cacheToggle.alignment = .left
        cacheToggle.target = self
        cacheToggle.action = #selector(cacheToggleTapped)

        cacheContainer.isHidden = true
        cacheContainerHeight = cacheContainer.heightAnchor.constraint(equalToConstant: 0)
        cacheContainerHeight.isActive = true

        autoClearCheckbox.target = self
        autoClearCheckbox.action = #selector(autoClearChanged)
        autoClearCheckbox.contentTintColor = .secondaryLabelColor
        let config = RotationManager.shared.config ?? AppConfig()
        autoClearCheckbox.state = config.autoClearCache ? .on : .off

        cacheButton.target = self
        cacheButton.action = #selector(clearCacheTapped)
        cacheButton.bezelStyle = .rounded
        cacheButton.controlSize = .small
        cacheButton.font = NSFont.systemFont(ofSize: 11)
        cacheButton.contentTintColor = .secondaryLabelColor
    }

    @objc private func cacheToggleTapped() {
        cacheExpanded = !cacheExpanded
        let expandedHeight: CGFloat = 60
        let delta = cacheExpanded ? expandedHeight : -expandedHeight

        cacheContainer.isHidden = !cacheExpanded
        cacheContainerHeight.constant = cacheExpanded ? expandedHeight : 0

        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta
        window.setFrame(frame, display: true, animate: true)
        updateCacheToggleTitle()
    }

    private func updateCacheToggleTitle() {
        let arrow = cacheExpanded ? "\u{25BC}" : "\u{25B6}"
        let config = RotationManager.shared.config ?? AppConfig()
        let suffix = config.autoClearCache ? " (auto)" : ""
        cacheToggle.title = "\(arrow)  Cache\(suffix)"
    }

    @objc private func autoClearChanged() {
        let wantOn = autoClearCheckbox.state == .on
        if wantOn && !WallpaperCache.hasFDA() {
            autoClearCheckbox.state = .off
            promptForFDA()
            return
        }
        var config = RotationManager.shared.config ?? AppConfig()
        config.autoClearCache = wantOn
        config.cacheAccessConfirmed = wantOn
        RotationManager.shared.config = config
        config.save()
        updateCacheToggleTitle()
    }

    @objc private func clearCacheTapped() {
        if !WallpaperCache.hasFDA() {
            promptForFDA()
            return
        }

        let size = WallpaperCache.formattedSize()
        let alert = NSAlert()
        alert.alertStyle = .informational

        if size == "empty" {
            alert.messageText = "macOS Wallpaper Cache"
            alert.informativeText = "The cache is empty. Nothing to clear."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        alert.messageText = "Clear macOS Wallpaper Cache"
        alert.informativeText = "macOS has cached \(size) of wallpaper data. This is safe to delete — macOS will regenerate files as needed."
        alert.addButton(withTitle: "Clear \(size)")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var config = RotationManager.shared.config ?? AppConfig()
        config.cacheAccessConfirmed = true
        RotationManager.shared.config = config
        config.save()

        let deleted = WallpaperCache.purge(keeping: 0)
        if deleted > 0 {
            Log.info("Cleared \(deleted) macOS wallpaper cache files (\(size))")
        }
    }

    private func promptForFDA() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "SpanWallpaper needs Full Disk Access to manage the macOS wallpaper cache.\n\n1. Click the \"+\" button below the app list\n2. Navigate to Applications and select SpanWallpaper\n3. Come back here and try again\n\nThis is a one-time setup."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    private func setupDisplaysSection() {
        displaysToggle.isBordered = false
        displaysToggle.setButtonType(.momentaryPushIn)
        displaysToggle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        displaysToggle.contentTintColor = .secondaryLabelColor
        displaysToggle.alignment = .left
        displaysToggle.target = self
        displaysToggle.action = #selector(displaysToggleTapped)

        displaysContainer.isHidden = true
        displaysContainerHeight = displaysContainer.heightAnchor.constraint(equalToConstant: 0)
        displaysContainerHeight.isActive = true

        let labels = [display1Label, display2Label, display3Label]
        let paths = [display1Path, display2Path, display3Path]
        let buttons = [display1Button, display2Button, display3Button]
        let clears = [display1Clear, display2Clear, display3Clear]

        for label in labels {
            label.textColor = .secondaryLabelColor
            label.font = NSFont.systemFont(ofSize: 12)
        }
        for path in paths {
            path.textColor = .tertiaryLabelColor
            path.font = NSFont.systemFont(ofSize: 11)
            path.lineBreakMode = .byTruncatingMiddle
            path.maximumNumberOfLines = 1
        }
        for btn in buttons {
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.target = self
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for path in paths {
            path.setContentHuggingPriority(.defaultLow, for: .horizontal)
            path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for btn in clears {
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 12)
            btn.contentTintColor = .tertiaryLabelColor
            btn.target = self
        }

        display1Button.action = #selector(display1Browse)
        display2Button.action = #selector(display2Browse)
        display3Button.action = #selector(display3Browse)
        display1Clear.action = #selector(display1ClearTapped)
        display2Clear.action = #selector(display2ClearTapped)
        display3Clear.action = #selector(display3ClearTapped)

        syncDisplaysFolders()
    }

    @objc private func displaysToggleTapped() {
        displaysExpanded = !displaysExpanded
        let expandedHeight: CGFloat = 90
        let delta = displaysExpanded ? expandedHeight : -expandedHeight

        displaysContainer.isHidden = !displaysExpanded
        displaysContainerHeight.constant = displaysExpanded ? expandedHeight : 0

        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta
        window.setFrame(frame, display: true, animate: true)
        updateDisplaysToggleTitle()
    }

    private func updateDisplaysToggleTitle() {
        let arrow = displaysExpanded ? "\u{25BC}" : "\u{25B6}"
        let config = RotationManager.shared.config ?? AppConfig()
        let count = config.monitorFolders?.values.filter({ !$0.isEmpty }).count ?? 0
        let suffix = count > 0 ? " (\(count) set)" : ""
        displaysToggle.title = "\(arrow)  Displays\(suffix)"
    }

    private func syncDisplaysFolders() {
        let config = RotationManager.shared.config ?? AppConfig()
        let folders = config.monitorFolders ?? [:]

        let paths = [display1Path, display2Path, display3Path]
        let clears = [display1Clear, display2Clear, display3Clear]

        for (i, key) in ["1", "2", "3"].enumerated() {
            if let folder = folders[key], !folder.isEmpty {
                paths[i].stringValue = (folder as NSString).lastPathComponent
                paths[i].toolTip = folder
                clears[i].isHidden = false
            } else {
                paths[i].stringValue = "Not set"
                paths[i].toolTip = nil
                clears[i].isHidden = true
            }
        }
        updateDisplaysToggleTitle()
    }

    private func browseForDisplayFolder(count: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose folder for \(count)-display configuration"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        var config = RotationManager.shared.config ?? AppConfig()
        var folders = config.monitorFolders ?? [:]
        folders[String(count)] = url.path
        config.monitorFolders = folders
        RotationManager.shared.config = config
        config.save()
        syncDisplaysFolders()
    }

    private func clearDisplayFolder(count: Int) {
        var config = RotationManager.shared.config ?? AppConfig()
        var folders = config.monitorFolders ?? [:]
        folders.removeValue(forKey: String(count))
        if folders.isEmpty { config.monitorFolders = nil } else { config.monitorFolders = folders }
        RotationManager.shared.config = config
        config.save()
        syncDisplaysFolders()
    }

    @objc private func display1Browse() { browseForDisplayFolder(count: 1) }
    @objc private func display2Browse() { browseForDisplayFolder(count: 2) }
    @objc private func display3Browse() { browseForDisplayFolder(count: 3) }
    @objc private func display1ClearTapped() { clearDisplayFolder(count: 1) }
    @objc private func display2ClearTapped() { clearDisplayFolder(count: 2) }
    @objc private func display3ClearTapped() { clearDisplayFolder(count: 3) }

    private func setupDebugRow() {
        debugCheckbox.target = self
        debugCheckbox.action = #selector(debugToggled)
        debugCheckbox.contentTintColor = .tertiaryLabelColor
        debugCheckbox.font = NSFont.systemFont(ofSize: 11)
        let config = RotationManager.shared.config ?? AppConfig()
        debugCheckbox.state = config.debugLog ? .on : .off
    }

    @objc private func debugToggled() {
        var config = RotationManager.shared.config ?? AppConfig()
        config.debugLog = debugCheckbox.state == .on
        RotationManager.shared.config = config
        config.save()
    }

    private func setupActionRow() {
        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"

        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        nextButton.bezelStyle = .rounded

        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.bezelStyle = .rounded

        retireButton.target = self
        retireButton.action = #selector(retireTapped)
        retireButton.bezelStyle = .rounded
        retireButton.contentTintColor = .systemOrange

        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.bezelStyle = .rounded
        stopButton.contentTintColor = .systemRed
    }

    private func setupStatusRow() {
        statusLabel.textColor = .systemGreen
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
    }

    private func layoutConstraints() {
        let c = window.contentView!
        let m: CGFloat = 20

        NSLayoutConstraint.activate([
            dropZone.topAnchor.constraint(equalTo: c.topAnchor, constant: m),
            dropZone.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            dropZone.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            dropZone.heightAnchor.constraint(equalToConstant: 80),

            browseButton.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 14),
            browseButton.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            browseButton.widthAnchor.constraint(equalToConstant: 90),

            pathLabel.centerYAnchor.constraint(equalTo: browseButton.centerYAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            pathLabel.trailingAnchor.constraint(equalTo: browseButton.leadingAnchor, constant: -10),

            separator.topAnchor.constraint(equalTo: browseButton.bottomAnchor, constant: 14),
            separator.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            separator.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Interval row
            intervalLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 14),
            intervalLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            intervalLabel.widthAnchor.constraint(equalToConstant: 52),

            intervalPopup.centerYAnchor.constraint(equalTo: intervalLabel.centerYAnchor),
            intervalPopup.leadingAnchor.constraint(equalTo: intervalLabel.trailingAnchor, constant: 6),
            intervalPopup.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Play mode row
            playModeLabel.topAnchor.constraint(equalTo: intervalPopup.bottomAnchor, constant: 10),
            playModeLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            playModeLabel.widthAnchor.constraint(equalToConstant: 52),

            playModePopup.centerYAnchor.constraint(equalTo: playModeLabel.centerYAnchor),
            playModePopup.leadingAnchor.constraint(equalTo: playModeLabel.trailingAnchor, constant: 6),
            playModePopup.widthAnchor.constraint(equalToConstant: 130),

            // Display mode (same row as play mode)
            displayModeLabel.centerYAnchor.constraint(equalTo: playModeLabel.centerYAnchor),
            displayModeLabel.leadingAnchor.constraint(equalTo: playModePopup.trailingAnchor, constant: 12),

            displayModePopup.centerYAnchor.constraint(equalTo: displayModeLabel.centerYAnchor),
            displayModePopup.leadingAnchor.constraint(equalTo: displayModeLabel.trailingAnchor, constant: 6),
            displayModePopup.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Appearance row
            appearanceLabel.topAnchor.constraint(equalTo: playModePopup.bottomAnchor, constant: 12),
            appearanceLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            appearanceLabel.widthAnchor.constraint(equalToConstant: 52),

            appearanceSegment.centerYAnchor.constraint(equalTo: appearanceLabel.centerYAnchor),
            appearanceSegment.leadingAnchor.constraint(equalTo: appearanceLabel.trailingAnchor, constant: 6),

            // Filter toggle
            filterToggle.topAnchor.constraint(equalTo: appearanceSegment.bottomAnchor, constant: 12),
            filterToggle.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),

            // Filter container
            filterContainer.topAnchor.constraint(equalTo: filterToggle.bottomAnchor, constant: 8),
            filterContainer.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m + 12),
            filterContainer.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Row 1: Scan subfolders
            recursiveCheckbox.topAnchor.constraint(equalTo: filterContainer.topAnchor, constant: 4),
            recursiveCheckbox.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),

            // Row 2: Exclude -- "retired" tag + additional patterns field
            excludeLabel.topAnchor.constraint(equalTo: recursiveCheckbox.bottomAnchor, constant: 12),
            excludeLabel.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),
            excludeLabel.widthAnchor.constraint(equalToConstant: 55),

            excludeFixedTag.centerYAnchor.constraint(equalTo: excludeLabel.centerYAnchor),
            excludeFixedTag.leadingAnchor.constraint(equalTo: excludeLabel.trailingAnchor, constant: 6),
            excludeFixedTag.widthAnchor.constraint(equalToConstant: 52),
            excludeFixedTag.heightAnchor.constraint(equalToConstant: 20),

            excludePlusLabel.centerYAnchor.constraint(equalTo: excludeLabel.centerYAnchor),
            excludePlusLabel.leadingAnchor.constraint(equalTo: excludeFixedTag.trailingAnchor, constant: 6),

            excludeField.centerYAnchor.constraint(equalTo: excludeLabel.centerYAnchor),
            excludeField.leadingAnchor.constraint(equalTo: excludePlusLabel.trailingAnchor, constant: 6),
            excludeField.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor),
            excludeField.heightAnchor.constraint(equalToConstant: 22),

            // Row 3: Min size -- width W x height H
            minSizeLabel.topAnchor.constraint(equalTo: excludeField.bottomAnchor, constant: 12),
            minSizeLabel.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),
            minSizeLabel.widthAnchor.constraint(equalToConstant: 55),

            minWidthField.centerYAnchor.constraint(equalTo: minSizeLabel.centerYAnchor),
            minWidthField.leadingAnchor.constraint(equalTo: minSizeLabel.trailingAnchor, constant: 6),
            minWidthField.widthAnchor.constraint(equalToConstant: 65),
            minWidthField.heightAnchor.constraint(equalToConstant: 22),

            minWidthSuffix.centerYAnchor.constraint(equalTo: minSizeLabel.centerYAnchor),
            minWidthSuffix.leadingAnchor.constraint(equalTo: minWidthField.trailingAnchor, constant: 3),

            minSizeX.centerYAnchor.constraint(equalTo: minSizeLabel.centerYAnchor),
            minSizeX.leadingAnchor.constraint(equalTo: minWidthSuffix.trailingAnchor, constant: 6),

            minHeightField.centerYAnchor.constraint(equalTo: minSizeLabel.centerYAnchor),
            minHeightField.leadingAnchor.constraint(equalTo: minSizeX.trailingAnchor, constant: 6),
            minHeightField.widthAnchor.constraint(equalToConstant: 65),
            minHeightField.heightAnchor.constraint(equalToConstant: 22),

            minHeightSuffix.centerYAnchor.constraint(equalTo: minSizeLabel.centerYAnchor),
            minHeightSuffix.leadingAnchor.constraint(equalTo: minHeightField.trailingAnchor, constant: 3),

            // Row 4: Max size -- width W x height H
            maxSizeLabel.topAnchor.constraint(equalTo: minSizeLabel.bottomAnchor, constant: 12),
            maxSizeLabel.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),
            maxSizeLabel.widthAnchor.constraint(equalToConstant: 55),

            maxWidthField.centerYAnchor.constraint(equalTo: maxSizeLabel.centerYAnchor),
            maxWidthField.leadingAnchor.constraint(equalTo: maxSizeLabel.trailingAnchor, constant: 6),
            maxWidthField.widthAnchor.constraint(equalToConstant: 65),
            maxWidthField.heightAnchor.constraint(equalToConstant: 22),

            maxWidthSuffix.centerYAnchor.constraint(equalTo: maxSizeLabel.centerYAnchor),
            maxWidthSuffix.leadingAnchor.constraint(equalTo: maxWidthField.trailingAnchor, constant: 3),

            maxSizeX.centerYAnchor.constraint(equalTo: maxSizeLabel.centerYAnchor),
            maxSizeX.leadingAnchor.constraint(equalTo: maxWidthSuffix.trailingAnchor, constant: 6),

            maxHeightField.centerYAnchor.constraint(equalTo: maxSizeLabel.centerYAnchor),
            maxHeightField.leadingAnchor.constraint(equalTo: maxSizeX.trailingAnchor, constant: 6),
            maxHeightField.widthAnchor.constraint(equalToConstant: 65),
            maxHeightField.heightAnchor.constraint(equalToConstant: 22),

            maxHeightSuffix.centerYAnchor.constraint(equalTo: maxSizeLabel.centerYAnchor),
            maxHeightSuffix.leadingAnchor.constraint(equalTo: maxHeightField.trailingAnchor, constant: 3),

            // Cache toggle
            cacheToggle.topAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: 8),
            cacheToggle.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),

            // Cache container
            cacheContainer.topAnchor.constraint(equalTo: cacheToggle.bottomAnchor, constant: 8),
            cacheContainer.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m + 12),
            cacheContainer.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Cache container internals
            autoClearCheckbox.topAnchor.constraint(equalTo: cacheContainer.topAnchor, constant: 4),
            autoClearCheckbox.leadingAnchor.constraint(equalTo: cacheContainer.leadingAnchor),

            cacheButton.topAnchor.constraint(equalTo: autoClearCheckbox.bottomAnchor, constant: 8),
            cacheButton.leadingAnchor.constraint(equalTo: cacheContainer.leadingAnchor),

            // Displays toggle
            displaysToggle.topAnchor.constraint(equalTo: cacheContainer.bottomAnchor, constant: 8),
            displaysToggle.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),

            // Displays container
            displaysContainer.topAnchor.constraint(equalTo: displaysToggle.bottomAnchor, constant: 8),
            displaysContainer.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m + 12),
            displaysContainer.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Displays row 1: label → button → path → clear
            display1Label.topAnchor.constraint(equalTo: displaysContainer.topAnchor, constant: 4),
            display1Label.leadingAnchor.constraint(equalTo: displaysContainer.leadingAnchor),
            display1Label.widthAnchor.constraint(equalToConstant: 18),

            display1Button.centerYAnchor.constraint(equalTo: display1Label.centerYAnchor),
            display1Button.leadingAnchor.constraint(equalTo: display1Label.trailingAnchor, constant: 4),

            display1Path.centerYAnchor.constraint(equalTo: display1Label.centerYAnchor),
            display1Path.leadingAnchor.constraint(equalTo: display1Button.trailingAnchor, constant: 6),
            display1Path.trailingAnchor.constraint(equalTo: display1Clear.leadingAnchor, constant: -4),

            display1Clear.centerYAnchor.constraint(equalTo: display1Label.centerYAnchor),
            display1Clear.trailingAnchor.constraint(equalTo: displaysContainer.trailingAnchor),
            display1Clear.widthAnchor.constraint(equalToConstant: 20),

            // Displays row 2
            display2Label.topAnchor.constraint(equalTo: display1Label.bottomAnchor, constant: 8),
            display2Label.leadingAnchor.constraint(equalTo: displaysContainer.leadingAnchor),
            display2Label.widthAnchor.constraint(equalToConstant: 18),

            display2Button.centerYAnchor.constraint(equalTo: display2Label.centerYAnchor),
            display2Button.leadingAnchor.constraint(equalTo: display2Label.trailingAnchor, constant: 4),

            display2Path.centerYAnchor.constraint(equalTo: display2Label.centerYAnchor),
            display2Path.leadingAnchor.constraint(equalTo: display2Button.trailingAnchor, constant: 6),
            display2Path.trailingAnchor.constraint(equalTo: display2Clear.leadingAnchor, constant: -4),

            display2Clear.centerYAnchor.constraint(equalTo: display2Label.centerYAnchor),
            display2Clear.trailingAnchor.constraint(equalTo: displaysContainer.trailingAnchor),
            display2Clear.widthAnchor.constraint(equalToConstant: 20),

            // Displays row 3
            display3Label.topAnchor.constraint(equalTo: display2Label.bottomAnchor, constant: 8),
            display3Label.leadingAnchor.constraint(equalTo: displaysContainer.leadingAnchor),
            display3Label.widthAnchor.constraint(equalToConstant: 18),

            display3Button.centerYAnchor.constraint(equalTo: display3Label.centerYAnchor),
            display3Button.leadingAnchor.constraint(equalTo: display3Label.trailingAnchor, constant: 4),

            display3Path.centerYAnchor.constraint(equalTo: display3Label.centerYAnchor),
            display3Path.leadingAnchor.constraint(equalTo: display3Button.trailingAnchor, constant: 6),
            display3Path.trailingAnchor.constraint(equalTo: display3Clear.leadingAnchor, constant: -4),

            display3Clear.centerYAnchor.constraint(equalTo: display3Label.centerYAnchor),
            display3Clear.trailingAnchor.constraint(equalTo: displaysContainer.trailingAnchor),
            display3Clear.widthAnchor.constraint(equalToConstant: 20),

            // Debug checkbox
            debugCheckbox.topAnchor.constraint(equalTo: displaysContainer.bottomAnchor, constant: 10),
            debugCheckbox.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Action row
            stopButton.topAnchor.constraint(equalTo: debugCheckbox.bottomAnchor, constant: 10),
            stopButton.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),

            retireButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            retireButton.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 8),

            backButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            backButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),

            nextButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),

            applyButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            applyButton.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            applyButton.widthAnchor.constraint(equalToConstant: 80),

            // Status row
            statusLabel.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            statusLabel.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: c.bottomAnchor, constant: -m),
        ])
    }

    func syncUI() {
        let rm = RotationManager.shared
        let rotating = rm.isActive

        if rotating, let cfg = rm.config, let folderPath = cfg.folderPath {
            selectedPath = folderPath
            selectedIsFolder = true
            intervalPopup.selectItem(at: IntervalPreset.indexForSeconds(cfg.intervalSeconds))
            playModePopup.selectItem(at: cfg.playMode == .shuffle ? 0 : 1)
        }

        if let cfg = rm.config {
            switch cfg.displayMode {
            case .span: displayModePopup.selectItem(at: 0)
            case .fit: displayModePopup.selectItem(at: 1)
            case .fill: displayModePopup.selectItem(at: 2)
            }
            switch cfg.appearanceMode {
            case .system: appearanceSegment.selectedSegment = 0
            case .dark: appearanceSegment.selectedSegment = 1
            case .light: appearanceSegment.selectedSegment = 2
            }
            applyAppearance(cfg.appearanceMode)
        }

        if let path = selectedPath {
            let name = (path as NSString).lastPathComponent
            pathLabel.stringValue = selectedIsFolder ? "\(name)/" : name
            pathLabel.toolTip = path
        } else {
            pathLabel.stringValue = "No selection"
            pathLabel.toolTip = nil
        }

        intervalLabel.isHidden = !selectedIsFolder
        intervalPopup.isHidden = !selectedIsFolder
        playModeLabel.isHidden = !selectedIsFolder
        playModePopup.isHidden = !selectedIsFolder
        let sequential = (RotationManager.shared.config?.playMode ?? .shuffle) == .sequential
        nextButton.isHidden = !rotating
        backButton.isHidden = !rotating || !sequential
        retireButton.isHidden = !rotating
        stopButton.isHidden = !rotating

        updateFilterToggleTitle()
        updateCacheToggleTitle()

        applyButton.isEnabled = selectedPath != nil

        if rotating, let cfg = rm.config, let folderPath = cfg.folderPath {
            if let errMsg = WallpaperSetter.readError() {
                statusLabel.stringValue = "Last rotation error: \(errMsg)"
                statusLabel.textColor = .systemRed
            } else {
                let options = ScanOptions(from: cfg)
                let images = imageFiles(in: URL(fileURLWithPath: folderPath), options: options)
                let presetTitle = IntervalPreset.all[
                    IntervalPreset.indexForSeconds(cfg.intervalSeconds)
                ].title.lowercased()
                let modeName = cfg.playMode == .shuffle ? "shuffle" : "sequential"
                statusLabel.stringValue = "Rotating \(images.count) images, \(presetTitle), \(modeName)"
                statusLabel.textColor = .systemGreen
            }
        } else {
            statusLabel.stringValue = ""
        }

    }

    func handleFile(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            let options = ScanOptions(from: RotationManager.shared.config ?? AppConfig())
            let images = scanImages(in: url, options: options)
            guard !images.isEmpty else {
                showError("No image files found in \(url.lastPathComponent).")
                return
            }
            selectedPath = url.path
            selectedIsFolder = true
            let idx = intervalPopup.indexOfSelectedItem
            let seconds = IntervalPreset.all[idx].seconds
            RotationManager.shared.start(folderPath: url.path, intervalSeconds: seconds,
                                         displayMode: selectedDisplayMode(), playMode: selectedPlayMode())
            syncUI()
        } else if imageExtensions.contains(url.pathExtension.lowercased()) {
            RotationManager.shared.stop()
            selectedPath = url.path
            selectedIsFolder = false
            syncUI()
            applySelection()
        }
    }

    private func applySelection() {
        guard let path = selectedPath else { return }
        saveFiltersToConfig()

        if selectedIsFolder {
            let options = ScanOptions(from: RotationManager.shared.config ?? AppConfig())
            let images = scanImages(in: URL(fileURLWithPath: path), options: options)
            guard !images.isEmpty else {
                showError("No image files in folder.")
                return
            }
            let idx = intervalPopup.indexOfSelectedItem
            let seconds = IntervalPreset.all[idx].seconds
            RotationManager.shared.start(folderPath: path, intervalSeconds: seconds,
                                         displayMode: selectedDisplayMode(), playMode: selectedPlayMode())
            DebugLog.record(action: "apply-folder", image: path)
            syncUI()
        } else {
            RotationManager.shared.stop()
            let displayMode = selectedDisplayMode()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try processImage(at: path, displayMode: displayMode)
                    var cfg = RotationManager.shared.config ?? AppConfig.load() ?? AppConfig()
                    cfg.singleImagePath = path
                    cfg.folderPath = nil
                    cfg.save()
                    RotationManager.shared.config = cfg
                    DebugLog.record(action: "apply-image", image: path)
                    DispatchQueue.main.async { [weak self] in
                        self?.statusLabel.stringValue = "Applied."
                        self?.statusLabel.textColor = .tertiaryLabelColor
                    }
                } catch {
                    DispatchQueue.main.async { showError(error.localizedDescription) }
                }
            }
            syncUI()
        }
    }

    private func selectedDisplayMode() -> DisplayMode {
        switch displayModePopup.indexOfSelectedItem {
        case 1: return .fit
        case 2: return .fill
        default: return .span
        }
    }

    private func selectedPlayMode() -> PlayMode {
        return playModePopup.indexOfSelectedItem == 0 ? .shuffle : .sequential
    }

    @objc private func playModeChanged() {
        if var cfg = RotationManager.shared.config {
            cfg.playMode = selectedPlayMode()
            RotationManager.shared.config = cfg
            cfg.save()
        }
        RotationManager.shared.resetShuffle()
        syncUI()
    }

    @objc private func displayModeChanged() {
        let mode = selectedDisplayMode()
        if var cfg = RotationManager.shared.config {
            cfg.displayMode = mode
            RotationManager.shared.config = cfg
            cfg.save()
        }
        if RotationManager.shared.lastAppliedImagePath != nil {
            DispatchQueue.global(qos: .userInitiated).async {
                RotationManager.shared.reapplyCurrent()
            }
        }
    }

    @objc private func browseTapped() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .folder]
        panel.message = "Choose an image or a folder of images"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleFile(url)
    }

    @objc private func applyTapped() {
        applySelection()
    }

    @objc private func nextTapped() {
        RotationManager.shared.applyNext()
        syncUI()
    }

    @objc private func backTapped() {
        RotationManager.shared.applyPrevious()
        syncUI()
    }

    @objc private func retireTapped() {
        RotationManager.shared.retireCurrent()
        syncUI()
    }

    @objc private func stopTapped() {
        RotationManager.shared.stop()
        selectedPath = nil
        selectedIsFolder = false
        syncUI()
    }
}
