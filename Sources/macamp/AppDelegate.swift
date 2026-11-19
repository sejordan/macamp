import AppKit
import MacampCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let options: CLI.LaunchOptions
    private let stateURL: URL
    private var controller: PlayerController!
    private var skins: SkinManager!
    private var windowController: PlayerWindowController!
    private var nowPlaying: NowPlaying?

    private var ready = false
    private var pendingOpen: [URL] = []
    private var saveScheduled = false
    private var metadataRefreshScheduled = false
    private var metadataQueued: Set<UUID> = []
    private let metadataQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()

    init(options: CLI.LaunchOptions) {
        self.options = options
        self.stateURL = options.stateFile ?? AppState.defaultURL
    }

    private var view: SkinView { windowController.view }

    // MARK: Launch and quit

    func applicationDidFinishLaunching(_ notification: Notification) {
        let firstLaunch = !FileManager.default.fileExists(atPath: stateURL.path)
        let state = AppState.load(from: stateURL)
        controller = PlayerController(audio: AudioPlayer())
        controller.restore(tracks: state.tracks, currentID: state.currentID)
        controller.volume = state.volume
        var order = PlaybackOrder()
        order.shuffle = state.shuffle
        order.repeatMode = state.repeatMode
        controller.order = order

        skins = SkinManager(saved: state.skin, requested: options.skinPath)
        windowController = PlayerWindowController(controller: controller, skin: skins.current,
                                                  origin: state.windowOrigin, height: state.windowHeight)
        view.showRemaining = state.showRemaining
        view.scopeMode = state.scopeMode
        view.errorBanner = skins.currentError
        view.onAction = { [weak self] in self?.perform($0) }
        view.onDrop = { [weak self] in self?.open($0, playFirstNew: false, playIfIdle: true) }
        view.onAppearanceChange = { [weak self] in self?.skins.appearanceChanged() }

        controller.onChange = { [weak self] in
            guard let self else { return }
            self.view.controllerChanged()
            self.nowPlaying?.update()
            self.scheduleSave()
        }
        skins.onChange = { [weak self] in
            guard let self else { return }
            self.windowController.apply(skin: self.skins.current)
            self.view.errorBanner = self.skins.currentError
            self.scheduleSave()
        }
        windowController.onClose = { NSApp.terminate(nil) }
        windowController.onFrameChange = { [weak self] in self?.scheduleSave() }

        NSApp.mainMenu = MainMenu.build(delegate: self)
        windowController.show()
        NSApp.activate(ignoringOtherApps: true)
        nowPlaying = NowPlaying(controller: controller)
        view.controllerChanged()

        ready = true
        let launchFiles = options.files + pendingOpen
        pendingOpen = []
        if firstLaunch { addWelcomeTrack() }
        if !launchFiles.isEmpty { open(launchFiles, playFirstNew: true, playIfIdle: true) }
        verifyRestoredFiles()
        loadMissingMetadata()
        scheduleSnapshotIfRequested()
    }

    /// The very first time the app runs, its playlist holds the short track that ships with it,
    /// so there is something to play. It is added once and never comes back after being removed.
    private func addWelcomeTrack() {
        let bundled = Bundle.main.url(forResource: "macamp", withExtension: "mp3")
        guard let track = WelcomeTrack.install(from: bundled, into: stateURL.deletingLastPathComponent()) else { return }
        controller.add([track], playFirstNew: false, playIfIdle: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { saveNow() }

    /// Files opened from Finder, "Open With" or the Dock icon start playing at once.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard ready else {
            pendingOpen.append(contentsOf: urls)
            return
        }
        open(urls, playFirstNew: true, playIfIdle: true)
    }

    // MARK: Opening files

    func open(_ urls: [URL], playFirstNew: Bool, playIfIdle: Bool) {
        var audio: [URL] = []
        var skinFile: URL?
        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, !isDirectory.boolValue, FileScanner.isSkinFile(url) { skinFile = skinFile ?? url } else { audio.append(url) }
        }
        if let skinFile { skins.open(file: skinFile) }
        guard !audio.isEmpty else { return }
        // Walking a large folder can take a while, so it happens off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = FileScanner.expand(audio)
            DispatchQueue.main.async {
                guard let self, !files.isEmpty else { return }
                self.controller.add(files, playFirstNew: playFirstNew, playIfIdle: playIfIdle)
                self.loadMissingMetadata()
            }
        }
    }

    /// Reads tags for tracks that do not have them yet, two files at a time, in the background.
    private func loadMissingMetadata() {
        for track in controller.playlist.tracks where !track.metadataLoaded && !metadataQueued.contains(track.id) {
            metadataQueued.insert(track.id)
            let id = track.id, url = track.url
            metadataQueue.addOperation { [weak self] in
                let tags = TrackMetadata.read(url)
                let exists = FileManager.default.fileExists(atPath: url.path)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.metadataQueued.remove(id)
                    self.controller.playlist.update(id: id) { t in
                        t.metadataLoaded = exists
                        if let tags {
                            t.title = tags.title; t.artist = tags.artist; t.album = tags.album
                            if t.duration == nil { t.duration = tags.duration }
                        }
                        if !exists { t.unplayable = true }
                    }
                    self.scheduleMetadataRefresh()
                }
            }
        }
    }

    /// A restored playlist may point at files that have since moved or been deleted; mark those.
    private func verifyRestoredFiles() {
        // Marks are only ever added here. A file marked for another reason (it is not really audio,
        // say) keeps its mark, and any mark clears by itself the next time the track plays.
        let tracks = controller.playlist.tracks.filter { !$0.unplayable }.map { ($0.id, $0.url) }
        guard !tracks.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let missing = tracks.filter { !FileManager.default.fileExists(atPath: $0.1.path) }.map(\.0)
            guard !missing.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                for id in missing { self.controller.playlist.update(id: id) { $0.unplayable = true } }
                self.scheduleMetadataRefresh()
            }
        }
    }

    private func scheduleMetadataRefresh() {
        guard !metadataRefreshScheduled else { return }
        metadataRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.metadataRefreshScheduled = false
            self.view.metadataChanged()
            self.nowPlaying?.update()
            self.scheduleSave()
        }
    }

    // MARK: Actions

    func perform(_ action: ButtonAction) {
        switch action {
        case .play: controller.play()
        case .pause: controller.pause()
        case .playPause: controller.playPause()
        case .stop: controller.stop()
        case .previous: controller.previous()
        case .next: controller.next()
        case .open: openFiles(nil)
        case .shuffle:
            var order = controller.order
            order.shuffle.toggle()
            controller.order = order
        case .repeat:
            var order = controller.order
            order.repeatMode = order.repeatMode.next
            controller.order = order
        case .close: windowController.window.close()
        case .minimize: windowController.window.miniaturize(nil)
        case .toggleTime:
            view.showRemaining.toggle()
            scheduleSave()
        case .toggleVisualizer:
            view.scopeMode.toggle()
            scheduleSave()
        }
    }

    @objc func menuAction(_ sender: NSMenuItem) {
        if let action = MainMenu.action(forTag: sender.tag) { perform(action) }
    }

    @objc func openFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose audio files or folders to add to the playlist"
        panel.beginSheetModal(for: windowController.window) { [weak self] response in
            guard response == .OK else { return }
            self?.open(panel.urls, playFirstNew: false, playIfIdle: true)
        }
    }

    @objc func clearPlaylist(_ sender: Any?) { controller.clear() }
    @objc func selectAllRows(_ sender: Any?) { view.selectAllRows() }
    @objc func removeSelectedRows(_ sender: Any?) { view.removeSelectedRows() }
    @objc func volumeUp(_ sender: Any?) { controller.volume = min(1, controller.volume + 0.05) }
    @objc func volumeDown(_ sender: Any?) { controller.volume = max(0, controller.volume - 0.05) }
    @objc func closeWindow(_ sender: Any?) { windowController.window.close() }
    @objc func minimizeWindow(_ sender: Any?) { windowController.window.miniaturize(nil) }

    // MARK: Skin menu

    @objc func selectBuiltinSkin(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { skins.select(builtin: name) }
    }

    @objc func selectSkinFile(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { skins.open(file: url) }
    }

    @objc func openSkinFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a macamp skin file"
        panel.beginSheetModal(for: windowController.window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.skins.open(file: url)
        }
    }

    @objc func reloadSkin(_ sender: Any?) { skins.reload() }

    @objc func revealSkinsFolder(_ sender: Any?) {
        let folder = SkinManager.skinsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Skin" { rebuildSkinMenu(menu) } else if menu.title == "Controls" { updateControlsMenu(menu) }
    }

    private func rebuildSkinMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for name in BuiltinSkins.names {
            let item = NSMenuItem(title: name, action: #selector(selectBuiltinSkin(_:)), keyEquivalent: "")
            item.representedObject = name
            item.state = skins.source == .builtin(name) ? .on : .off
            menu.addItem(item)
        }
        var files = skins.userSkins()
        if case .file(let active) = skins.source, !files.contains(where: { $0.standardizedFileURL == active }) {
            files.insert(active, at: 0)
        }
        if !files.isEmpty { menu.addItem(.separator()) }
        for url in files {
            let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent,
                                  action: #selector(selectSkinFile(_:)), keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            item.state = skins.source == .file(url.standardizedFileURL) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Skin File…", action: #selector(openSkinFile(_:)), keyEquivalent: ""))
        let reload = NSMenuItem(title: "Reload Skin", action: #selector(reloadSkin(_:)), keyEquivalent: "r")
        reload.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(reload)
        menu.addItem(NSMenuItem(title: "Reveal Skins Folder", action: #selector(revealSkinsFolder(_:)), keyEquivalent: ""))
    }

    private func updateControlsMenu(_ menu: NSMenu) {
        for item in menu.items {
            guard let action = MainMenu.action(forTag: item.tag) else { continue }
            switch action {
            case .playPause: item.title = controller.status == .playing ? "Pause" : "Play"
            case .shuffle: item.state = controller.order.shuffle ? .on : .off
            case .repeat:
                switch controller.order.repeatMode {
                case .off: item.title = "Repeat"; item.state = .off
                case .all: item.title = "Repeat All"; item.state = .on
                case .one: item.title = "Repeat One"; item.state = .on
                }
            case .toggleTime: item.state = view.showRemaining ? .on : .off
            case .toggleVisualizer: item.state = view.scopeMode ? .on : .off
            default: break
            }
        }
    }

    // MARK: Saved state

    private func scheduleSave() {
        guard ready, !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.saveScheduled = false
            self?.saveNow()
        }
    }

    private func saveNow() {
        guard ready else { return }
        var state = AppState()
        state.tracks = controller.playlist.tracks
        state.currentID = controller.playlist.currentID
        state.volume = controller.volume
        state.shuffle = controller.order.shuffle
        state.repeatMode = controller.order.repeatMode
        state.skin = skins.savedIdentifier
        let corner = windowController.topLeft
        state.windowOrigin = [Double(corner.x), Double(corner.y)]
        state.windowHeight = Double(windowController.contentHeight)
        state.showRemaining = view.showRemaining
        state.scopeMode = view.scopeMode
        try? state.save(to: stateURL)
    }

    // MARK: Diagnostics

    /// `--snapshot <png>` writes a picture of the live window plus a status file, then quits.
    private func scheduleSnapshotIfRequested() {
        guard let png = options.snapshotFile else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + options.snapshotDelay) { [weak self] in
            guard let self else { return }
            try? self.view.snapshotPNG()?.write(to: png)
            let values = self.controller.templateValues
            var status: [String: Any] = [
                "state": values.state,
                "elapsed": self.controller.elapsed,
                "duration": self.controller.duration,
                "index": values.index ?? 0,
                "count": values.count,
                "title": TextTemplate("{display}").render(values),
                "codec": values.codec ?? "",
                "skin": self.skins.current.name,
                "skinError": self.skins.currentError ?? "",
                "windowSize": [Double(self.view.bounds.width), Double(self.view.bounds.height)],
                "unplayable": self.controller.playlist.tracks.filter(\.unplayable).count,
                "tagged": self.controller.playlist.tracks.filter { $0.title != nil }.count,
            ]
            status["nowPlaying"] = self.nowPlaying?.published ?? [:]
            status["framesDrawn"] = self.view.tickCount
            status["tracks"] = self.controller.playlist.tracks.prefix(8).map {
                ["file": $0.fileName, "title": $0.title ?? "", "unplayable": $0.unplayable]
            }
            if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: png.appendingPathExtension("json"))
            }
            NSApp.terminate(nil)
        }
    }
}
