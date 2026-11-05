import AppKit

let app = NSApplication.shared
// `NSApplication.delegate` is weak; this global keeps the delegate alive for the process lifetime.
let appDelegate = AppDelegate()
app.delegate = appDelegate
// Belt and braces with `LSUIElement`: no Dock icon, no Cmd-Tab entry, even when run unbundled.
app.setActivationPolicy(.accessory)
app.run()
