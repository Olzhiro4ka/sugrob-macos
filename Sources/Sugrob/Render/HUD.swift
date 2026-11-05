import AppKit

/// `--hud`: a small stats label on the primary overlay, plus a line on stderr every 5 s
/// (so numbers can be read when launched from a terminal).
@MainActor
final class HUD {
    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.drawsBackground = true
        label.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        return label
    }()

    struct Frame {
        /// Time since the previous tick (s); its max shows hitches.
        var interval: Double
        /// Cumulative dropped frames.
        var drops: Int
        /// Input polling + simulation (s).
        var tick: Double
        /// CPU encode time of all overlays (s).
        var render: Double
        /// Window-list poll duration if a poll happened this frame (s).
        var poll: Double?
        var flakes: Int
        var debris: Int
        /// Settled snow (pt²).
        var snow: Float
        var windows: Int
        var caps: Int
        var segments: Int
        var fps: Int
    }

    private var windowStart = CACurrentMediaTime()
    private var lastLog = CACurrentMediaTime()
    private var frames = 0
    private var tickSum: Double = 0
    private var tickMax: Double = 0
    private var renderSum: Double = 0
    private var renderMax: Double = 0
    private var intervalMax: Double = 0
    private var dropsAtWindowStart = 0
    private var pollSum: Double = 0
    private var pollMax: Double = 0
    private var polls = 0
    private var cpuAtWindowStart = ProcessStats.cpuSeconds()

    /// Places the label at the top-left of `view`, just below the menu bar.
    func attach(to view: NSView) {
        label.removeFromSuperview()
        view.addSubview(label)
        label.frame.origin = CGPoint(x: 12, y: view.bounds.height - 76)
        label.autoresizingMask = [.minYMargin, .maxXMargin]
    }

    func record(_ frame: Frame) {
        frames += 1
        tickSum += frame.tick
        tickMax = max(tickMax, frame.tick)
        renderSum += frame.render
        renderMax = max(renderMax, frame.render)
        intervalMax = max(intervalMax, frame.interval)
        if let poll = frame.poll {
            polls += 1
            pollSum += poll
            pollMax = max(pollMax, poll)
        }

        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }

        let cpuNow = ProcessStats.cpuSeconds()
        let cpuPercent = (cpuNow - cpuAtWindowStart) / elapsed * 100
        let line1 = String(
            format: "fps %4.1f (cap %d, worst gap %.1f ms, drops %d) · tick %.3f ms (max %.3f) · poll %.2f ms (max %.2f, %d/s) · render %.3f ms (max %.2f)",
            Double(frames) / elapsed, frame.fps, intervalMax * 1000, frame.drops - dropsAtWindowStart,
            tickSum / Double(frames) * 1000, tickMax * 1000,
            polls > 0 ? pollSum / Double(polls) * 1000 : 0, pollMax * 1000, polls,
            renderSum / Double(frames) * 1000, renderMax * 1000
        )
        let line2 = String(
            format: "flakes %d · debris %d · snow %.0f pt² · windows %d · caps %d · segments %d · cpu %.1f%% · mem %.1f MB",
            frame.flakes, frame.debris, frame.snow, frame.windows, frame.caps, frame.segments,
            cpuPercent, ProcessStats.footprintMegabytes()
        )
        label.stringValue = " " + line1 + " \n " + line2 + " "
        label.sizeToFit()

        if now - lastLog >= 5 {
            lastLog = now
            FileHandle.standardError.write(Data(("[hud] " + line1 + " · " + line2 + "\n").utf8))
        }

        windowStart = now
        cpuAtWindowStart = cpuNow
        frames = 0
        tickSum = 0
        tickMax = 0
        renderSum = 0
        renderMax = 0
        intervalMax = 0
        dropsAtWindowStart = frame.drops
        pollSum = 0
        pollMax = 0
        polls = 0
    }
}

/// Process CPU time and memory via public BSD APIs.
enum ProcessStats {
    /// User + system CPU time consumed by this process (s).
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Physical footprint (MB), the number Activity Monitor shows as "Memory".
    static func footprintMegabytes() -> Double {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return 0 }
        return Double(info.ri_phys_footprint) / 1_048_576
    }
}
