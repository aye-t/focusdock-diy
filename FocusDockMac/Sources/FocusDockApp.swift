import AppKit
import SwiftUI

@main
struct FocusDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            Button(model.isRunning ? "暂停" : model.isPaused ? "继续" : "开始专注") {
                model.performPrimaryAction()
            }
            Button("显示主窗口") { WindowManager.shared.showMainWindow() }
            Button("提醒") { WindowManager.shared.showMainWindow(section: .reminders) }
            Button(model.settings.showPetPanel ? "隐藏桌宠" : "显示桌宠") {
                model.updateSettings { $0.showPetPanel.toggle() }
                WindowManager.shared.refreshPanelVisibility()
            }
            Divider()
            Button("退出 FocusDock") { NSApp.terminate(nil) }
        } label: {
            Label(model.phase == .idle ? "FocusDock" : model.timeText, systemImage: model.isRest ? "cup.and.saucer.fill" : "timer")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        WindowManager.shared.setup(model: AppModel.shared)
        // 菜单栏型 App 在 didFinishLaunching 回调内尚未完成激活；
        // 延到下一轮主线程再置前，避免窗口已创建却保持隐藏。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WindowManager.shared.showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showMainWindow()
        return true
    }
}
