import simd

/// Oklch → sRGB, because the redesign is authored in Oklch and nothing else will
/// reproduce it.
///
/// The design specifies every content fill as `oklch(L C H)` with the branch hue
/// held fixed and only lightness and chroma moving with the score. That is the
/// whole point of the encoding: in Oklch a lightness ramp is *perceptually* a
/// lightness ramp, so "more solid = brighter" (dark) and "more solid = denser
/// ink" (light) hold evenly across twelve different branch hues. The same walk in
/// HSV does not — `hsv` value at hue 58 (yellow) is far lighter than at hue 276
/// (violet), so an equally-known node in two branches would read as two different
/// scores.
///
/// `ScoreRamp` in GraphCore keeps its HSV walk: it owns the *model's* colour
/// (§4.5's blue → teal → green), which is still what the probe prints and what
/// the score tests pin. This is the display layer's own space, and it is here
/// rather than in GraphCore for that reason.
enum OKLCH {
    /// `oklch(lightness chroma hue)` with `hue` in degrees, gamma-encoded sRGB out,
    /// each component clamped to 0…1.
    ///
    /// Out-of-gamut triples are clamped per channel rather than chroma-reduced.
    /// Every colour the design asks for is well inside sRGB (chroma ≤ 0.16), so a
    /// gamut-mapping pass would be code that never runs.
    static func srgb(_ lightness: Double, _ chroma: Double, _ hueDegrees: Double)
        -> SIMD3<Double>
    {
        let hue = hueDegrees * .pi / 180
        let a = chroma * cos(hue)
        let b = chroma * sin(hue)

        // Oklab → LMS′ → LMS (Björn Ottosson's matrices).
        let lCube = lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b
        let mCube = lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b
        let sCube = lightness - 0.089_484_177_5 * a - 1.291_485_548_0 * b
        let l = lCube * lCube * lCube
        let m = mCube * mCube * mCube
        let s = sCube * sCube * sCube

        // LMS → linear sRGB.
        let red = 4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s
        let green = -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s
        let blue = -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s

        return SIMD3(encode(red), encode(green), encode(blue))
    }

    /// The same colour as a packed rgba8 word, ready for an instance buffer.
    static func packed(_ lightness: Double, _ chroma: Double, _ hueDegrees: Double,
                       alpha: Double = 1) -> UInt32
    {
        let rgb = srgb(lightness, chroma, hueDegrees)
        return packRGBA(Float(rgb.x), Float(rgb.y), Float(rgb.z), Float(alpha))
    }

    /// Linear-light → gamma-encoded sRGB. The drawable is `bgra8Unorm`, not
    /// `bgra8Unorm_srgb`, so what is packed into an instance word is what the
    /// display receives — the encode has to happen here.
    private static func encode(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.003_130_8
            ? clamped * 12.92
            : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
