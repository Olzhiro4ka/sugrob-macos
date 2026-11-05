/// Fixed-capacity pool of knocked-off snow particles, struct-of-arrays.
///
/// Particles fall under gravity with light drag and may land on another visible cap (that is how
/// snow transfers from window to window). They never land on the cap they came from.
public struct DebrisPool {
    public let capacity: Int
    public private(set) var count = 0

    /// Render data per particle: (x, y, radius, alpha).
    public private(set) var sprites: [SIMD4<Float>]
    /// Velocity per particle (pt/s); the renderer stretches particles along it.
    public private(set) var velocities: [SIMD2<Float>]
    private var masses: [Float]
    private var ages: [Float]
    private var sources: [UInt32]

    public init(capacity: Int = Config.debrisCapacity) {
        self.capacity = capacity
        sprites = Array(repeating: .zero, count: capacity)
        velocities = Array(repeating: .zero, count: capacity)
        masses = Array(repeating: 0, count: capacity)
        ages = Array(repeating: 0, count: capacity)
        sources = Array(repeating: 0, count: capacity)
    }

    public var totalMass: Float { masses[0..<count].reduce(0, +) }

    /// Splits `spill` into particles of `Config.debrisParticleMass` (stochastic rounding) and
    /// spawns them. Particles that don't fit in the pool are dropped.
    public mutating func spawn(_ spill: SnowSpill, rng: inout SplitMix64) {
        let exact = spill.mass / Config.debrisParticleMass
        var particles = Int(exact)
        if rng.nextUnit() < exact - Float(particles) { particles += 1 }
        for _ in 0..<particles {
            guard count < capacity else { return }
            let index = count
            count += 1
            let jitter = Config.debrisJitter
            let velocity = spill.velocity + SIMD2(
                jitter.x * (2 * rng.nextUnit() - 1),
                jitter.y * (2 * rng.nextUnit() - 1)
            )
            let position = spill.position + SIMD2(2 * rng.nextUnit() - 1, 2 * rng.nextUnit() - 1)
            sprites[index] = SIMD4(position.x, position.y,
                                   rng.next(in: Config.debrisRadius), rng.next(in: Config.debrisOpacity))
            velocities[index] = velocity
            masses[index] = Config.debrisParticleMass
            ages[index] = 0
            sources[index] = spill.source
        }
    }

    /// Advances all particles. `land(previous, current, source, mass)` returns true when the
    /// particle was absorbed by a surface. Particles below `floor` or too old are removed.
    public mutating func step(
        dt: Float, floor: Float,
        land: (SIMD2<Float>, SIMD2<Float>, UInt32, Float) -> Bool
    ) {
        let damping = max(0, 1 - Config.debrisDrag * dt)
        var i = 0
        while i < count {
            var velocity = velocities[i]
            velocity.y -= Config.gravity * dt
            velocity *= damping
            var sprite = sprites[i]
            let previous = SIMD2(sprite.x, sprite.y)
            sprite.x += velocity.x * dt
            sprite.y += velocity.y * dt
            ages[i] += dt
            let current = SIMD2(sprite.x, sprite.y)
            if sprite.y < floor || ages[i] > Config.debrisMaxLife
                || (velocity.y < 0 && land(previous, current, sources[i], masses[i])) {
                remove(at: i)
                continue
            }
            sprites[i] = sprite
            velocities[i] = velocity
            i += 1
        }
    }

    public mutating func removeAll() {
        count = 0
    }

    private mutating func remove(at index: Int) {
        let last = count - 1
        if index != last {
            sprites[index] = sprites[last]
            velocities[index] = velocities[last]
            masses[index] = masses[last]
            ages[index] = ages[last]
            sources[index] = sources[last]
        }
        count = last
    }
}
