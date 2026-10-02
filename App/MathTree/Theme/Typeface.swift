import AppKit
import SwiftUI

/// The redesign's three faces, resolved at runtime with system fallbacks.
///
/// It asks for IBM Plex Sans, IBM Plex Mono and Source Serif 4. None of them ship
/// with macOS, and none of them are bundled here — a design import should not add
/// a megabyte of font binaries to a repository whose ground rules keep third-party
/// dependencies out. So each role names the design's face first and falls back to
/// the system's nearest equivalent: SF Pro, SF Mono, and New York.
///
/// The fallbacks are close enough that the *roles* survive, which is what the
/// design is actually built on — a mono, wide-tracked, uppercase eyebrow reads as
/// an eyebrow in SF Mono too, and the light direction's serif/sans contrast holds
/// with New York against SF Pro. If the Plex family is installed, the frames match
/// the design document exactly.
///
/// The one bundled face is the fourth role, **reading**: lesson prose and every
/// `$…$` span, set in Latin Modern — Computer Modern, the face a LaTeX document on
/// Overleaf sets in by default — so the mathematics reads the way the reader has
/// seen it typeset everywhere else. It is the exception to the rule above because
/// no fallback survives the role: the point of the face is that it *is* Computer
/// Modern. Five OpenType files, GUST Font License, registered for this process
/// only (`App/MathTree/Fonts/README.md`).
enum Typeface {
    /// Resolved once: `availableFontFamilies` walks the font registry, and these
    /// are asked for on every text run in the app.
    private static let installed: Set<String> = Set(NSFontManager.shared.availableFontFamilies)

    private static func family(_ candidates: [String]) -> String? {
        candidates.first { installed.contains($0) }
    }

    static let sansFamily = family(["IBM Plex Sans"])
    static let monoFamily = family(["IBM Plex Mono"])
    static let serifFamily = family(["Source Serif 4", "Source Serif Pro", "Source Serif"])

    // MARK: - SwiftUI

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let sansFamily else { return .system(size: size, weight: weight) }
        return .custom(sansFamily, fixedSize: size).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let monoFamily else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(monoFamily, fixedSize: size).weight(weight)
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let serifFamily else { return .system(size: size, weight: weight, design: .serif) }
        return .custom(serifFamily, fixedSize: size).weight(weight)
    }

    /// The maths variable face. Every serif this app can resolve to — Source Serif 4, and
    /// New York as the fallback — ships a real italic, so this is a face selection rather
    /// than a slant applied to the roman.
    static func serifItalic(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        serif(size, weight).italic()
    }

    static func sansItalic(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        sans(size, weight).italic()
    }

    /// The reading face — Latin Modern Roman, with Latin Modern Math behind it for the
    /// symbols a text face does not carry. The serif when the bundle is missing.
    static func reading(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font(nsReading(size, MathTextView.nsWeight(weight)))
    }

    static func readingItalic(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font(nsReading(size, MathTextView.nsWeight(weight), italic: true))
    }

    /// Letter-spacing the way the design writes it: a multiple of the font size.
    /// `0.18em` at 10 pt is 1.8 pt of tracking.
    static func tracking(_ em: CGFloat, at size: CGFloat) -> CGFloat { em * size }

    // MARK: - AppKit

    /// The same three roles as `NSFont`, for the label atlas — map labels are
    /// rasterised through Core Text, not laid out by SwiftUI.
    static func nsSans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        resolved(sansFamily, size: size, weight: weight)
            ?? .systemFont(ofSize: size, weight: weight)
    }

    static func nsMono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        resolved(monoFamily, size: size, weight: weight)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func nsSerif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        if let font = resolved(serifFamily, size: size, weight: weight) { return font }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The reading face as `NSFont`, for `MathBox`'s Core Text layout and the SwiftUI
    /// wrappers above. Latin Modern Roman carries the cascade list itself, so a `∑`,
    /// `≤` or `∈` in a run — glyphs Computer Modern's text fonts never had — is drawn
    /// from Latin Modern Math rather than from whatever the system picks.
    static func nsReading(
        _ size: CGFloat, _ weight: NSFont.Weight = .regular, italic: Bool = false
    ) -> NSFont {
        guard let readingFamily else {
            return italic ? nsItalic(nsSerif(size, weight)) : nsSerif(size, weight)
        }
        // Latin Modern Roman 10 has two weights; anything from semibold up is the bold.
        let bold = weight.rawValue >= NSFont.Weight.semibold.rawValue
        let face = [bold ? "Bold" : nil, italic ? "Italic" : nil].compactMap { $0 }
            .joined(separator: " ")
        var attributes: [NSFontDescriptor.AttributeName: Any] = [
            .family: readingFamily, .face: "10 \(face.isEmpty ? "Regular" : face)",
        ]
        if let mathFamily = readingMathFamily {
            attributes[.cascadeList] = [NSFontDescriptor(fontAttributes: [.family: mathFamily])]
        }
        return NSFont(descriptor: NSFontDescriptor(fontAttributes: attributes), size: size)
            ?? (italic ? nsItalic(nsSerif(size, weight)) : nsSerif(size, weight))
    }

    /// Latin Modern Math, for a glyph the reading face lacks when a path is wanted
    /// rather than a run (`MathBox`'s stretched delimiters).
    static func nsReadingMath(_ size: CGFloat) -> NSFont? {
        readingMathFamily.flatMap {
            NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: $0]), size: size)
        }
    }

    /// A maths italic run as the reading face draws it. Computer Modern sets a Greek
    /// variable from its maths italic (`cmmi`), which Latin Modern Math carries at the
    /// Mathematical Alphanumeric code points, not as a slanted `U+03B1`; mapping there
    /// is what makes `$\alpha$` the TeX α rather than an upright one. Rendering only:
    /// `MathText.plainText` and the source keep the ordinary letters.
    static func readingMathItalic(_ text: String) -> String {
        guard readingMathFamily != nil else { return text }
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            output.append(mathItalicGreek[scalar.value].flatMap(Unicode.Scalar.init) ?? scalar)
        }
        return String(output)
    }

    private static let mathItalicGreek: [UInt32: UInt32] = {
        // α…ω (with ς) run contiguously in both blocks; the variant forms follow ∂.
        var table: [UInt32: UInt32] = [:]
        for offset in 0...0x18 { table[0x3B1 + UInt32(offset)] = 0x1D6FC + UInt32(offset) }
        let variants: [(UInt32, UInt32)] = [
            (0x3F5, 0x1D716), (0x3D1, 0x1D717), (0x3F0, 0x1D718),
            (0x3D5, 0x1D719), (0x3F1, 0x1D71A), (0x3D6, 0x1D71B),
        ]
        for (letter, italic) in variants { table[letter] = italic }
        return table
    }()

    /// Registered once, for this process. The bundle sits beside the binary under
    /// `swift run` and in `Contents/Resources` inside the app (`bundle-app.sh`);
    /// `Bundle.module` is not used because it traps when the bundle is absent, and a
    /// missing face should fall back to the serif, not stop the app.
    private static let readingFamilies: (text: String?, math: String?) = {
        let bundleName = "MathTree_MathTree.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent(bundleName),
        ].compactMap { $0 }
        guard
            let fonts = candidates.map({ $0.appendingPathComponent("Fonts") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let files = try? FileManager.default.contentsOfDirectory(
                at: fonts, includingPropertiesForKeys: nil)
        else { return (nil, nil) }
        var families: Set<String> = []
        for file in files where file.pathExtension == "otf" {
            // An already-registered face (a second scene, a test host) is not an error.
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            for descriptor in
                (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])
                ?? []
            {
                if let family = CTFontDescriptorCopyAttribute(
                    descriptor, kCTFontFamilyNameAttribute) as? String
                {
                    families.insert(family)
                }
            }
        }
        return (
            families.contains("Latin Modern Roman") ? "Latin Modern Roman" : nil,
            families.contains("Latin Modern Math") ? "Latin Modern Math" : nil
        )
    }()

    static var readingFamily: String? { readingFamilies.text }
    private static var readingMathFamily: String? { readingFamilies.math }

    /// The same three roles slanted, for the offscreen maths layout — `MathBox` draws
    /// through Core Text and cannot ask SwiftUI for a face.
    static func nsItalic(_ font: NSFont) -> NSFont {
        let traits = font.fontDescriptor.symbolicTraits.union(.italic)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        if let italic = NSFont(descriptor: descriptor, size: font.pointSize),
            italic.fontDescriptor.symbolicTraits.contains(.italic)
        {
            return italic
        }
        // A family with no italic face: slant the roman rather than silently setting
        // variables upright, which would erase the one distinction the italic exists for.
        // The matrix carries the point size, so the font is then asked for at size 0.
        var slant = AffineTransform(scale: font.pointSize)
        slant.append(AffineTransform(m11: 1, m12: 0, m21: 0.21, m22: 1, tX: 0, tY: 0))
        let sheared = font.fontDescriptor.withMatrix(slant)
        return NSFont(descriptor: sheared, size: 0) ?? font
    }

    private static func resolved(_ family: String?, size: CGFloat, weight: NSFont.Weight)
        -> NSFont?
    {
        guard let family else { return nil }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size)
    }
}
