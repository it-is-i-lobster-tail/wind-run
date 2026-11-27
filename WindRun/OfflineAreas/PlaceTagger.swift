import Foundation

/// Works out a workout's places from the offline pack, away from the main thread. The pack is opened the
/// first time it's needed and kept open, and only this actor reads it.
actor PlaceTagger {
    private let url: URL?
    private var pack: AreaPack?
    /// The pack's revision, read once when the app starts. Nil when this build has no pack.
    nonisolated let revision: String?

    init(url: URL?) {
        self.url = url
        revision = url.flatMap { try? AreaPack(url: $0).revision }
    }

    /// The pack in the app bundle.
    static let bundled = PlaceTagger(url: Bundle.main.url(forResource: AreaPack.fileName, withExtension: "sqlite"))

    /// The places along a route, or nil when this build has no pack or the route has no usable fix.
    func places(for fixes: [PlaceFix]) throws -> RoutePlaces? {
        guard let url else { return nil }
        if pack == nil { pack = try AreaPack(url: url) }
        guard let pack else { return nil }
        return try RoutePlaces.of(fixes, pack: pack)
    }
}
