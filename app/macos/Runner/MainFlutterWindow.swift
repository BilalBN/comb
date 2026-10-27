import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable size, centred; never smaller than the layout needs.
    let size = NSSize(width: 1280, height: 820)
    if let screen = NSScreen.main?.visibleFrame {
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      self.setFrame(NSRect(origin: origin, size: size), display: true)
    }
    self.minSize = NSSize(width: 980, height: 640)
    self.title = "Comb"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
