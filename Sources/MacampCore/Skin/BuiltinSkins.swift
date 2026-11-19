import Foundation

/// The skins and documents that ship inside the binary.
public enum BuiltinSkins {
    public static let names = ["Phosphor", "Rack Unit", "Native Mini"]
    public static let defaultName = "Phosphor"

    private static func key(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace }
    }

    /// The canonical name for a loosely typed one ("rackunit" gives "Rack Unit").
    public static func canonicalName(_ name: String) -> String? {
        names.first { key($0) == key(name) }
    }

    public static func data(named name: String) -> Data? {
        switch canonicalName(name) {
        case "Phosphor": return Data(PackageResources.Phosphor_json)
        case "Rack Unit": return Data(PackageResources.RackUnit_json)
        case "Native Mini": return Data(PackageResources.NativeMini_json)
        default: return nil
        }
    }

    public static let guide = String(decoding: PackageResources.SKIN_GUIDE_md, as: UTF8.self)
    public static let schema = String(decoding: PackageResources.skin_schema_json, as: UTF8.self)
}
