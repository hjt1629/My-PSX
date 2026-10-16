import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run`으로 실행해도 Dock에 나타나고 창이 앞으로 오도록 합니다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MyPSXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var browser = FolderBrowser(launchArguments: CommandLine.arguments)

    var body: some Scene {
        WindowGroup("My PSX") {
            ContentView()
                .environmentObject(browser)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("폴더 열기…") { browser.chooseFolder() }
                    .keyboardShortcut("o")
            }
        }
    }
}
