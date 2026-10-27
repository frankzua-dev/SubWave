import AppKit
import SwiftUI

@MainActor
let sharedState = AppState()

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching (_ notification: Notification) {
    MainActor.assumeIsolated { sharedState.start() }
  }

  func applicationWillTerminate (_ notification: Notification) {
    // Destroying the tap restores normal system audio
    MainActor.assumeIsolated { sharedState.stop() }
  }

  // Closing the window (the red button) quits SubWave, which also restores normal system audio
  func applicationShouldTerminateAfterLastWindowClosed (_ sender: NSApplication) -> Bool {
    true
  }
}

@main
struct SubWaveApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @ObservedObject private var app = sharedState

  var body: some Scene {
    Window("SubWave", id: "main") {
      ContentView()
        .environmentObject(app)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 500, height: 880)
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About SubWave") { AboutPanel.show() }
      }
    }

    MenuBarExtra {
      MenuBarContent().environmentObject(app)
    } label: {
      Image(nsImage: MenuBarIcon.image)
    }
  }
}

private struct MenuBarContent: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open SubWave") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Toggle("Process Audio", isOn: $app.settings.processingEnabled)
    if !app.favorites.isEmpty {
      Divider()
      ForEach(app.favorites) { favorite in
        Button(favorite.name) { app.select(favorite) }
      }
    }
    Divider()
    Button("Quit SubWave") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}

/// The standard About window, with a dedication above the copyright line.
enum AboutPanel {
  static let dedication = "This app is dedicated to my daughter Bebos who always tell me \u{201C}Dad all we do is work work work!\u{201D}\n\nLove you Bebos!"

  static func show () {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.paragraphSpacing = 2
    let credits = NSAttributedString(string: dedication, attributes: [
      .font: NSFont.systemFont(ofSize: 11),
      .foregroundColor: NSColor.secondaryLabelColor,
      .paragraphStyle: paragraph
    ])
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate(ignoringOtherApps: true)
  }
}
