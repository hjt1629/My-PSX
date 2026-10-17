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
    @StateObject private var gptSettings = GPTSettings()

    var body: some Scene {
        WindowGroup("My PSX") {
            ContentView()
                .environmentObject(browser)
                .environmentObject(gptSettings)
                .frame(minWidth: 1000, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("폴더 열기…") { browser.chooseFolder() }
                    .keyboardShortcut("o")
            }
        }

        // 앱 메뉴 → 설정… (⌘,)
        Settings {
            SettingsView()
                .environmentObject(gptSettings)
                .preferredColorScheme(.dark)
        }
    }
}
