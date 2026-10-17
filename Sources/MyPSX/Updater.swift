import AppKit
import Foundation

/// 앱 메뉴 → 업데이트…: 맥북에 받아 둔 코드(scripts/install.sh)로 최신 버전을 만들어 다시 설치합니다.
@MainActor
enum Updater {
    /// install.sh가 기록해 두는 코드 폴더
    static var sourcePath: String? {
        UserDefaults.standard.string(forKey: "sourcePath")
    }

    static let logPath = "~/Library/Logs/MyPSX-update.log"

    static func run() {
        guard let source = sourcePath,
              FileManager.default.isExecutableFile(atPath: source + "/scripts/install.sh") else {
            showSetupHelp()
            return
        }
        let alert = NSAlert()
        alert.messageText = "최신 버전으로 업데이트할까요?"
        alert.informativeText = """
            \(source) 에서 최신 코드를 받아 앱을 다시 만들고 설치합니다. 1분 정도 걸리고, 끝나면 앱이 다시 켜집니다.
            저장하지 않은 편집은 사라지니 먼저 저장해 주세요.
            """
        alert.addButton(withTitle: "업데이트")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 앱이 꺼져도 계속 돌도록 백그라운드로 실행하고, 진행 기록은 로그 파일에 남깁니다.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "nohup \"$0\" > \(logPath) 2>&1 &", source + "/scripts/install.sh"]
        do {
            try process.run()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let started = NSAlert()
        started.messageText = "업데이트를 시작했습니다"
        started.informativeText = "끝나면 앱이 자동으로 다시 켜집니다. 실패하면 알림이 뜨고, 자세한 내용은 \(logPath) 에 남습니다."
        started.runModal()
    }

    private static func showSetupHelp() {
        let alert = NSAlert()
        alert.messageText = "맥북에 코드를 먼저 받아 두세요"
        alert.informativeText = """
            터미널에서 한 번만 실행하면, 이후에는 이 메뉴로 업데이트할 수 있습니다.

            xcode-select --install   (처음 한 번, 이미 있으면 건너뜀)
            git clone -b claude/photo-viewer-editor https://github.com/hjt1629/My-PSX.git ~/My-PSX
            ~/My-PSX/scripts/install.sh
            """
        alert.addButton(withTitle: "명령어 복사")
        alert.addButton(withTitle: "닫기")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                "git clone -b claude/photo-viewer-editor https://github.com/hjt1629/My-PSX.git ~/My-PSX && ~/My-PSX/scripts/install.sh",
                forType: .string)
        }
    }
}
