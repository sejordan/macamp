import AppKit
import MacampCore

/// Holds the active skin, reloads it when its file changes, and keeps the last
/// good version on screen while a file being edited is broken.
final class SkinManager {
    enum Source: Equatable {
        case builtin(String)
        case file(URL)
    }

    private(set) var current: Skin
    private(set) var source: Source
    /// A one-line description of what is wrong with the active skin file, if anything.
    private(set) var currentError: String?
    /// Called on the main thread after the skin or its error changes.
    var onChange: (() -> Void)?

    /// The most recent source that actually loaded. This is what gets remembered,
    /// so a file that never worked cannot replace the user's skin at the next launch.
    private var lastGood: String
    private var fileWatcher: DispatchSourceFileSystemObject?
    /// Watches the skin's folder while the file itself is absent, to notice it coming back.
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var reloadPending = false

    static var skinsFolder: URL { AppState.supportDirectory.appendingPathComponent("Skins", isDirectory: true) }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// `saved` is what was remembered from the last run: a built-in name or a file path. If it can
    /// no longer be used, the default skin is shown without complaint.
    /// `requested` is a skin the user asked for at launch. That one is kept and watched even if it
    /// is broken, with its error on show, because they are presumably about to fix it.
    init(saved: String, requested: String? = nil) {
        let fallbackName = BuiltinSkins.defaultName
        current = SkinParser.parse(data: BuiltinSkins.data(named: fallbackName)!, dark: Self.isDark).skin!
        source = .builtin(fallbackName)
        lastGood = fallbackName

        if let name = BuiltinSkins.canonicalName(saved) {
            select(builtin: name)
        } else if saved.hasPrefix("/"), let data = try? Data(contentsOf: URL(fileURLWithPath: saved)),
                  SkinParser.parse(data: data, dark: Self.isDark).skin != nil {
            open(file: URL(fileURLWithPath: saved))
        }
        if let requested {
            if let name = BuiltinSkins.canonicalName(requested) {
                select(builtin: name)
            } else {
                open(file: URL(fileURLWithPath: requested))
            }
        }
    }

    /// What to store so the same skin comes back next launch.
    var savedIdentifier: String { lastGood }

    func select(builtin name: String) {
        guard let canonical = BuiltinSkins.canonicalName(name), let data = BuiltinSkins.data(named: canonical),
              let skin = SkinParser.parse(data: data, dark: Self.isDark).skin else { return }
        stopWatching()
        source = .builtin(canonical)
        current = skin
        currentError = nil
        lastGood = canonical
        onChange?()
    }

    /// Uses a skin file where it sits and watches it. If the file has errors, the
    /// skin already on screen stays and the error is reported until the file is fixed.
    func open(file url: URL) {
        source = .file(url.standardizedFileURL)
        loadFile()
        watch()
        onChange?()
    }

    func reload() {
        switch source {
        case .builtin(let name): select(builtin: name)
        case .file:
            if fileWatcher == nil { watch() }
            loadFile()
            onChange?()
        }
    }

    /// Skins that define a dark palette are parsed again when the system appearance flips.
    func appearanceChanged() {
        guard current.followsAppearance else { return }
        reload()
    }

    func userSkins() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: Self.skinsFolder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { FileScanner.isSkinFile($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: Loading

    private func loadFile() {
        guard case .file(let url) = source else { return }
        guard let data = try? Data(contentsOf: url) else {
            currentError = "\(url.lastPathComponent): file cannot be read"
            FileHandle.standardError.write(Data("macamp: cannot read skin \(url.path)\n".utf8))
            return
        }
        let result = SkinParser.parse(data: data, dark: Self.isDark)
        for issue in result.issues {
            let kind = issue.severity == .error ? "error" : "warning"
            FileHandle.standardError.write(Data("\(url.lastPathComponent): \(kind): \(issue)\n".utf8))
        }
        if let skin = result.skin {
            current = skin
            currentError = nil
            lastGood = url.path
        } else {
            let errors = result.errors
            let more = errors.count > 1 ? "  (+\(errors.count - 1) more)" : ""
            currentError = "\(url.lastPathComponent): \(errors.first?.description ?? "invalid skin")\(more)"
        }
    }

    // MARK: Watching

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        folderWatcher?.cancel()
        folderWatcher = nil
    }

    private func makeWatcher(path: String, events: DispatchSource.FileSystemEvent,
                             handler: @escaping (DispatchSource.FileSystemEvent) -> Void) -> DispatchSourceFileSystemObject? {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        watcher.setEventHandler { [weak watcher] in
            if let watcher { handler(watcher.data) }
        }
        watcher.setCancelHandler { close(descriptor) }
        watcher.resume()
        return watcher
    }

    /// Watches the active skin file. While the file does not exist, watches its folder instead,
    /// so the file is picked up again whenever it reappears, however long that takes.
    private func watch() {
        stopWatching()
        guard case .file(let url) = source else { return }
        fileWatcher = makeWatcher(path: url.path, events: [.write, .extend, .delete, .rename, .attrib]) { [weak self] events in
            guard let self, self.source == .file(url) else { return }
            // Editors that save by writing a new file and renaming it over the old one leave
            // this watcher attached to the old file, so attach to whatever is at the path now.
            if !events.intersection([.delete, .rename]).isEmpty { self.watch() }
            self.scheduleReload()
        }
        guard fileWatcher == nil else { return }

        let folder = url.deletingLastPathComponent().path
        folderWatcher = makeWatcher(path: folder, events: [.write, .rename, .delete]) { [weak self] _ in
            guard let self, self.source == .file(url), FileManager.default.fileExists(atPath: url.path) else { return }
            self.watch()
            self.scheduleReload()
        }
        // The file may have appeared between the two attempts above.
        if folderWatcher != nil, FileManager.default.fileExists(atPath: url.path) {
            watch()
            scheduleReload()
        }
    }

    /// Several events arrive for one save; reload once after they settle.
    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.reloadPending = false
            guard case .file = self.source else { return }
            self.loadFile()
            self.onChange?()
        }
    }
}
