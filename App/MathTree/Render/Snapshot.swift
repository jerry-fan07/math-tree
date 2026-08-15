import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
import simd

/// Offscreen single-frame capture, driven entirely by environment variables:
///
/// - `MATHTREE_SNAPSHOT` — path to write a PNG to. Its presence turns the app
///   into a one-shot renderer that never opens a window.
/// - `MATHTREE_SNAPSHOT_ZOOM` — `overview` | `mid` | `detail` (default `overview`).
/// - `MATHTREE_SNAPSHOT_SIZE` — `WIDTHxHEIGHT` in points (default `1280x800`).
/// - `MATHTREE_SNAPSHOT_REVEAL` — freeze the progressive-reveal clock at a value
///   in 0…1 (default 1, fully revealed). Values below 1 capture §6.4's
///   hubs-first fade-in as a still.
/// - `MATHTREE_SNAPSHOT_HOVER` — `auto` (default) hovers the anchor node at
///   detail zoom so the prerequisite/dependent highlight is visible; `none`
///   disables it; any node id hovers that node.
///
/// The appearance comes from `MATHTREE_THEME` (`dark` | `light`, read by
/// `ThemeStore`), which is a process-wide pin rather than a snapshot flag —
/// `--probe` and `MATHTREE_PANEL_SHOT` need the same control, and a headless run
/// has no system appearance to fall back on.
///
/// The environment rather than flags because of D3.7: `--flag value` pairs on an
/// AppKit command line get parsed into `NSUserDefaults` and can stop the window
/// from ever being created. Offscreen because D3.7 also says profile offscreen —
/// and it means a snapshot needs no window server at all.
enum Snapshot {
    @MainActor
    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MATHTREE_SNAPSHOT"], !path.isEmpty else { return }

        let bandName = environment["MATHTREE_SNAPSHOT_ZOOM"] ?? ZoomBand.overview.rawValue
        guard let band = ZoomBand(rawValue: bandName) else {
            fail("MATHTREE_SNAPSHOT_ZOOM must be one of: overview, mid, detail (got \(bandName))")
        }
        let sizePt = parseSize(environment["MATHTREE_SNAPSHOT_SIZE"]) ?? CGSize(width: 1280, height: 800)

        let store = SceneStore.shared
        guard let renderer = store.renderer, let scene = store.scene else {
            fail(store.errorMessage ?? "renderer unavailable")
        }

        let backingScale: CGFloat = 2
        let widthPx = Int(sizePt.width * backingScale)
        let heightPx = Int(sizePt.height * backingScale)
        renderer.resize(
            drawablePx: SIMD2(Float(widthPx), Float(heightPx)), backingScale: backingScale)
        // A snapshot shows the settled scene unless it is deliberately capturing
        // the progressive reveal part-way through.
        renderer.setReveal(Float(environment["MATHTREE_SNAPSHOT_REVEAL"].flatMap(Double.init) ?? 1))

        let anchor = scene.anchor(for: band)
        renderer.park(at: band, anchor: anchor)
        applyHover(environment["MATHTREE_SNAPSHOT_HOVER"], band: band, anchor: anchor, renderer: renderer)

        do {
            let texture = try renderer.renderOffscreen(widthPx: widthPx, heightPx: heightPx)
            try writePNG(texture: texture, to: URL(fileURLWithPath: path))
        } catch {
            fail(String(describing: error))
        }

        print("snapshot: \(path) \(widthPx)x\(heightPx)px band=\(band.rawValue)")
        fflush(stdout)
        exit(0)
    }

    // MARK: - Helpers

    @MainActor
    private static func applyHover(
        _ setting: String?, band: ZoomBand, anchor: SIMD2<Float>, renderer: GraphRenderer
    ) {
        let scene = renderer.scene
        switch setting ?? "auto" {
        case "none":
            return
        case "auto":
            // The highlight is a detail-zoom behaviour (§6.1), so that is the only
            // band where it is worth capturing.
            guard band == .detail else { return }
            renderer.setHover(scene.pickGrid.nearest(to: anchor, within: 1e-2))
        case let id:
            renderer.setHover(scene.document.index(of: .init(id)))
        }
    }

    private static func parseSize(_ text: String?) -> CGSize? {
        guard let text else { return nil }
        let parts = text.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
            width >= 64, height >= 64
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func writePNG(texture: MTLTexture, to url: URL) throws {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base, bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        // bgra8Unorm bytes are little-endian xRGB; the scene is rendered on an
        // opaque background, so alpha carries no information and is skipped.
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        else { throw SnapshotError.imageCreationFailed }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SnapshotError.writeFailed(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SnapshotError.writeFailed(url.path)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("snapshot: \(message)\n".utf8))
        exit(3)
    }

    enum SnapshotError: Error, CustomStringConvertible {
        case imageCreationFailed
        case writeFailed(String)

        var description: String {
            switch self {
            case .imageCreationFailed: "could not build a CGImage from the render target"
            case let .writeFailed(path): "could not write PNG to \(path)"
            }
        }
    }
}
