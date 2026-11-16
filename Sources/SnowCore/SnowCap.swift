import Foundation

/// Snow that left a cap: a position, an amount (pt²), a velocity and the cap it came from
/// (0 = none). Turned into debris by the world.
public struct SnowSpill: Equatable, Sendable {
    public var position: SIMD2<Float>
    public var mass: Float
    public var velocity: SIMD2<Float>
    public var source: UInt32

    public init(position: SIMD2<Float>, mass: Float, velocity: SIMD2<Float> = .zero, source: UInt32 = 0) {
        self.position = position
        self.mass = mass
        self.velocity = velocity
        self.source = source
    }
}

/// Heightmap of settled snow on one window's top edge.
///
/// Columns are spaced ~`Config.capColumnSpacing` apart across the full window width. Heights are
/// relative to the window's top edge; near the ends the *base* follows the rounded window corner
/// down, so snow slides along the arc and melts off the ends. Fresh snow first lands in `incoming` and
/// eases into `heights`, so the cap grows smoothly instead of in visible steps.
public final class SnowCap {
    public let id: UInt32
    public private(set) var frame: Rect
    public private(set) var heights: [Float]
    /// Offset of the surface under each column below the top edge (≤ 0, pt).
    public private(set) var base: [Float]
    /// Deposited snow not yet eased into `heights` (pt).
    private var incoming: [Float]
    /// Per-column maximum height (lumpy, pt).
    private var ceiling: [Float]
    public private(set) var spacing: Float
    public let cornerRadius: Float
    /// Maximum snow height (pt); see `setMaxHeight`.
    public private(set) var maxHeight: Float
    /// Visible x-intervals of the top edge (absolute pt), updated by the world.
    public internal(set) var visible: [Interval] = []
    /// Whether the window is currently in the window list.
    public internal(set) var isPresent = true
    /// Simulation time the window last moved (s).
    public internal(set) var lastMoveTime: Float = -.infinity
    private let lumpPhase: Float
    /// Snow that slid over the ends and melted since creation (pt²); for mass bookkeeping.
    public private(set) var meltedMass: Float = 0
    /// False once relaxation found nothing to move; any change to the heights clears it.
    /// Settled caps skip relaxation entirely (most caps, most of the time).
    public private(set) var isSettled = false
    private var pendingIncoming = false

    public init(id: UInt32, frame: Rect, cornerRadius: Float, lumpPhase: Float = 0,
                maxHeight: Float = Config.capMaxHeight) {
        self.id = id
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.maxHeight = maxHeight
        self.lumpPhase = lumpPhase
        heights = []
        base = []
        incoming = []
        ceiling = []
        spacing = Config.capColumnSpacing
        rebuildColumns(width: frame.width)
    }

    public var columnCount: Int { heights.count }
    public var edgeY: Float { frame.maxY }

    /// Total snow on the cap, including snow still easing in (pt²).
    public var mass: Float {
        (heights.reduce(0, +) + incoming.reduce(0, +)) * spacing
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
        let weightSum = Float((radius + 1) * (radius + 1))
        var added: Float = 0
        for offset in -radius...radius {
            let index = center + offset
            guard index >= 0, index < columnCount else { continue }
            let share = amount * Float(radius + 1 - abs(offset)) / weightSum / spacing
            let room = max(0, ceiling[index] - heights[index] - incoming[index])
            let delta = min(share, room)
            incoming[index] += delta
            added += delta * spacing
        }
        if added > 0 {
            isSettled = false
            pendingIncoming = true
        }
        return added
    }

    /// Fills every column to `fraction` of its ceiling (`--instant-snow`), then settles it.
    public func fill(fraction: Float) {
        for index in heights.indices {
            heights[index] = max(heights[index], ceiling[index] * fraction)
        }
        isSettled = false
        var discard: [SnowSpill] = []
        for _ in 0..<200 { relax(dt: 1.0 / 30, spills: &discard) }
    }

    /// Changes the maximum height. Lowering it lets the excess settle down to the new ceiling
    /// (it melts away over the ends rather than raining down).
    public func setMaxHeight(_ value: Float) {
        guard value != maxHeight else { return }
        let scale = value / maxHeight
        maxHeight = value
        for index in ceiling.indices {
            ceiling[index] *= scale
            if heights[index] > ceiling[index] {
                meltedMass += (heights[index] - ceiling[index]) * spacing
                heights[index] = ceiling[index]
            }
        }
        isSettled = false
    }

    /// Removes all snow.
    public func clear() {
        for index in heights.indices {
            heights[index] = 0
            incoming[index] = 0
        }
        pendingIncoming = false
    }

    // MARK: Relaxation

    /// Eases fresh snow in, then relaxes: wherever the surface is steeper than the angle of
    /// repose, snow moves downhill. Snow above `Config.capEdgeHold` on an end column slides over
    /// the corner and melts (`meltedMass`).
    public func relax(dt: Float, spills: inout [SnowSpill]) {
        let count = columnCount
        guard count >= 2, !isSettled else { return }
        if pendingIncoming {
            let ease = min(1, Config.depositEaseRate * dt)
            var remaining = false
            for index in 0..<count where incoming[index] > 0 {
                let moved = incoming[index] < 1e-4 ? incoming[index] : incoming[index] * ease
                incoming[index] -= moved
                heights[index] += moved
                if incoming[index] > 0 { remaining = true }
            }
            pendingIncoming = remaining
        }
        var movedAny = false

        let maxRise = Config.reposeSlope * spacing
        let rate = Config.relaxRate
        for _ in 0..<Config.relaxPasses {
            for index in 0..<(count - 1) {
                let left = base[index] + heights[index]
                let right = base[index + 1] + heights[index + 1]
                let difference = left - right
                let excess = abs(difference) - maxRise
                guard excess > 0 else { continue }
                let moved: Float
                if difference > 0 {
                    moved = min(excess * 0.5 * rate, heights[index])
                    heights[index] -= moved
                    heights[index + 1] += moved
                } else {
                    moved = min(excess * 0.5 * rate, heights[index + 1])
                    heights[index + 1] -= moved
                    heights[index] += moved
                }
                // Sub-micron transfers are invisible (e.g. bare corner arcs steeper than repose);
                // ignoring them lets caps settle.
                if moved > 1e-4 { movedAny = true }
            }
        }
        let melted = drain(column: 0) + drain(column: count - 1)
        meltedMass += melted
        if !movedAny && !pendingIncoming && melted < 1e-4 { isSettled = true }
    }

    private func drain(column: Int) -> Float {
        let excess = heights[column] - Config.capEdgeHold
        guard excess > 0 else { return 0 }
        let moved = excess * Config.relaxRate
        heights[column] -= moved
        return moved * spacing
    }

    // MARK: Interactions

    /// Follows the window to `newFrame`. On a width change the columns are re-anchored to the
    /// edge that did not move; snow on columns that no longer exist is reported as spills with a
    /// small outward kick. Returns the rigid displacement (the part of the change that is a move).
    @discardableResult
    public func update(frame newFrame: Rect, spills: inout [SnowSpill]) -> SIMD2<Float> {
        let old = frame
        frame = newFrame
        let displacement = Self.rigidDisplacement(from: old, to: newFrame)
        guard abs(newFrame.width - old.width) > 0.5 else { return displacement }

        flushIncoming()
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

        guard newFrame.width < old.width else { return displacement }
        // Old columns beyond the new extent fall off.
        let kick: Float = anchoredLeft ? Config.resizeSpillHorizontalKick : -Config.resizeSpillHorizontalKick
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
                velocity: SIMD2(kick, Config.resizeSpillVerticalKick), source: id
            ))
        }
        return displacement
    }

    /// Resizes a centred surface such as the Dock. Snow that remains over the new frame keeps
    /// its screen x-coordinate; snow beyond either end falls off both sides.
    public func updateCentered(frame newFrame: Rect, spills: inout [SnowSpill]) {
        let old = frame
        frame = newFrame
        guard abs(newFrame.minX - old.minX) > 0.5 || abs(newFrame.width - old.width) > 0.5 else { return }

        flushIncoming()
        let oldHeights = heights
        let oldSpacing = spacing
        rebuildColumns(width: newFrame.width)
        for index in heights.indices {
            let x = newFrame.minX + Float(index) * spacing
            heights[index] = Self.sample(oldHeights, at: (x - old.minX) / oldSpacing)
        }

        for (index, height) in oldHeights.enumerated() where height > 0 {
            let x = old.minX + Float(index) * oldSpacing
            guard x < newFrame.minX - oldSpacing * 0.5 || x > newFrame.maxX + oldSpacing * 0.5 else { continue }
            let kick = x < newFrame.minX ? -Config.resizeSpillHorizontalKick : Config.resizeSpillHorizontalKick
            appendSpill(&spills, SnowSpill(
                position: SIMD2(x, newFrame.maxY + height * 0.5), mass: height * oldSpacing,
                velocity: SIMD2(kick, Config.resizeSpillVerticalKick), source: id
            ))
        }
    }

    /// Reattaches a cap after its window returns from another Space, without loose snow.
    public func restore(frame newFrame: Rect) {
        var discarded: [SnowSpill] = []
        update(frame: newFrame, spills: &discarded)
    }

    /// Sheds `fraction` (0…1) of the snow on every column, inheriting `velocity`.
    public func shed(fraction: Float, velocity: SIMD2<Float>, spills: inout [SnowSpill]) {
        guard fraction > 0 else { return }
        flushIncoming()
        let fraction = min(fraction, 1)
        for index in heights.indices where heights[index] > 0 {
            let removed = heights[index] * fraction
            heights[index] -= removed
            appendSpill(&spills, SnowSpill(
                position: SIMD2(x(ofColumn: index), surfaceY(ofColumn: index) + removed * 0.5),
                mass: removed * spacing, velocity: velocity, source: id
            ))
        }
    }

    /// Converts the whole cap into spills (window closed, minimized, moved to another Space).
    public func shedAll(velocity: SIMD2<Float>, spills: inout [SnowSpill]) {
        shed(fraction: 1, velocity: velocity, spills: &spills)
    }

    /// Removes the snow crossed by a left-moving blade and returns its area (pt²).
    /// The angled blade directs that mass sideways, outside this side-view heightmap.
    @discardableResult
    public func clearSnow(from oldBladeX: Float, to newBladeX: Float) -> Float {
        guard newBladeX < oldBladeX, oldBladeX > frame.minX,
              newBladeX < frame.maxX else { return 0 }
        // Cross column centres once, regardless of frame rate, including incoming snow.
        let first = max(0, Int(((newBladeX - frame.minX) / spacing).rounded(.up)))
        let last = min(columnCount - 1, Int(((oldBladeX - frame.minX) / spacing).rounded(.up)) - 1)
        guard first <= last else { return 0 }
        var displaced: Float = 0
        for index in first...last {
            displaced += heights[index] + incoming[index]
            heights[index] = 0
            incoming[index] = 0
        }
        if displaced > 0 { isSettled = false }
        return displaced * spacing
    }

    /// Knocks off snow touched by a cursor that moved from `from` to `to` (brush of `radius`).
    /// Only the parts of the cap inside `visible` are touched. Returns the mass removed.
    @discardableResult
    public func brush(from: SIMD2<Float>, to: SIMD2<Float>, radius: Float,
                      velocity: SIMD2<Float>, fraction: Float = 1, spills: inout [SnowSpill]) -> Float {
        let lowX = min(from.x, to.x) - radius
        let highX = max(from.x, to.x) + radius
        guard highX >= frame.minX, lowX <= frame.maxX else { return 0 }
        let lowY = min(from.y, to.y) - radius
        let highY = max(from.y, to.y) + radius
        guard highY >= frame.maxY - cornerRadius, lowY <= frame.maxY + maxHeight + 2 else { return 0 }

        flushIncoming()
        let first = max(0, Int(((lowX - frame.minX) / spacing).rounded(.down)))
        let last = min(columnCount - 1, Int(((highX - frame.minX) / spacing).rounded(.up)))
        guard first <= last else { return 0 }
        var removedMass: Float = 0
        for index in first...last where heights[index] > 0.01 {
            let x = x(ofColumn: index)
            guard Intervals.contains(visible, x) else { continue }
            let bottom = frame.maxY + base[index]
            let top = bottom + heights[index]
            // The column is a vertical segment; it is hit if the cursor path comes within radius.
            let distance = Self.distance(segmentA: from, segmentB: to, columnX: x, bottom: bottom, top: top)
            guard distance <= radius else { continue }
            let removed = heights[index] * min(max(fraction, 0), 1)
            heights[index] -= removed
            removedMass += removed * spacing
            appendSpill(&spills, SnowSpill(
                position: SIMD2(x, top + 1),
                mass: removed * spacing, velocity: velocity, source: id
            ))
        }
        return removedMass
    }

    // MARK: Private

    private func flushIncoming() {
        for index in heights.indices where incoming[index] > 0 {
            heights[index] += incoming[index]
            incoming[index] = 0
        }
        pendingIncoming = false
        isSettled = false
    }

    private func rebuildColumns(width: Float) {
        let count = max(2, Int((width / Config.capColumnSpacing).rounded()) + 1)
        spacing = width / Float(count - 1)
        heights = Array(repeating: 0, count: count)
        incoming = Array(repeating: 0, count: count)
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
            return maxHeight * (lumpiness + (1 - lumpiness) * min(max(wave, 0), 1))
        }
    }

    /// The move part of a frame change: both vertical edges shifting the same way. A resize from
    /// one side (one edge fixed) is not a move.
    static func rigidDisplacement(from old: Rect, to new: Rect) -> SIMD2<Float> {
        let left = new.minX - old.minX
        let right = new.maxX - old.maxX
        let dx: Float = left * right > 0 ? (abs(left) < abs(right) ? left : right) : 0
        let top = new.maxY - old.maxY
        let bottom = new.minY - old.minY
        let dy: Float = top * bottom > 0 ? (abs(top) < abs(bottom) ? top : bottom) : 0
        return SIMD2(dx, dy)
    }

    /// How far a rounded corner of `radius` sits below the top edge at `fromEdge` pt from the side.
    static func cornerDrop(fromEdge: Float, radius: Float) -> Float {
        guard radius > 0, fromEdge < radius else { return 0 }
        let dx = radius - max(fromEdge, 0)
        return -(radius - (radius * radius - dx * dx).squareRoot())
    }

    /// Distance between segment AB and the vertical segment x = columnX, y ∈ [bottom, top].
    static func distance(segmentA a: SIMD2<Float>, segmentB b: SIMD2<Float>,
                         columnX: Float, bottom: Float, top: Float) -> Float {
        // Sample the column at bottom, middle and top, plus the closest point of AB to the column
        // line; exact enough for a 10 pt brush over ≤ 14 pt columns.
        func pointToSegment(_ p: SIMD2<Float>) -> Float {
            let ab = b - a
            let lengthSquared = (ab * ab).sum()
            let t = lengthSquared > 0 ? min(max(((p - a) * ab).sum() / lengthSquared, 0), 1) : 0
            let closest = a + ab * t
            let d = p - closest
            return (d * d).sum().squareRoot()
        }
        var best = min(pointToSegment(SIMD2(columnX, bottom)),
                       pointToSegment(SIMD2(columnX, (bottom + top) * 0.5)),
                       pointToSegment(SIMD2(columnX, top)))
        // Where AB crosses x = columnX, the distance is the vertical gap to the column span.
        if (a.x - columnX) * (b.x - columnX) <= 0, a.x != b.x {
            let t = (columnX - a.x) / (b.x - a.x)
            let y = a.y + (b.y - a.y) * t
            best = min(best, y < bottom ? bottom - y : (y > top ? y - top : 0))
        }
        return best
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
