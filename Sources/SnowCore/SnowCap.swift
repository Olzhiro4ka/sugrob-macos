import Foundation

/// Snow that left a cap: a position, an amount (pt²) and a velocity. Turned into debris by the world.
public struct SnowSpill: Equatable, Sendable {
    public var position: SIMD2<Float>
    public var mass: Float
    public var velocity: SIMD2<Float>

    public init(position: SIMD2<Float>, mass: Float, velocity: SIMD2<Float> = .zero) {
        self.position = position
        self.mass = mass
        self.velocity = velocity
    }
}

/// Heightmap of settled snow on one window's top edge.
///
/// Columns are spaced ~`Config.capColumnSpacing` apart across the full window width. Heights are
/// relative to the window's top edge; near the ends the *base* follows the rounded window corner
/// down, so snow slides along the arc and drips off. Heights are stored relative to the window,
/// so the cap moves rigidly with it.
public final class SnowCap {
    public let id: UInt32
    public private(set) var frame: Rect
    public private(set) var heights: [Float]
    /// Offset of the surface under each column below the top edge (≤ 0, pt).
    public private(set) var base: [Float]
    /// Per-column maximum height (lumpy, pt).
    private var ceiling: [Float]
    public private(set) var spacing: Float
    public let cornerRadius: Float
    /// Visible x-intervals of the top edge (absolute pt), updated by the world.
    public internal(set) var visible: [Interval] = []
    /// Whether the window is currently in the window list.
    public internal(set) var isPresent = true
    private let lumpPhase: Float

    public init(id: UInt32, frame: Rect, cornerRadius: Float, lumpPhase: Float = 0) {
        self.id = id
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.lumpPhase = lumpPhase
        heights = []
        base = []
        ceiling = []
        spacing = Config.capColumnSpacing
        rebuildColumns(width: frame.width)
    }

    public var columnCount: Int { heights.count }
    public var edgeY: Float { frame.maxY }

    /// Total settled snow (pt²).
    public var mass: Float {
        heights.reduce(0, +) * spacing
    }

    public func x(ofColumn index: Int) -> Float {
        frame.minX + Float(index) * spacing
    }

    /// Absolute y of the snow surface at column `index`.
    public func surfaceY(ofColumn index: Int) -> Float {
        frame.maxY + base[index] + heights[index]
    }

    /// Absolute y of the snow surface at `x` (linear between columns), or nil outside the cap.
    public func surfaceY(at x: Float) -> Float? {
        let position = (x - frame.minX) / spacing
        guard position >= 0, position <= Float(columnCount - 1) else { return nil }
        let left = min(Int(position), columnCount - 2)
        let t = position - Float(left)
        let a = base[left] + heights[left]
        let b = base[left + 1] + heights[left + 1]
        return frame.maxY + a + (b - a) * t
    }

    // MARK: Accumulation

    /// Adds `amount` (pt²) of snow centred at `x`, spread over a small triangular kernel and
    /// limited by the column ceilings. Returns how much was actually added.
    @discardableResult
    public func deposit(at x: Float, amount: Float) -> Float {
        let center = Int(((x - frame.minX) / spacing).rounded())
        let radius = Config.depositRadiusColumns
        var weightSum: Float = 0
        for offset in -radius...radius {
            weightSum += Float(radius + 1 - abs(offset))
        }
        var added: Float = 0
        for offset in -radius...radius {
            let index = center + offset
            guard index >= 0, index < columnCount else { continue }
            let share = amount * Float(radius + 1 - abs(offset)) / weightSum / spacing
            let room = max(0, ceiling[index] - heights[index])
            let delta = min(share, room)
            heights[index] += delta
            added += delta * spacing
        }
        return added
    }

    /// Fills every column to `fraction` of its ceiling (`--instant-snow`), then settles it.
    public func fill(fraction: Float) {
        for index in heights.indices {
            heights[index] = max(heights[index], ceiling[index] * fraction)
        }
        var discard: [SnowSpill] = []
        for _ in 0..<200 { relax(spills: &discard) }
    }

    /// Removes all snow.
    public func clear() {
        for index in heights.indices { heights[index] = 0 }
    }

    // MARK: Relaxation

    /// One relaxation step: wherever the surface is steeper than the angle of repose, move snow
    /// downhill. Snow above `Config.capEdgeHold` on an end column spills over the edge.
    public func relax(spills: inout [SnowSpill]) {
        let count = columnCount
        guard count >= 2 else { return }
        let maxRise = Config.reposeSlope * spacing
        let rate = Config.relaxRate
        for _ in 0..<Config.relaxPasses {
            for index in 0..<(count - 1) {
                let left = base[index] + heights[index]
                let right = base[index + 1] + heights[index + 1]
                let difference = left - right
                let excess = abs(difference) - maxRise
                guard excess > 0 else { continue }
                if difference > 0 {
                    let moved = min(excess * 0.5 * rate, heights[index])
                    heights[index] -= moved
                    heights[index + 1] += moved
                } else {
                    let moved = min(excess * 0.5 * rate, heights[index + 1])
                    heights[index + 1] -= moved
                    heights[index] += moved
                }
            }
        }
        spillEnd(column: 0, direction: -1, spills: &spills)
        spillEnd(column: count - 1, direction: 1, spills: &spills)
    }

    private func spillEnd(column: Int, direction: Float, spills: inout [SnowSpill]) {
        let excess = heights[column] - Config.capEdgeHold
        guard excess > 0 else { return }
        let moved = excess * Config.relaxRate
        heights[column] -= moved
        appendSpill(&spills, SnowSpill(
            position: SIMD2(x(ofColumn: column) + direction * spacing * 0.5, surfaceY(ofColumn: column)),
            mass: moved * spacing,
            velocity: SIMD2(direction * 8, 0)
        ))
    }

    // MARK: Moving and resizing

    /// Follows the window to `newFrame`. A pure move just shifts the cap. On a width change the
    /// columns are re-anchored to the edge that did not move; snow on columns that no longer
    /// exist is reported as spills (with a small outward kick).
    public func update(frame newFrame: Rect, spills: inout [SnowSpill]) {
        let old = frame
        frame = newFrame
        guard abs(newFrame.width - old.width) > 0.5 else { return }

        let oldHeights = heights
        let oldSpacing = spacing
        let oldCount = oldHeights.count
        // Anchor to whichever vertical edge moved less.
        let anchoredLeft = abs(newFrame.minX - old.minX) <= abs(newFrame.maxX - old.maxX)

        rebuildColumns(width: newFrame.width)
        for index in heights.indices {
            // Distance of this column from the anchored edge, mapped into the old heightmap.
            let fromAnchor = anchoredLeft
                ? Float(index) * spacing
                : newFrame.width - Float(index) * spacing
            let oldPosition = anchoredLeft
                ? fromAnchor / oldSpacing
                : (old.width - fromAnchor) / oldSpacing
            heights[index] = Self.sample(oldHeights, at: oldPosition)
        }
        // No clamping to the new ceiling: its lumps shift on resize, and the ceiling only limits
        // new deposits. Heights stay physically where they were.

        guard newFrame.width < old.width else { return }
        // Old columns beyond the new extent fall off.
        let kick: Float = anchoredLeft ? 25 : -25
        for oldIndex in 0..<oldCount {
            let fromAnchor = anchoredLeft
                ? Float(oldIndex) * oldSpacing
                : old.width - Float(oldIndex) * oldSpacing
            guard fromAnchor > newFrame.width + oldSpacing * 0.5, oldHeights[oldIndex] > 0 else { continue }
            let xOld = anchoredLeft
                ? newFrame.minX + fromAnchor
                : newFrame.maxX - fromAnchor
            appendSpill(&spills, SnowSpill(
                position: SIMD2(xOld, newFrame.maxY + oldHeights[oldIndex] * 0.5),
                mass: oldHeights[oldIndex] * oldSpacing,
                velocity: SIMD2(kick, 15)
            ))
        }
    }

    /// Converts the whole cap into spills (window closed, minimized, moved to another Space).
    public func shedAll(velocity: SIMD2<Float>, spills: inout [SnowSpill]) {
        for index in heights.indices where heights[index] > 0 {
            appendSpill(&spills, SnowSpill(
                position: SIMD2(x(ofColumn: index), surfaceY(ofColumn: index) - heights[index] * 0.5),
                mass: heights[index] * spacing,
                velocity: velocity
            ))
            heights[index] = 0
        }
    }

    // MARK: Private

    private func rebuildColumns(width: Float) {
        let count = max(2, Int((width / Config.capColumnSpacing).rounded()) + 1)
        spacing = width / Float(count - 1)
        heights = Array(repeating: 0, count: count)
        base = (0..<count).map { index in
            let x = Float(index) * spacing
            let fromEdge = min(x, width - x)
            return Self.cornerDrop(fromEdge: fromEdge, radius: cornerRadius)
        }
        ceiling = (0..<count).map { index in
            let x = Float(index) * spacing
            let wave = 0.5 + 0.35 * sin(x * 2 * Float.pi / Config.capLumpWavelength + lumpPhase)
                + 0.15 * sin(x * 2 * Float.pi / (Config.capLumpWavelength * 0.43) + lumpPhase * 1.7)
            let lumpiness = Config.capCeilingLumpiness
            return Config.capMaxHeight * (lumpiness + (1 - lumpiness) * min(max(wave, 0), 1))
        }
    }

    /// How far a rounded corner of `radius` sits below the top edge at `fromEdge` pt from the side.
    static func cornerDrop(fromEdge: Float, radius: Float) -> Float {
        guard radius > 0, fromEdge < radius else { return 0 }
        let dx = radius - max(fromEdge, 0)
        return -(radius - (radius * radius - dx * dx).squareRoot())
    }

    private static func sample(_ values: [Float], at position: Float) -> Float {
        guard position >= 0, position <= Float(values.count - 1) else { return 0 }
        let left = min(Int(position), values.count - 2)
        let t = position - Float(left)
        return values[left] + (values[left + 1] - values[left]) * t
    }

    private func appendSpill(_ spills: inout [SnowSpill], _ spill: SnowSpill) {
        guard spills.count < Config.maxSpillsPerStep else { return }
        spills.append(spill)
    }
}
