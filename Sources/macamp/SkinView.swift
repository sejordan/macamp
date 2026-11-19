import AppKit
import MacampCore
import QuartzCore

/// The whole player window: draws the active skin and turns mouse, keyboard
/// and drag-and-drop input into player actions.
final class SkinView: NSView {
    static let fftSamples = SpectrumAnalyzer.fftSize
    static let scopePoints = 160

    let controller: PlayerController
    /// Runs a button action. The app delegate owns this so menus and skins share one path.
    var onAction: ((ButtonAction) -> Void)?
    /// Files or folders were dropped on the window.
    var onDrop: (([URL]) -> Void)?

    var showRemaining = false { didSet { needsDisplay = true } }
    var scopeMode = false { didSet { needsDisplay = true } }
    var errorBanner: String? { didSet { needsDisplay = true } }

    private var skin: Skin
    private var renderer: SkinRenderer

    // Pointer state
    private var hover: Int?
    private var pressed: Int?
    private var dragSlider: (element: Int, value: Double)?
    private var mouseDownPoint = CGPoint.zero
    private var mouseDownRow: Int?
    private var collapseSelectionOnMouseUp = false
    private var draggingRows = false
    private var dropRow: Int?

    // Playlist state
    private(set) var selection = IndexSet()
    private var anchorRow: Int?
    private var scroll: CGFloat = 0
    private var lastCurrentID: UUID?

    // Elements that need attention on every tick, found once per skin
    private var dynamicText: [Int] = []
    private var visualizers: [Int] = []
    private var seekSliders: [Int] = []
    private var playlists: [Int] = []
    private var marquees: Set<Int> = []
    private var textCache: [Int: String] = [:]
    private var seekCache: [Int: CGFloat] = [:]

    // Visualizer
    private let analyzer = SpectrumAnalyzer()
    private var smoother = BarSmoother(count: 0)
    private var samples = [Float](repeating: 0, count: SkinView.fftSamples)
    private var scope: [Float] = []
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var marqueeTime = 0.0

    init(controller: PlayerController, skin: Skin, height: CGFloat) {
        self.controller = controller
        self.skin = skin
        self.renderer = SkinRenderer(skin: skin, windowHeight: height)
        super.init(frame: CGRect(x: 0, y: 0, width: skin.window.size.width, height: height))
        registerForDraggedTypes([.fileURL])
        indexElements()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Skin and layout

    func apply(skin newSkin: Skin) {
        skin = newSkin
        rebuildRenderer()
        hover = nil
        pressed = nil
        dragSlider = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(renderer.layout.windowSize.height - newSize.height) > 0.01 { rebuildRenderer() }
    }

    private func rebuildRenderer() {
        renderer = SkinRenderer(skin: skin, windowHeight: max(1, bounds.height))
        indexElements()
        clampScroll()
        needsDisplay = true
    }

    private func indexElements() {
        dynamicText = []; visualizers = []; seekSliders = []; playlists = []
        textCache = [:]; seekCache = [:]; marquees = []
        var bars = 0
        for (i, element) in skin.elements.enumerated() {
            switch element.kind {
            case .text(let text): if text.template.isDynamic { dynamicText.append(i) }
            case .visualizer(let viz):
                visualizers.append(i)
                bars = max(bars, viz.bars)
            case .slider(let slider): if slider.binds == .seek { seekSliders.append(i) }
            case .playlist: playlists.append(i)
            default: break
            }
        }
        if smoother.levels.count != bars { smoother = BarSmoother(count: bars) }
        refreshReadouts(with: makeState())
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    var onAppearanceChange: (() -> Void)?

    // MARK: State and drawing

    private func makeState() -> RenderState {
        var s = RenderState()
        s.values = controller.templateValues
        s.values.showRemaining = showRemaining
        s.isPlaying = controller.status == .playing
        s.isPaused = controller.status == .paused
        let duration = controller.duration
        s.seekFraction = duration > 0 ? min(1, controller.elapsed / duration) : 0
        s.volume = controller.volume
        s.shuffle = controller.order.shuffle
        s.repeatOn = controller.order.repeatMode != .off
        s.repeatOne = controller.order.repeatMode == .one
        s.scopeMode = scopeMode
        s.bars = smoother.levels
        s.peaks = smoother.peaks
        s.scope = scope
        let tracks = controller.playlist.tracks
        s.rowCount = tracks.count
        s.row = { i in
            let t = tracks[i]
            return PlaylistRow(title: t.title, artist: t.artist, album: t.album, fileName: t.fileName,
                               duration: t.duration, unplayable: t.unplayable)
        }
        s.currentRow = controller.playlist.currentIndex
        s.selection = selection
        s.playlistScroll = scroll
        s.dropIndicatorRow = draggingRows ? dropRow : nil
        s.hoverElement = hover
        s.pressedElement = pressed
        s.dragSlider = dragSlider
        s.marqueeTime = marqueeTime
        s.errorBanner = errorBanner
        return s
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let state = makeState()
        var rects: UnsafePointer<NSRect>?
        var count = 0
        getRectsBeingDrawn(&rects, count: &count)
        if let rects, count > 0, count <= 8 {
            for i in 0..<count { renderer.draw(in: ctx, state: state, dirty: rects[i]) }
        } else {
            renderer.draw(in: ctx, state: state, dirty: dirtyRect)
        }
    }

    private func invalidate(_ element: Int?) {
        guard let element, renderer.layout.frames.indices.contains(element) else { return }
        setNeedsDisplay(renderer.layout.frames[element])
    }

    /// Repaints text and seek sliders whose appearance has changed since they were last drawn.
    private func refreshReadouts(with state: RenderState) {
        for i in dynamicText {
            let text = renderer.renderedText(element: i, state: state) ?? ""
            if textCache[i] != text {
                textCache[i] = text
                if renderer.needsMarquee(element: i, state: state) { marquees.insert(i) } else { marquees.remove(i) }
                invalidate(i)
            }
        }
        for i in seekSliders {
            let x = (renderer.layout.sliderGeometry(element: i, value: state.seekFraction).progress.maxX * 2).rounded() / 2
            if seekCache[i] != x {
                seekCache[i] = x
                invalidate(i)
            }
        }
    }

    /// The player's state changed outside a tick: a track started, the playlist was edited, and so on.
    func controllerChanged() {
        let current = controller.playlist.currentID
        if current != lastCurrentID {
            lastCurrentID = current
            marqueeTime = 0
            scrollCurrentRowIntoView()
        }
        selection = selection.filteredIndexSet { $0 < controller.playlist.count }
        clampScroll()
        textCache = [:]
        needsDisplay = true
        updateTicking()
    }

    /// Tags arrived for some rows; only the playlist and the readouts can be affected.
    func metadataChanged() {
        playlists.forEach(invalidate)
        refreshReadouts(with: makeState())
    }

    // MARK: Animation

    /// The display link runs only while there is something moving and someone can see it.
    func updateTicking() {
        let visible = window.map { $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false
        let active = controller.status == .playing || !smoother.isSilent
        if visible && active {
            guard link == nil else { return }
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
            lastTick = 0
        } else if let link {
            link.invalidate()
            self.link = nil
            needsDisplay = true
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick == 0 ? 1.0 / 60 : min(0.1, max(0, now - lastTick))
        lastTick = now
        let playing = controller.status == .playing
        if playing { marqueeTime += dt }

        if !visualizers.isEmpty {
            var target: [Float] = []
            let rate = playing ? samples.withUnsafeMutableBufferPointer { controller.monoSamples(count: Self.fftSamples, into: $0) } : nil
            if let rate {
                if scopeMode {
                    let recent = samples.suffix(Self.scopePoints * 3)
                    scope = stride(from: recent.startIndex, to: recent.endIndex, by: 3).map { recent[$0] }
                } else {
                    target = samples.withUnsafeBufferPointer {
                        analyzer.bands(samples: $0, sampleRate: rate, count: smoother.levels.count)
                    }
                }
            } else {
                scope = []
            }
            smoother.update(target: target, dt: dt)
            visualizers.forEach(invalidate)
        }
        refreshReadouts(with: makeState())
        if playing { marquees.forEach(invalidate) }
        if !playing && smoother.isSilent { updateTicking() }
    }

    // MARK: Playlist helpers

    private var playlistElement: Int? { playlists.first }

    private func clampScroll() {
        guard let element = playlistElement else { scroll = 0; return }
        scroll = min(max(0, scroll), renderer.layout.maxPlaylistScroll(element: element, count: controller.playlist.count))
    }

    private func scrollCurrentRowIntoView() {
        guard let element = playlistElement, let row = controller.playlist.currentIndex,
              case .playlist(let list) = skin.elements[element].kind else { return }
        let rowHeight = CGFloat(list.rowHeight), visible = renderer.layout.frames[element].height
        let top = CGFloat(row) * rowHeight
        if top < scroll { scroll = top } else if top + rowHeight > scroll + visible { scroll = top + rowHeight - visible }
        clampScroll()
    }

    func selectAllRows() {
        selection = IndexSet(integersIn: 0..<controller.playlist.count)
        playlists.forEach(invalidate)
    }

    func removeSelectedRows() {
        guard !selection.isEmpty else { return }
        let rows = selection
        selection = IndexSet()
        anchorRow = nil
        controller.remove(at: rows)
    }

    // MARK: Mouse

    private func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func setHover(_ element: Int?) {
        var target = element
        if let e = element, case .button = skin.elements[e].kind {} else { target = nil }
        guard target != hover else { return }
        invalidate(hover)
        hover = target
        invalidate(hover)
    }

    override func mouseMoved(with event: NSEvent) {
        setHover(renderer.layout.interactiveElement(at: location(event)))
    }

    override func mouseExited(with event: NSEvent) { setHover(nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = location(event)
        mouseDownPoint = p
        guard let element = renderer.layout.interactiveElement(at: p) else {
            window?.performDrag(with: event)
            return
        }
        switch skin.elements[element].kind {
        case .button, .text, .visualizer:
            pressed = element
            invalidate(element)
        case .slider(let slider):
            let value = renderer.layout.sliderValue(element: element, at: p)
            dragSlider = (element, value)
            if slider.binds == .volume { controller.volume = value }
            invalidate(element)
        case .playlist:
            playlistMouseDown(element: element, at: p, event: event)
        case .rect:
            break
        }
    }

    private func playlistMouseDown(element: Int, at p: CGPoint, event: NSEvent) {
        let count = controller.playlist.count
        let row = renderer.layout.playlistRow(element: element, at: p, scroll: scroll, count: count)
        mouseDownRow = row
        collapseSelectionOnMouseUp = false
        draggingRows = false
        defer { invalidate(element) }
        guard let row else {
            selection = IndexSet()
            anchorRow = nil
            return
        }
        if event.clickCount >= 2 {
            selection = IndexSet(integer: row)
            anchorRow = row
            mouseDownRow = nil
            controller.playTrack(at: row)
            return
        }
        if event.modifierFlags.contains(.command) {
            if selection.contains(row) { selection.remove(row) } else { selection.insert(row) }
            anchorRow = row
        } else if event.modifierFlags.contains(.shift), let anchor = anchorRow, anchor < count {
            selection = IndexSet(integersIn: min(anchor, row)...max(anchor, row))
        } else if selection.contains(row) {
            // Might be the start of dragging several rows; only collapse to this row if no drag follows.
            collapseSelectionOnMouseUp = true
        } else {
            selection = IndexSet(integer: row)
            anchorRow = row
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(event)
        if let drag = dragSlider, case .slider(let slider) = skin.elements[drag.element].kind {
            let value = renderer.layout.sliderValue(element: drag.element, at: p)
            dragSlider = (drag.element, value)
            if slider.binds == .volume { controller.volume = value }
            invalidate(drag.element)
            return
        }
        if let element = pressed {
            // Dragging off a pressed control cancels the click.
            if !renderer.layout.frames[element].contains(p) {
                pressed = nil
                invalidate(element)
            }
            return
        }
        guard let element = playlistElement, mouseDownRow != nil, !selection.isEmpty else { return }
        if !draggingRows, hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) < 4 { return }
        draggingRows = true
        let frame = renderer.layout.frames[element]
        if case .playlist(let list) = skin.elements[element].kind {
            if p.y < frame.minY { scroll -= CGFloat(list.rowHeight) / 2 }
            if p.y > frame.maxY { scroll += CGFloat(list.rowHeight) / 2 }
            clampScroll()
        }
        let clamped = CGPoint(x: p.x, y: min(frame.maxY, max(frame.minY, p.y)))
        dropRow = renderer.layout.playlistInsertionIndex(element: element, at: clamped, scroll: scroll,
                                                         count: controller.playlist.count)
        invalidate(element)
    }

    override func mouseUp(with event: NSEvent) {
        let p = location(event)
        if let drag = dragSlider {
            dragSlider = nil
            if case .slider(let slider) = skin.elements[drag.element].kind, slider.binds == .seek {
                controller.seek(fraction: drag.value)
            }
            invalidate(drag.element)
            return
        }
        if let element = pressed {
            pressed = nil
            invalidate(element)
            guard renderer.layout.frames[element].contains(p) else { return }
            switch skin.elements[element].kind {
            case .button(let button): onAction?(button.action)
            case .text(let text): if let action = text.action { onAction?(action) }
            case .visualizer: onAction?(.toggleVisualizer)
            default: break
            }
            return
        }
        if draggingRows, let destination = dropRow {
            selection = controller.move(from: selection, to: destination)
            anchorRow = selection.first
        } else if collapseSelectionOnMouseUp, let row = mouseDownRow {
            selection = IndexSet(integer: row)
            anchorRow = row
        }
        draggingRows = false
        dropRow = nil
        mouseDownRow = nil
        collapseSelectionOnMouseUp = false
        playlists.forEach(invalidate)
    }

    override func scrollWheel(with event: NSEvent) {
        let p = location(event)
        guard let element = playlistElement, renderer.layout.frames[element].contains(p),
              case .playlist(let list) = skin.elements[element].kind else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * CGFloat(list.rowHeight)
        let before = scroll
        scroll -= delta
        clampScroll()
        if scroll != before { invalidate(element) }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 49: onAction?(.playPause)                              // space
        case 123: controller.seek(by: -5)                           // left
        case 124: controller.seek(by: 5)                            // right
        case 126: controller.volume = min(1, controller.volume + 0.05)   // up
        case 125: controller.volume = max(0, controller.volume - 0.05)   // down
        case 36, 76: if let row = selection.first { controller.playTrack(at: row) }   // return, enter
        case 51, 117: removeSelectedRows()                          // delete, forward delete
        case 53:                                                    // escape
            selection = IndexSet()
            playlists.forEach(invalidate)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z": onAction?(.previous)
            case "x": onAction?(.play)
            case "c": onAction?(.pause)
            case "v": onAction?(.stop)
            case "b": onAction?(.next)
            default: super.keyDown(with: event)
            }
        }
    }

    // MARK: Drag and drop

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                            options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    // MARK: Diagnostics

    /// The window's content as PNG data, drawn through the same path as the screen.
    func snapshotPNG() -> Data? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
