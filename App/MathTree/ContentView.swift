import GraphCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Knowledge Tree")
                    .font(.system(size: 34, weight: .light, design: .default))
                    .foregroundStyle(.white)
                Text("content format v\(GraphCore.contentFormatVersion)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
