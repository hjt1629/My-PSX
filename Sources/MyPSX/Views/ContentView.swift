import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let photo = browser.openedPhoto {
                EditorView(url: photo)
                    .id(photo)
            } else {
                BrowserView()
            }
        }
        .navigationTitle(browser.openedPhoto?.lastPathComponent
                         ?? browser.currentFolder?.lastPathComponent
                         ?? "My PSX")
        .confirmationDialog(
            "저장하지 않은 변경사항이 있습니다.",
            isPresented: Binding(
                get: { browser.pendingNavigation != nil },
                set: { if !$0 { browser.pendingNavigation = nil } }
            ),
            presenting: browser.pendingNavigation
        ) { pending in
            Button("저장하지 않고 이동", role: .destructive) {
                browser.hasUnsavedEdits = false
                browser.pendingNavigation = nil
                pending.action()
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("이동하면 편집한 내용이 사라집니다.")
        }
        .alert(
            "오류",
            isPresented: Binding(
                get: { browser.errorMessage != nil },
                set: { if !$0 { browser.errorMessage = nil } }
            )
        ) {
            Button("확인") {}
        } message: {
            Text(browser.errorMessage ?? "")
        }
    }
}
