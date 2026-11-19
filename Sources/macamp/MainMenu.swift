import AppKit
import MacampCore

/// Builds the menu bar. Every player action lives here too, so a skin may omit any control.
enum MainMenu {
    static let skinMenuTag = 100
    static let controlsMenuTag = 101

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func submenu(_ title: String, tag: Int = 0, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = true
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        holder.tag = tag
        return holder
    }

    static func build(delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("macamp", [
            item("About macamp", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide macamp", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit macamp", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("File", [
            item("Open…", #selector(AppDelegate.openFiles(_:)), "o"),
            .separator(),
            item("Clear Playlist", #selector(AppDelegate.clearPlaylist(_:)), "k"),
        ]))
        main.addItem(submenu("Edit", [
            item("Select All", #selector(AppDelegate.selectAllRows(_:)), "a"),
            // No shortcut here on purpose: a bare Delete in the menu would fire while typing in a dialog.
            // The player window handles the Delete key itself.
            item("Remove from Playlist", #selector(AppDelegate.removeSelectedRows(_:))),
        ]))
        let controls = submenu("Controls", tag: controlsMenuTag, [
            item("Play", #selector(AppDelegate.menuAction(_:)), tag: actionTag(.playPause)),
            item("Stop", #selector(AppDelegate.menuAction(_:)), ".", tag: actionTag(.stop)),
            item("Next", #selector(AppDelegate.menuAction(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), tag: actionTag(.next)),
            item("Previous", #selector(AppDelegate.menuAction(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), tag: actionTag(.previous)),
            .separator(),
            item("Shuffle", #selector(AppDelegate.menuAction(_:)), "s", tag: actionTag(.shuffle)),
            item("Repeat", #selector(AppDelegate.menuAction(_:)), "r", tag: actionTag(.repeat)),
            .separator(),
            item("Volume Up", #selector(AppDelegate.volumeUp(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!)),
            item("Volume Down", #selector(AppDelegate.volumeDown(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!)),
            .separator(),
            item("Show Time Remaining", #selector(AppDelegate.menuAction(_:)), "t", tag: actionTag(.toggleTime)),
            item("Oscilloscope", #selector(AppDelegate.menuAction(_:)), "y", tag: actionTag(.toggleVisualizer)),
        ])
        controls.submenu?.delegate = delegate
        main.addItem(controls)

        let skins = submenu("Skin", tag: skinMenuTag, [])
        skins.submenu?.delegate = delegate
        main.addItem(skins)

        let window = submenu("Window", [
            item("Minimize", #selector(AppDelegate.minimizeWindow(_:)), "m"),
            item("Close", #selector(AppDelegate.closeWindow(_:)), "w"),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }

    /// Menu items carry their action in the tag.
    static func actionTag(_ action: ButtonAction) -> Int { 1000 + ButtonAction.allCases.firstIndex(of: action)! }
    static func action(forTag tag: Int) -> ButtonAction? {
        let index = tag - 1000
        return ButtonAction.allCases.indices.contains(index) ? ButtonAction.allCases[index] : nil
    }
}
