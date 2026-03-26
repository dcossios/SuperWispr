import SwiftUI

@main
struct SuperWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep a single running menu-bar instance to avoid backend port conflicts.
        if let bundleId = Bundle.main.bundleIdentifier {
            let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if instances.count > 1 {
                NSApp.terminate(nil)
                return
            }
        }

        menuBarController = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.shutdown()
    }
}
