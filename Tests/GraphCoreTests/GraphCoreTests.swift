import Testing

@testable import GraphCore

@Test func contentFormatVersionIsSet() {
    #expect(GraphCore.contentFormatVersion == 1)
}
