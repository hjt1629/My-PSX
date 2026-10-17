import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: FolderBrowser
    @EnvironmentObject private var jobs: BackgroundJobs

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            PanelDivider(vertical: false)
            Group {
                switch browser.tab {
                case .viewer:
                    ViewerView()
                case .editor, .cutout:
                    EditorWorkspace()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.window)
        .navigationTitle("My PSX")
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
        .alert(
            "배경 제거 실패",
            isPresented: Binding(
                get: { jobs.errorMessage != nil },
                set: { if !$0 { jobs.errorMessage = nil } }
            )
        ) {
            Button("확인") {}
        } message: {
            Text(jobs.errorMessage ?? "")
        }
        .onAppear {
            // 뒤에서 끝난 배경 제거 결과가 바로 썸네일 목록에 나타나도록
            jobs.onSaved = { [weak browser] url in
                ThumbnailLoader.shared.invalidate(url)
                browser?.reload()
            }
        }
    }
}

/// 창 위쪽의 글자 탭 줄 (사진 뷰어 | 사진 편집 | 오려내기)
struct TabBar: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.trailing, 10)
            ForEach(AppTab.allCases) { tab in
                if tab != AppTab.allCases.first {
                    Color.white.opacity(0.15).frame(width: 1, height: 14)
                }
                TabItem(tab: tab, selected: browser.tab == tab) {
                    browser.switchTab(tab)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.panel)
    }
}

private struct TabItem: View {
    let tab: AppTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.system(size: 14, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color.white : (hovering ? Theme.text : Theme.secondaryText))
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(tab.key, modifiers: .command)
        .help("\(tab.title) (⌘\(String(tab.key.character)))")
    }
}
