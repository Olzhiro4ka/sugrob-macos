/// All simulation tunables live here. Every value documents its unit.
public enum Config {
    /// Default RNG seed when `--seed` is not given; the app mixes in the launch time.
    public static let defaultSeed: UInt64 = 0x5_06D0_0B
}
