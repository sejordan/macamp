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

    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false
    private var rearmAttempts = 0

    static var skinsFolder: URL { AppState.supportDirectory.appendingPathComponent("Skins", isDirectory: true) }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// `saved` is a built-in name or the path of a skin file. Anything unusable falls back to the default skin.
    init(saved: String) {
        let fallbackName = BuiltinSkins.defaultName
        current = SkinParser.parse(data: BuiltinSkins.data(named: fallbackName)!, dark: Self.isDark).skin!
        source = .builtin(fallbackName)
        if let name = BuiltinSkins.canonicalName(saved) {
            select(builtin: name)
        } else if saved.hasPrefix("/") {
            open(file: URL(fileURLWithPath: saved))
        }
    }

    /// What to store so the same skin comes back next launch.
    var savedIdentifier: String {
        switch source {
        case .builtin(let name): return name
        case .file(let url): return url.path
        }
    }

    func select(builtin name: String) {
        guard let canonical = BuiltinSkins.canonicalName(name), let data = BuiltinSkins.data(named: canonical),
              let skin = SkinParser.parse(data: data, dark: Self.isDark).skin else { return }
        stopWatching()
        source = .builtin(canonical)
        current = skin
        currentError = nil
        onChange?()
    }

    /// Uses a skin file where it sits and watches it. If the file has errors, the
    /// skin already on screen stays and the error is reported until the file is fixed.
    func open(file url: URL) {
        stopWatching()
        source = .file(url.standardizedFileURL)
        rearmAttempts = 0
        loadFile()
        watch()
        onChange?()
    }

    func reload() {
        switch source {
        case .builtin(let name): select(builtin: name)
        case .file:
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

    // MARK: Loading and watching

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
        } else {
            let errors = result.errors
            let more = errors.count > 1 ? "  (+\(errors.count - 1) more)" : ""
            currentError = "\(url.lastPathComponent): \(errors.first?.description ?? "invalid skin")\(more)"
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func watch() {
        guard case .file(let url) = source else { return }
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The file is missing, perhaps mid-save. Look again shortly, a limited number of times.
            guard rearmAttempts < 20 else { return }
            rearmAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.watcher == nil, self.source == .file(url) else { return }
                self.watch()
                if self.watcher != nil { self.scheduleReload() }
            }
            return
        }
        rearmAttempts = 0
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                                eventMask: [.write, .extend, .delete, .rename, .attrib],
                                                                queue: .main)
        watcher.setEventHandler { [weak self, weak watcher] in
            guard let self, let watcher else { return }
            let replaced = !watcher.data.intersection([.delete, .rename]).isEmpty
            if replaced {
                // Editors that save by writing a new file and renaming it leave us watching the old one.
                self.stopWatching()
                self.watch()
            }
            self.scheduleReload()
        }
        watcher.setCancelHandler { close(descriptor) }
        watcher.resume()
        self.watcher = watcher
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
