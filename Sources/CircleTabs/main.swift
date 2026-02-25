import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Strong reference — app.delegate is weak, so we must retain it ourselves
let appDelegate = AppDelegate()
app.delegate = appDelegate

withExtendedLifetime(appDelegate) {
    app.run()
}
