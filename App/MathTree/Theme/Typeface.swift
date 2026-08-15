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
