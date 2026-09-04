#if DEBUG
    import AppKit
    import SwiftUI

    /// The maths specimen: every construct the renderer draws, in one frame.
    ///
    /// `MathText` is verified two ways and neither is enough alone. `MathText.Check` reads
    /// the *linear* form over the whole corpus and catches mechanical failures — a macro
    /// that was never consumed, a span that never closed. It cannot see a fraction rule
    /// half a point off the maths axis, an accent centred on the wrong glyph, or a variable
    /// that lost its italic, because none of those exist in the linearised read-out at all.
    ///
    /// This is the other half: a page of deliberately awkward notation, rendered through the
    /// real `MathTextView` at real sizes, so that any regression in the geometry lands in
    /// one PNG a human can read. It is not a pass/fail gate — it is the frame to look at.
    ///
    /// `MATHTREE_MATH_SPECIMEN=<dir>` writes it and exits.
    enum MathSpecimen {

        /// The gauntlet. Each line is here because it broke something or could.
        static let lines: [(String, String)] = [
            ("fraction", #"The mean value theorem gives $f'(c) = \frac{f(b) - f(a)}{b - a}$ for some $c$."#),
            ("nested", #"A continued form: $\cfrac{1}{1 + \cfrac{1}{1 + x}}$, and $\dfrac{\frac{a}{b}}{\frac{c}{d}}$."#),
            ("in a script", #"The tail bound $e^{-\frac{t^2}{2\sigma^2}}$ and the rate $r^{1/n}$."#),
            ("radical", #"$\sqrt{2}$, $\sqrt{x^2 + y^2}$, $\sqrt[3]{x}$, and $\sqrt{\frac{n}{n-1}}$."#),
            ("binomial", #"$\binom{n}{k} = \frac{n!}{k!(n-k)!}$, and $\binom{2n}{n} \approx \frac{4^n}{\sqrt{\pi n}}$."#),
            ("accents", #"$\hat{p}$, $\bar{X}_n$, $\vec{v}$, $\tilde{f}$, $\dot{x}$, $\ddot{x}$, $\widehat{\beta}$."#),
            ("rules", #"$\overline{A \cup B} = \overline{A} \cap \overline{B}$, and $\underline{\lim} \, a_n$."#),
            ("operators", #"$\sum_{i=1}^{n} X_i$, $\int_0^1 f(x)\,dx$, $\prod_{k} p_k$, $\lim_{x \to 0} \frac{\sin x}{x} = 1$."#),
            ("upright", #"$\operatorname{Var}(X) = \mathbb{E}[X^2] - (\mathbb{E}[X])^2$ and $\Pr(A \mid B)$."#),
            ("text mode", #"$x = 1 \text{ if } n \text{ is even}$, with $\mathrm{d}x$ and $\log n$."#),
            ("greek", #"$\alpha, \beta, \gamma, \theta, \mu, \sigma^2, \varepsilon > 0, \Delta x, \Omega, \lambda$."#),
            ("delimiters", #"$\left( \frac{a}{b} \right)^2$, $\left| \frac{x}{y} \right|$, $\langle u, v \rangle$."#),
            ("relations", #"$(A, \le)$ is a poset; $a \equiv b \pmod{n}$; $X \sim \mathcal{N}(\mu, \sigma^2)$."#),
            ("emphasis", "Emphasis is set in *italic prose*, not in asterisks, and $x$ is a variable."),
            ("prose+maths", #"If $f$ is continuous on $[a,b]$ and differentiable on $(a,b)$, then there is a $c \in (a,b)$ with $f'(c) = \frac{f(b) - f(a)}{b - a}$, which is the whole statement and it has to wrap."#),
        ]

        @MainActor
        static func runIfRequested() {
            let environment = ProcessInfo.processInfo.environment
            guard let directory = environment["MATHTREE_MATH_SPECIMEN"], !directory.isEmpty
            else { return }
            let root = URL(fileURLWithPath: directory)
            write(into: root)
            print("math-specimen: wrote to \(root.path)")
            fflush(stdout)
            exit(0)
        }

        /// Written by every `PanelShot` run as well, so the frame is refreshed by the
        /// same command that refreshes the panels rather than only when someone
        /// remembers this one exists.
        @MainActor
        static func write(into root: URL) {
            write(
                AnyView(SpecimenView()), to: root.appendingPathComponent("math-specimen.png"),
                size: CGSize(width: 1180, height: 1180))
        }

        private struct SpecimenView: View {
            var body: some View {
                let theme = ThemeStore.shared.theme
                return VStack(alignment: .leading, spacing: 0) {
                    Text("MATHS SPECIMEN · \(theme.isDark ? "DARK" : "LIGHT")")
                        .font(Typeface.mono(10, .medium))
                        .tracking(Typeface.tracking(0.18, at: 10))
                        .foregroundStyle(theme.eyebrow.color)
                        .padding(.bottom, 20)
                    ForEach(Array(MathSpecimen.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text(line.0)
                                .font(Typeface.mono(9.5))
                                .foregroundStyle(theme.eyebrowCount.color)
                                .frame(width: 86, alignment: .trailing)
                            MathTextView(
                                source: line.1, size: 16,
                                color: theme.ink.color,
                                face: theme.isDark ? .sans : .serif
                            )
                            .lineSpacing(7)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                    }
                    // The same gauntlet at the smallest size the app sets maths at, which
                    // is where a rule thickness rounds to nothing and an accent collides.
                    Text("AT 11 PT")
                        .font(Typeface.mono(9.5, .medium))
                        .tracking(Typeface.tracking(0.18, at: 9.5))
                        .foregroundStyle(theme.eyebrow.color)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    MathTextView(
                        source: MathSpecimen.lines[4].1 + " " + MathSpecimen.lines[5].1,
                        size: 11, color: theme.inkMuted.color)
                }
                .padding(34)
                .frame(width: 1180, height: 1180, alignment: .topLeading)
                .background(theme.canvasEdge.color)
            }
        }

        @MainActor
        private static func write(_ view: AnyView, to url: URL, size: CGSize) {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            host.appearance = NSAppearance(
                named: ThemeStore.shared.theme.isDark ? .darkAqua : .aqua)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
#endif
