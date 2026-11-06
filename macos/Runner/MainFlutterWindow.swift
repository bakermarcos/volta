import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.minX, y: windowFrame.minY, width: 1280, height: 820), display: true)
    self.minSize = NSSize(width: 800, height: 650)

    let windowChannel = FlutterMethodChannel(name: "volta/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "fullscreen", let enabled = call.arguments as? Bool, let window = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      if window.styleMask.contains(.fullScreen) != enabled { window.toggleFullScreen(nil) }
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
