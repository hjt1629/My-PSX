import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        Group {
            switch browser.tab {
            case .viewer:
                ViewerView()
            case .editor, .cutout:
                EditorWorkspace()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TabBar()
            }
        }
        .toolbarBackground(Theme.panel, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
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

/// 창 맨 위 가운데의 탭 (뷰어 / 사진 편집 / 누끼)
struct TabBar: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let selected = browser.tab == tab
                Button {
                    browser.switchTab(tab)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                        Text(tab.title)
                    }
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DarkButtonStyle(selected: selected))
                .keyboardShortcut(tab.key, modifiers: .command)
                .help("\(tab.title) (⌘\(String(tab.key.character)))")
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
    }
}
