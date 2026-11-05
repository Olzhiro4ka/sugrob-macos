/// Debug flags parsed from the process arguments (see CLAUDE.md, "Commands").
public struct LaunchOptions: Equatable, Sendable {
    /// `--debug-surfaces`: draw detected surfaces, Dock frame and occlusion clipping.
    public var debugSurfaces = false
    /// `--hud`: show fps, particle counts, ms per tick, window-poll ms.
    public var hud = false
    /// `--instant-snow`: pre-fill all caps.
    public var instantSnow = false
    /// `--seed N`: deterministic RNG seed. `nil` means "pick one at launch".
    public var seed: UInt64?

    public init() {}

    /// Parses arguments, ignoring anything unknown (macOS passes e.g. `-NSDocumentRevisionsDebugMode`).
    /// The first element is expected to be the executable path and is skipped.
    public init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--debug-surfaces": debugSurfaces = true
            case "--hud": hud = true
            case "--instant-snow": instantSnow = true
            case "--seed":
                if let value = iterator.next() { seed = UInt64(value) }
            default:
                if argument.hasPrefix("--seed="), let value = UInt64(argument.dropFirst("--seed=".count)) {
                    seed = value
                }
            }
        }
    }
}
