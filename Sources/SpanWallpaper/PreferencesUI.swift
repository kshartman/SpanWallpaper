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
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(white: 0.13, alpha: 1)
        bg.setFill()
        bounds.fill()

        let inset = bounds.insetBy(dx: 16, dy: 12)
        let dash = NSBezierPath(roundedRect: inset, xRadius: 12, yRadius: 12)
        dash.lineWidth = 2
        let pattern: [CGFloat] = [6, 5]
        dash.setLineDash(pattern, count: 2, phase: 0)
        (isDragHighlighted
            ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.9)
            : NSColor(white: 0.30, alpha: 1)
        ).setStroke()
        dash.stroke()

        let text = "Drop image or folder"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: isDragHighlighted
                ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
                : NSColor(white: 0.45, alpha: 1)
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

    private var filtersExpanded = false
    private var filterContainerHeight: NSLayoutConstraint!
    private var selectedPath: String?
    private var selectedIsFolder = false

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "SpanWallpaper"
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.10, alpha: 1)

        let content = window.contentView!
        content.wantsLayer = true

        for v: NSView in [dropZone, pathLabel, browseButton, intervalLabel,
                          intervalPopup, playModeLabel, playModePopup,
                          displayModeLabel, displayModePopup,
                          filterToggle, filterContainer,
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

        setupDropZone()
        setupPathRow()
        setupSeparator()
        setupIntervalRow()
        setupDisplayRow()
        setupFilterSection()
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
        pathLabel.textColor = NSColor(white: 0.6, alpha: 1)
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
        intervalLabel.textColor = NSColor(white: 0.6, alpha: 1)
        intervalLabel.font = NSFont.systemFont(ofSize: 13)

        intervalPopup.removeAllItems()
        for preset in IntervalPreset.all {
            intervalPopup.addItem(withTitle: preset.title)
        }
        let savedInterval = RotationManager.shared.config?.intervalSeconds ?? AppConfig.defaultInterval
        intervalPopup.selectItem(at: IntervalPreset.indexForSeconds(savedInterval))

        playModeLabel.textColor = NSColor(white: 0.6, alpha: 1)
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
        displayModeLabel.textColor = NSColor(white: 0.6, alpha: 1)
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

    private func setupFilterSection() {
        filterToggle.isBordered = false
        filterToggle.setButtonType(.momentaryPushIn)
        filterToggle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        filterToggle.contentTintColor = NSColor(white: 0.7, alpha: 1)
        filterToggle.alignment = .left
        filterToggle.target = self
        filterToggle.action = #selector(filterToggleTapped)

        filterContainer.isHidden = true
        filterContainerHeight = filterContainer.heightAnchor.constraint(equalToConstant: 0)
        filterContainerHeight.isActive = true

        recursiveCheckbox.target = self
        recursiveCheckbox.action = #selector(filterChanged)

        let dimLabels: [NSTextField] = [excludeLabel, excludePlusLabel, minSizeLabel, maxSizeLabel,
                                         minWidthSuffix, minHeightSuffix, maxWidthSuffix, maxHeightSuffix,
                                         minSizeX, maxSizeX]
        for label in dimLabels {
            label.textColor = NSColor(white: 0.5, alpha: 1)
            label.font = NSFont.systemFont(ofSize: 12)
        }

        excludeFixedTag.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        excludeFixedTag.textColor = NSColor(white: 0.45, alpha: 1)
        excludeFixedTag.drawsBackground = true
        excludeFixedTag.backgroundColor = NSColor(white: 0.18, alpha: 1)
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
            field.backgroundColor = NSColor(white: 0.15, alpha: 1)
            field.textColor = .white
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
        statusLabel.textColor = NSColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 0.9)
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

            // Filter toggle
            filterToggle.topAnchor.constraint(equalTo: playModePopup.bottomAnchor, constant: 12),
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

            // Action row
            stopButton.topAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: 16),
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
            statusLabel.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 12),
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
                statusLabel.textColor = NSColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 0.9)
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
                    DispatchQueue.main.async { [weak self] in
                        self?.statusLabel.stringValue = "Applied."
                        self?.statusLabel.textColor = NSColor(white: 0.5, alpha: 1)
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
