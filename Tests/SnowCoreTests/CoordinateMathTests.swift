import Testing
@testable import SnowCore

/// Primary display 1512×982 pt. CoreGraphics: top-left origin, y down. AppKit: bottom-left, y up.
struct CoordinateMathTests {
    private let primaryHeight: Float = 982

    @Test func primaryDisplayWindow() {
        // A window 100 pt below the top of the primary display, 400 pt tall.
        let cg = Rect(x: 50, y: 100, width: 800, height: 400)
        let appKit = CoordinateMath.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(appKit == Rect(x: 50, y: 482, width: 800, height: 400))
        #expect(appKit.maxY == 882) // top edge 100 pt below the screen top
    }

    @Test func secondaryAbove() {
        // Secondary 2560×1440 above the primary: AppKit y 982…2422, CG y -1440…0.
        let cg = Rect(x: 200, y: -1300, width: 1000, height: 400)
        let appKit = CoordinateMath.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(appKit.minY == 1882)
        #expect(appKit.maxY == 2282)
        #expect(appKit.maxY < 982 + 1440)
    }

    @Test func secondaryLeft() {
        // Secondary 1920×1080 to the left, bottom-aligned: AppKit x -1920…0, y 0…1080;
        // CG y = 982 - 1080 = -98 at its top.
        let cg = Rect(x: -1800, y: -50, width: 600, height: 300)
        let appKit = CoordinateMath.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(appKit == Rect(x: -1800, y: 732, width: 600, height: 300))
    }

    @Test func secondaryRight() {
        // Secondary to the right, top-aligned: AppKit x 1512…3432, y -98…982.
        let cg = Rect(x: 2000, y: 900, width: 500, height: 150)
        let appKit = CoordinateMath.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(appKit == Rect(x: 2000, y: -68, width: 500, height: 150))
    }

    @Test func roundTrip() {
        let original = Rect(x: -321, y: -77, width: 640, height: 480)
        let there = CoordinateMath.appKitRect(fromCG: original, primaryHeight: primaryHeight)
        #expect(CoordinateMath.cgRect(fromAppKit: there, primaryHeight: primaryHeight) == original)
    }
}
