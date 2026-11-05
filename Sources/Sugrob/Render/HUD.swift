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

    private var windowStart = CACurrentMediaTime()
    private var lastLog = CACurrentMediaTime()
    private var frames = 0
    private var tickSum: Double = 0
    private var tickMax: Double = 0
    private var renderSum: Double = 0
    private var cpuAtWindowStart = ProcessStats.cpuSeconds()

    /// Places the label at the top-left of `view`, just below the menu bar.
    func attach(to view: NSView) {
        label.removeFromSuperview()
        view.addSubview(label)
        label.frame.origin = CGPoint(x: 12, y: view.bounds.height - 60)
        label.autoresizingMask = [.minYMargin, .maxXMargin]
    }

    /// Records one frame. `tick` = input polling + simulation, `render` = CPU encode time (s).
    func record(tick: Double, render: Double, flakes: Int, fps: Int) {
        frames += 1
        tickSum += tick
        tickMax = max(tickMax, tick)
        renderSum += render

        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }

        let cpuNow = ProcessStats.cpuSeconds()
        let cpuPercent = (cpuNow - cpuAtWindowStart) / elapsed * 100
        let text = String(
            format: "fps %4.1f (cap %d) · flakes %d · tick %.3f ms (max %.3f) · render %.3f ms · cpu %.1f%% · mem %.1f MB",
            Double(frames) / elapsed, fps, flakes,
            tickSum / Double(frames) * 1000, tickMax * 1000,
            renderSum / Double(frames) * 1000,
            cpuPercent, ProcessStats.footprintMegabytes()
        )
        label.stringValue = " " + text + " "
        label.sizeToFit()

        if now - lastLog >= 5 {
            lastLog = now
            FileHandle.standardError.write(Data(("[hud] " + text + "\n").utf8))
        }

        windowStart = now
        cpuAtWindowStart = cpuNow
        frames = 0
        tickSum = 0
        tickMax = 0
        renderSum = 0
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
