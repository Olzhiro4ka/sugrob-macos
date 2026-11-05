import Testing
@testable import SnowCore

struct LaunchOptionsTests {
    @Test func defaultsAreOff() {
        let options = LaunchOptions(arguments: ["/path/Sugrob"])
        #expect(options == LaunchOptions())
    }

    @Test func parsesAllFlags() {
        let options = LaunchOptions(arguments: [
            "/path/Sugrob", "--hud", "--debug-surfaces", "--instant-snow", "--seed", "123",
        ])
        #expect(options.hud)
        #expect(options.debugSurfaces)
        #expect(options.instantSnow)
        #expect(options.seed == 123)
    }

    @Test func parsesSeedWithEquals() {
        #expect(LaunchOptions(arguments: ["x", "--seed=77"]).seed == 77)
    }

    @Test func ignoresUnknownAndSkipsExecutable() {
        let options = LaunchOptions(arguments: ["--hud", "-NSDocumentRevisionsDebugMode", "YES", "--seed", "nope"])
        #expect(!options.hud)
        #expect(options.seed == nil)
    }
}
