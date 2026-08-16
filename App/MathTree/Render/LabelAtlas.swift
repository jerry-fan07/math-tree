import AppKit
import CoreText
import Metal
import simd

/// Core Text into a grayscale `CGContext`, shelf-packed into an R8
/// `texture2d_array` and uploaded once (D3.5). No text layout engine, no
/// per-frame glyph work.
///
/// Tiers are rasterised on demand: the overview tier eagerly at load (~ms, on
/// the first-paint path), higher tiers the first time a zoom band asks for them.
/// D3.5's finding was that the binding constraint is atlas *memory*, not draw
/// time — 10,000 labels would be 88 MB — so nothing is rasterised until a band
/// needs it.
@MainActor
final class LabelAtlas {
    struct Stats {
        var pages = 0
        var bytes = 0
        var labels = 0
        var rasteriseMs = 0.0
        var highestTier: LODTier?
    }

    /// 1024² × R8 = 1 MB per page.
    static let pageSize = 1024
    /// Wider than this and a label stops being a label; truncate with an ellipsis.
    private static let maxLabelWidthPt: CGFloat = 240

    private let device: MTLDevice
    private let backingScale: CGFloat
    /// Baked in, not read live: the two directions of the redesign disagree about
    /// the tier-1 face, so a glyph page belongs to exactly one appearance. The
    /// renderer throws the atlas away and builds a new one when it switches.
    private let theme: Theme

    private var pageBytes: [[UInt8]] = []
    private var shelfX = 0
    private var shelfY = 0
    private var shelfHeight = 0

    private(set) var texture: MTLTexture?
    private(set) var instances: [LabelInstance] = []
    /// How many of the scene's label specs have been rasterised so far.
    private(set) var builtCount = 0
    private(set) var stats = Stats()

    init(device: MTLDevice, backingScale: CGFloat, theme: Theme) {
        self.device = device
        self.backingScale = max(backingScale, 1)
        self.theme = theme
    }

    /// Rasterise every spec up to and including `tier`. Returns true when new
    /// labels were added (and therefore the buffer needs re-uploading).
    @discardableResult
    func build(upTo tier: LODTier, specs: [GraphScene.LabelSpec]) -> Bool {
        guard builtCount < specs.count, specs[builtCount].tier <= tier else { return false }
        let start = CFAbsoluteTimeGetCurrent()

        var dirtyPages = Set<Int>()
        while builtCount < specs.count, specs[builtCount].tier <= tier {
            let spec = specs[builtCount]
            if let instance = rasterise(spec, dirtyPages: &dirtyPages) {
                instances.append(instance)
            } else {
                // A label that cannot be placed still needs an instance so that
                // the buffer stays index-aligned with the scene's tier prefixes.
                instances.append(
                    LabelInstance(
                        anchor: .zero, sizePt: .zero, uvMin: .zero, uvMax: .zero,
                        rgba: 0, page: 0, offsetPt: 0, fadeStart: spec.fadeStart))
            }
            builtCount += 1
        }

        uploadTexture(dirty: dirtyPages)
        stats.pages = pageBytes.count
        stats.bytes = pageBytes.count * Self.pageSize * Self.pageSize
        stats.labels = instances.count
        stats.rasteriseMs += (CFAbsoluteTimeGetCurrent() - start) * 1000
        stats.highestTier = tier
        return true
    }

    // MARK: - Rasterisation

    private func rasterise(_ spec: GraphScene.LabelSpec, dirtyPages: inout Set<Int>)
        -> LabelInstance?
    {
        // The redesign's three label registers. A branch name is a mono, uppercase,
        // wide-tracked eyebrow in both directions — it is the map's own chrome, not
        // its content. A subbranch is the one place the two directions differ in
        // *face* rather than colour: sans against the dark canvas, serif on paper.
        // Everything below is the reading sans.
        let pointSize = spec.tier.labelPointSize * backingScale
        let text: String
        let font: NSFont
        var tracking: CGFloat = 0
        switch spec.tier {
        case .branch:
            text = spec.text.uppercased()
            font = Typeface.nsMono(pointSize, .medium)
            tracking = Typeface.tracking(0.16, at: pointSize)
        case .subbranch:
            text = spec.text
            font = theme.isDark ? Typeface.nsSans(pointSize) : Typeface.nsSerif(pointSize)
        default:
            text = spec.text
            font = Typeface.nsSans(pointSize)
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(gray: 1.0, alpha: 1.0),
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        var line = CTLineCreateWithAttributedString(attributed)

        let maxWidth = Double(Self.maxLabelWidthPt * backingScale)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
            let token = CTLineCreateWithAttributedString(
                NSAttributedString(string: "…", attributes: attributes))
            if let truncated = CTLineCreateTruncatedLine(line, maxWidth, .end, token) {
                line = truncated
            }
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // One texel of slack on every side: the fragment shader's four-tap
        // dilation samples outside the glyph box.
        let padding: CGFloat = 2
        let boxWidth = Int((width + padding * 2).rounded(.up))
        let boxHeight = Int((ascent + descent + padding * 2).rounded(.up))
        guard boxWidth > 0, boxHeight > 0, boxWidth <= Self.pageSize, boxHeight <= Self.pageSize
        else { return nil }

        let slot = allocate(width: boxWidth, height: boxHeight)
        dirtyPages.insert(slot.page)

        pageBytes[slot.page].withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                let context = CGContext(
                    data: base, width: Self.pageSize, height: Self.pageSize,
                    bitsPerComponent: 8, bytesPerRow: Self.pageSize,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)  // subpixel smoothing is meaningless in R8
            context.setShouldSmoothFonts(false)
            context.textMatrix = .identity
            // The bitmap's first row is the top of the image while CG's origin is
            // bottom-left, so shelves are allocated top-down and flipped here.
            let cgBottom = CGFloat(Self.pageSize - slot.y - boxHeight)
            context.textPosition = CGPoint(x: CGFloat(slot.x) + padding, y: cgBottom + descent + padding)
            CTLineDraw(line, context)
        }

        let size = Float(Self.pageSize)
        return LabelInstance(
            anchor: spec.anchor,
            sizePt: SIMD2(Float(boxWidth) / Float(backingScale), Float(boxHeight) / Float(backingScale)),
            uvMin: SIMD2(Float(slot.x) / size, Float(slot.y) / size),
            uvMax: SIMD2(Float(slot.x + boxWidth) / size, Float(slot.y + boxHeight) / size),
            rgba: Palette.labelColor(tier: spec.tier, theme: theme),
            page: UInt32(slot.page),
            offsetPt: spec.offsetPt,
            fadeStart: spec.fadeStart)
    }

    private func allocate(width: Int, height: Int) -> (page: Int, x: Int, y: Int) {
        if pageBytes.isEmpty { newPage() }
        if shelfX + width > Self.pageSize {  // close the shelf
            shelfY += shelfHeight
            shelfX = 0
            shelfHeight = 0
        }
        if shelfY + height > Self.pageSize {  // close the page
            newPage()
        }
        let slot = (page: pageBytes.count - 1, x: shelfX, y: shelfY)
        shelfX += width
        shelfHeight = max(shelfHeight, height)
        return slot
    }

    private func newPage() {
        pageBytes.append([UInt8](repeating: 0, count: Self.pageSize * Self.pageSize))
        shelfX = 0
        shelfY = 0
        shelfHeight = 0
    }

    private func uploadTexture(dirty: Set<Int>) {
        guard !pageBytes.isEmpty else { return }
        var upload = dirty
        if texture == nil || texture!.arrayLength < pageBytes.count {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type2DArray
            descriptor.pixelFormat = .r8Unorm
            descriptor.width = Self.pageSize
            descriptor.height = Self.pageSize
            descriptor.arrayLength = pageBytes.count
            descriptor.usage = .shaderRead
            descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
            texture = device.makeTexture(descriptor: descriptor)
            upload = Set(0..<pageBytes.count)  // a fresh texture needs every page
        }
        guard let texture else { return }

        let region = MTLRegionMake2D(0, 0, Self.pageSize, Self.pageSize)
        for page in upload.sorted() {
            pageBytes[page].withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                texture.replace(
                    region: region, mipmapLevel: 0, slice: page, withBytes: base,
                    bytesPerRow: Self.pageSize, bytesPerImage: Self.pageSize * Self.pageSize)
            }
        }
    }
}
