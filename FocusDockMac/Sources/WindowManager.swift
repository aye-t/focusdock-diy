import AppKit
import Combine
import SwiftUI

enum FloatingPanelKind: Hashable {
    case timer
    case reminder
    case pet
}

enum FloatingTimerPanelMetrics {
    // Timer icons draw a 10-point shadow with a 4-point vertical offset.
    // Keep that effect inside the borderless panel instead of clipping it at
    // the native window boundary.
    static let independentContentInset: CGFloat = 14

    static func independentSize(for style: TimerIconStyle) -> NSSize {
        let iconSize: NSSize
        switch style {
        case .digital:
            iconSize = NSSize(width: 120, height: 84)
        case .progressRing, .tomato, .hourglass:
            iconSize = NSSize(width: 84, height: 84)
        }
        return NSSize(
            width: iconSize.width + independentContentInset * 2,
            height: iconSize.height + independentContentInset * 2
        )
    }
}

enum FloatingReminderPanelMetrics {
    // The independent reminder is a compact utility card, not the reminder
    // half of the combined control bar. Keep its native panel tightly fitted
    // around the card so a reminder-only setup does not leave a long backdrop.
    static let contentSize = NSSize(width: 208, height: 80)
    static let contentInset: CGFloat = 4
    static let panelSize = NSSize(
        width: contentSize.width + contentInset * 2,
        height: contentSize.height + contentInset * 2
    )
}

enum PetPanelMetrics {
    static func size(petSize rawPetSize: CGFloat, isExpanded: Bool, hasCompletion: Bool) -> NSSize {
        let petSize = PetVisualMetrics.clampedSettingSize(rawPetSize)
        let expanded = isExpanded || hasCompletion
        let bubbleHeight: CGFloat = hasCompletion
            ? 140
            : (expanded ? FloatingTodayPlanMetrics.height : 68)
        let avatarHeight = PetVisualMetrics.avatarCanvasHeight(for: petSize)
        return NSSize(
            width: max(expanded ? 288 : 248, petSize + 44),
            height: bubbleHeight + avatarHeight + PetVisualMetrics.petPanelVerticalSafetyArea()
        )
    }
}

enum MainWindowSectionPolicy {
    static func destination(for explicitSection: AppSection?) -> AppSection {
        explicitSection ?? .focus
    }
}

enum FloatingPanelPlacement {
    static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - result.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - result.height)
        result.origin.x = min(max(result.origin.x, visibleFrame.minX), maximumX)
        result.origin.y = min(max(result.origin.y, visibleFrame.minY), maximumY)
        return result
    }
}

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var timerPanel: FloatingPanel?
    private var reminderPanel: FloatingPanel?
    private var petPanel: FloatingPanel?
    private var focusPopover: NSPopover?
    private var observation: AnyCancellable?
    private weak var model: AppModel?
    private var mainWindow: NSWindow?
    private var previousFloatingLayout: FloatingLayoutStyle?
    private var suppressNextPetPanelClick = false

    func setup(model: AppModel) {
        if timerPanel == nil {
        self.model = model
        timerPanel = makePanel(
            size: timerPanelSize(for: model.settings),
            key: "FocusDock.TimerPanelFrame",
            defaultOffset: NSPoint(x: 32, y: 132),
            content: AnyView(FloatingTimerPanelView().environmentObject(model))
        )
        timerPanel?.onClick = { [weak self] location, clickCount in
            self?.handleTimerPanelClick(at: location, clickCount: clickCount)
        }
        timerPanel?.delaysSingleClickForDoubleClick = false
        reminderPanel = makePanel(
            size: FloatingReminderPanelMetrics.panelSize,
            key: "FocusDock.ReminderPanelFrame",
            defaultOffset: NSPoint(x: 38, y: 44),
            content: AnyView(FloatingReminderView().environmentObject(model))
        )
        // FloatingReminderView owns click routing. A second panel-wide callback
        // would run after every SwiftUI control and force the main window back
        // to Reminders, even when the control intended to show a popover.
        reminderPanel?.onClick = nil
        petPanel = makePanel(
            size: petPanelSize(for: model.settings),
            key: "FocusDock.PetPanelFrame",
            defaultOffset: NSPoint(x: 220, y: 44),
            content: AnyView(DesktopPetPanelView().environmentObject(model))
        )
        petPanel?.onClick = { [weak self, weak petPanel] location, clickCount in
            guard let self, let petPanel else { return }
            if self.suppressNextPetPanelClick {
                self.suppressNextPetPanelClick = false
                return
            }
            // 只有宠物本体区域触发展开。提醒卡片和计划按钮位于其上方，
            // 不能在处理完成后再被外层窗口误判成一次“点击宠物”。
            let petSize = PetVisualMetrics.clampedSettingSize(CGFloat(model.settings.petSize))
            let avatarHitHeight = PetVisualMetrics.panelBottomSafetyInset
                + PetVisualMetrics.avatarCanvasHeight(for: petSize)
            guard location.y <= min(petPanel.frame.height, avatarHitHeight) else { return }
            if clickCount >= 2 {
                self.showMainWindow(section: .focus)
            } else {
                model.petInteractionToken += 1
            }
        }
        petPanel?.onRightClick = { [weak self, weak petPanel] event in
            guard let self, let petPanel else { return }
            self.showPetContextMenu(event: event, panel: petPanel)
        }
        petPanel?.delaysSingleClickForDoubleClick = true
        let petState = Publishers.CombineLatest4(
            model.$activeReminderIDs.removeDuplicates(),
            model.$activePlanReminderID.removeDuplicates(),
            model.$petQuickControlsExpanded.removeDuplicates(),
            model.$petPlanListCollapsed.removeDuplicates()
        )
        let petPresentationState = Publishers.CombineLatest(
            petState,
            model.$completionFeedback.map(\.?.id).removeDuplicates()
        )
        observation = Publishers.CombineLatest3(
            model.$settings.removeDuplicates(),
            model.$reminders.removeDuplicates(),
            petPresentationState
        ).dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPanelVisibility() }
        }
        previousFloatingLayout = model.settings.floatingLayout
        refreshPanelVisibility()
        // 启动时统一贴右下角（清除任何残留的旧位置）
        layoutPanelsToBottomRight()
        applyAppearance(model.settings.appearance)
        }
        ensureMainWindow()
    }

    func suppressNextPetClick() {
        suppressNextPetPanelClick = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.suppressNextPetPanelClick = false
        }
    }

    func showMainWindow(section: AppSection? = nil) {
        // Generic "open FocusDock" actions always land on Focus. Reminders is
        // selected only by an explicit reminder entry point, so a previous
        // reminder click cannot hijack every later reopen.
        model?.selectedSection = MainWindowSectionPolicy.destination(for: section)
        guard let main = ensureMainWindow() else { return }
        presentMainWindow(main)
    }

    private func presentMainWindow(_ main: NSWindow) {
        mainWindow = main
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if main.isMiniaturized {
            main.deminiaturize(nil)
        }
        main.orderFrontRegardless()
        main.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleTimerPanelClick(at location: NSPoint, clickCount: Int) {
        guard let model, model.settings.showTimerPanel else { return }

        if !model.settings.usesStandaloneTimerSurface {
            // 单击由原生 SwiftUI Button 处理；双击额外打开任务与时间编辑页。
            if clickCount >= 2 {
                showMainWindow(section: .focus)
            }
            return
        }

        if clickCount >= 2 {
            showMainWindow(section: .dailyPlan)
        }
        // The SwiftUI button covers the complete independent timer (including
        // its effect inset) and owns the single-click toggle. Handling it again
        // here would close and immediately reopen an already visible popover.
    }

    func toggleFocusPopover() {
        if focusPopover?.isShown == true {
            closeFocusPopover()
        } else {
            showFocusPopover()
        }
    }

    func showFocusPopover() {
        guard let model,
              model.settings.showTimerPanel,
              let anchorView = timerPanel?.contentView else { return }

        let popover = ensureFocusPopover(model: model)
        if popover.isShown { return }
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minX)
    }

    func closeFocusPopover() {
        focusPopover?.performClose(nil)
    }

    private func ensureFocusPopover(model: AppModel) -> NSPopover {
        if let focusPopover { return focusPopover }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(
            width: FloatingFocusPanelMetrics.width,
            height: FloatingFocusPanelMetrics.compactHeight
        )

        let content = MinimalFloatingFocusPanelView(
            onClose: { [weak self] in self?.closeFocusPopover() },
            onPreferredSizeChange: { [weak self] size in
                self?.updateFocusPopoverSize(size)
            }
        )
        .environmentObject(model)
        let controller = NSHostingController(rootView: AnyView(content))
        // The popover's three pages have explicit sizes. Prevent SwiftUI from
        // racing AppKit with a stale fitting size while a page is changing.
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: popover.contentSize)
        controller.view.autoresizingMask = [.width, .height]
        popover.contentViewController = controller
        focusPopover = popover
        return popover
    }

    private func updateFocusPopoverSize(_ size: CGSize) {
        guard let popover = focusPopover else { return }
        let resolved = NSSize(width: size.width, height: size.height)
        guard popover.contentSize != resolved else { return }
        popover.contentSize = resolved
        popover.contentViewController?.view.frame = NSRect(origin: .zero, size: resolved)
    }

    private func showPetContextMenu(event: NSEvent, panel: FloatingPanel) {
        guard let model, let view = panel.contentView else { return }
        let menu = NSMenu(title: "桌面宠物")
        menu.autoenablesItems = false

        menu.addItem(menuItem(model.primaryActionTitle, action: #selector(petPrimaryAction)))
        menu.addItem(menuItem("填写任务与时间…", action: #selector(petOpenFocus)))
        menu.addItem(.separator())

        let speciesItem = NSMenuItem(title: "换个形象", action: nil, keyEquivalent: "")
        let speciesMenu = NSMenu(title: "换个形象")
        for species in PetSpecies.allCases {
            let item = menuItem(species.title, action: #selector(petChooseSpecies))
            item.representedObject = species.rawValue
            item.state = model.settings.petSpecies == species ? .on : .off
            speciesMenu.addItem(item)
        }
        speciesItem.submenu = speciesMenu
        menu.addItem(speciesItem)

        let sceneItem = NSMenuItem(title: "场景演示", action: nil, keyEquivalent: "")
        let sceneMenu = NSMenu(title: "场景演示")
        [("💧 喝水", 1), ("👀 护眼", 2), ("🚶 活动", 3), ("🎉 庆祝", 4), ("👋 挥手", 5)]
            .forEach { title, tag in
                let item = menuItem(title, action: #selector(petPreviewScene))
                item.tag = tag
                sceneMenu.addItem(item)
            }
        sceneItem.submenu = sceneMenu
        menu.addItem(sceneItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("桌宠设置…", action: #selector(petOpenSettings)))
        menu.addItem(menuItem("隐藏桌宠", action: #selector(petHide)))

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func petPrimaryAction() {
        model?.performPrimaryAction()
    }

    @objc private func petOpenFocus() {
        showMainWindow(section: .focus)
    }

    @objc private func petChooseSpecies(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let species = PetSpecies(rawValue: raw) else { return }
        model?.updateSettings { $0.petSpecies = species }
    }

    @objc private func petPreviewScene(_ sender: NSMenuItem) {
        let mood: PetMood
        switch sender.tag {
        case 1: mood = .drink
        case 2: mood = .eye
        case 3: mood = .stretch
        case 4: mood = .celebrate
        default: mood = .wave
        }
        model?.previewPetScene(mood)
    }

    @objc private func petOpenSettings() {
        showMainWindow(section: .settings)
    }

    @objc private func petHide() {
        model?.updateSettings { $0.showPetPanel = false }
        refreshPanelVisibility()
    }

    @discardableResult
    private func ensureMainWindow() -> NSWindow? {
        if let mainWindow { return mainWindow }
        guard let model else { return nil }

        let controller = NSHostingController(
            rootView: MainView()
                .environmentObject(model)
        )
        // NSWindow owns the main window's size. If NSHostingController also
        // derives min/ideal/max sizes from SwiftUI, title-bar zoom can start a
        // resize → layout → resize feedback loop and AppKit aborts the app.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "FocusDock"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 740))
        window.minSize = NSSize(width: 960, height: 640)
        window.contentMinSize = NSSize(width: 960, height: 640)
        controller.view.frame = NSRect(origin: .zero, size: NSSize(width: 1120, height: 740))
        controller.view.autoresizingMask = [.width, .height]
        window.isReleasedWhenClosed = false
        // This window is created explicitly on every launch; do not let AppKit
        // restore a second stale instance with old size constraints.
        window.isRestorable = false
        window.center()
        mainWindow = window
        applyAppearance(model.settings.appearance)
        return window
    }

    func applyAppearance(_ appearance: AppAppearance) {
        let nsAppearance = appearance.appearance
        timerPanel?.appearance = nsAppearance
        reminderPanel?.appearance = nsAppearance
        petPanel?.appearance = nsAppearance
        for window in NSApp.windows where !(window is FloatingPanel) {
            window.appearance = nsAppearance
        }
    }

    func refreshPanelVisibility() {
        guard let model else { return }
        if !model.settings.showTimerPanel {
            closeFocusPopover()
        }
        // 悬浮控件始终交给 WindowServer 原生拖动。
        timerPanel?.isMovable = true
        timerPanel?.isMovableByWindowBackground = false
        reminderPanel?.isMovable = true
        reminderPanel?.isMovableByWindowBackground = false
        petPanel?.isMovable = true
        petPanel?.isMovableByWindowBackground = false
        updatePanelSizes(for: model.settings)
        // Saved coordinates can become invalid after a display is disconnected,
        // its scale changes, or a drag is interrupted. Recover before ordering
        // the panels front so an enabled companion can never remain off-screen.
        recoverPanelIfNeeded(timerPanel)
        recoverPanelIfNeeded(reminderPanel)
        recoverPanelIfNeeded(petPanel)
        // 切换布局时，统一把所有面板定位到屏幕右下方（保证一致且都在右下角）
        let layoutChanged = previousFloatingLayout != nil && previousFloatingLayout != model.settings.floatingLayout
        if layoutChanged,
           (model.settings.floatingLayout == .independent
            ? (model.settings.showTimerPanel && model.settings.showReminderPanel)
            : (model.settings.showTimerPanel || model.settings.showReminderPanel)) {
            layoutPanelsToBottomRight()
        } else if model.settings.floatingLayout == .independent,
                  model.settings.showTimerPanel,
                  model.settings.showReminderPanel,
                  independentPanelsNeedAlignment() {
            layoutPanelsToBottomRight()
        }
        model.settings.showTimerPanel ? timerPanel?.orderFrontRegardless() : timerPanel?.orderOut(nil)
        if model.settings.floatingLayout == .independent {
            model.settings.showReminderPanel
                ? reminderPanel?.orderFrontRegardless()
                : reminderPanel?.orderOut(nil)
        } else {
            // 合并控制条已经内置提醒入口；仅在隐藏番茄钟时保留独立提醒窗。
            (!model.settings.showTimerPanel && model.settings.showReminderPanel)
                ? reminderPanel?.orderFrontRegardless()
                : reminderPanel?.orderOut(nil)
        }
        model.settings.showPetPanel ? petPanel?.orderFrontRegardless() : petPanel?.orderOut(nil)
        previousFloatingLayout = model.settings.floatingLayout
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? FloatingPanel,
              !panel.isProgrammaticMove,
              !panel.isDraggingWindow else { return }
        recoverPanelIfNeeded(panel)
        saveFrame(panel)
    }

    func resetPanelPositions() {
        layoutPanelsToBottomRight()
        layoutPetToBottomLeft()
    }

    /// 桌宠默认落在屏幕左下角，与右下角的计时/提醒控件错开
    private func layoutPetToBottomLeft() {
        guard let petPanel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        move(petPanel, to: NSRect(
            x: visible.minX + 32,
            y: visible.minY + 24,
            width: petPanel.frame.width,
            height: petPanel.frame.height
        ))
        saveFrame(petPanel)
    }

    private func panel(for kind: FloatingPanelKind) -> FloatingPanel? {
        switch kind {
        case .timer: timerPanel
        case .reminder: reminderPanel
        case .pet: petPanel
        }
    }

    private func petPanelSize(for settings: AppSettings) -> NSSize {
        PetPanelMetrics.size(
            petSize: CGFloat(settings.petSize),
            isExpanded: model?.petQuickControlsExpanded == true,
            hasCompletion: model?.completionFeedback != nil
        )
    }

    private func move(_ panel: FloatingPanel, to frame: NSRect) {
        panel.isProgrammaticMove = true
        panel.setFrame(clamped(frame), display: true)
        panel.isProgrammaticMove = false
    }

    /// 统一把所有面板定位到屏幕右下方，并保存位置（保证三种布局一致）
    private func layoutPanelsToBottomRight() {
        guard let model, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let gap: CGFloat = 10
        let baseY: CGFloat = 132

        if model.settings.floatingLayout == .independent,
           let timerPanel, let reminderPanel,
           model.settings.showTimerPanel, model.settings.showReminderPanel {
            // 独立双组件：番茄钟在左、提醒在右，整体贴右边缘
            let timerW = timerPanel.frame.width
            let timerH = timerPanel.frame.height
            let remW = reminderPanel.frame.width
            let remH = reminderPanel.frame.height
            let totalW = timerW + gap + remW
            let timerX = visible.maxX - totalW
            move(timerPanel, to: NSRect(x: timerX, y: visible.minY + baseY, width: timerW, height: timerH))
            let remY = visible.minY + baseY + timerH / 2 - remH / 2
            move(reminderPanel, to: NSRect(x: timerX + timerW + gap, y: remY, width: remW, height: remH))
            saveFrame(timerPanel)
            saveFrame(reminderPanel)
        } else if let timerPanel, model.settings.showTimerPanel || model.settings.showReminderPanel {
            // 合并：单个面板贴右边缘
            let w = timerPanel.frame.width
            let h = timerPanel.frame.height
            move(timerPanel, to: NSRect(x: visible.maxX - w - 32, y: visible.minY + baseY, width: w, height: h))
            saveFrame(timerPanel)
        }
    }

    private func saveFrame(_ panel: FloatingPanel?) {
        guard let panel, let key = panel.storageKey else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: key)
    }

    private func independentPanelsNeedAlignment() -> Bool {
        guard let timerPanel, let reminderPanel else { return false }
        let timerFrame = timerPanel.frame
        let reminderFrame = reminderPanel.frame
        let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(timerFrame) } ?? NSScreen.main)?.visibleFrame

        if let visible, !visible.contains(reminderFrame) {
            return true
        }

        let horizontalGap: CGFloat
        if reminderFrame.maxX < timerFrame.minX {
            horizontalGap = timerFrame.minX - reminderFrame.maxX
        } else if timerFrame.maxX < reminderFrame.minX {
            horizontalGap = reminderFrame.minX - timerFrame.maxX
        } else {
            horizontalGap = 0
        }
        let verticalOffset = abs(reminderFrame.midY - timerFrame.midY)
        return horizontalGap > 24 || verticalOffset > 24
    }

    private func makePanel(size: NSSize, key: String, defaultOffset: NSPoint, content: AnyView) -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.storageKey = key
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // SwiftUI 的 TapGesture 需要面板先成为 key window 才能稳定收到首次点击。
        // nonactivatingPanel 仍会保证点击悬浮窗时不抢占其他 App 的激活状态。
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = true
        // 禁用 NSWindow 的背景拖动，统一由 FloatingPanel.sendEvent 启动一次原生拖动。
        panel.isMovableByWindowBackground = false
        panel.onDragEnded = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.move(panel, to: self.clamped(panel.frame))
            self.saveFrame(panel)
        }
        // Floating panels own their size. Disable every NSHostingView sizing
        // contribution so frequent pet/timer updates cannot invalidate the
        // window's constraints while AppKit is already laying it out.
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        if let saved = UserDefaults.standard.string(forKey: key) {
            var savedFrame = NSRectFromString(saved)
            savedFrame.size = size
            let recoveredFrame = clamped(savedFrame)
            panel.isProgrammaticMove = true
            panel.setFrame(recoveredFrame, display: false)
            panel.isProgrammaticMove = false
            if recoveredFrame.origin != savedFrame.origin {
                UserDefaults.standard.set(NSStringFromRect(recoveredFrame), forKey: key)
            }
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.isProgrammaticMove = true
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - defaultOffset.x,
                y: visible.minY + defaultOffset.y
            ))
            panel.isProgrammaticMove = false
        }
        return panel
    }

    private func updatePanelSizes(for settings: AppSettings) {
        resize(timerPanel, to: timerPanelSize(for: settings))
        resize(reminderPanel, to: FloatingReminderPanelMetrics.panelSize)
        resizePetPanel(to: petPanelSize(for: settings))
    }

    private func timerPanelSize(for settings: AppSettings) -> NSSize {
        if settings.usesStandaloneTimerSurface {
            return Self.combinedTimerOnlyPanelSize(for: settings.timerIconStyle)
        }
        return NSSize(width: combinedPanelWidth(for: settings), height: 88)
    }

    private static func combinedTimerOnlyPanelSize(for style: TimerIconStyle) -> NSSize {
        FloatingTimerPanelMetrics.independentSize(for: style)
    }

    private static func combinedTimerWidth(for style: TimerIconStyle) -> CGFloat {
        switch style {
        case .digital: 108
        case .progressRing, .tomato, .hourglass: 72
        }
    }

    private func combinedPanelWidth(for settings: AppSettings) -> CGFloat {
        let visibleRules: [ReminderRule]
        if model?.activeReminderIDs.isEmpty == false {
            visibleRules = model?.activeReminderIDs.compactMap { id in model?.reminders.first(where: { $0.id == id }) } ?? []
        } else {
            visibleRules = Array(model?.reminders.filter(\.isEnabled).sorted { $0.nextFireAt < $1.nextFireAt }.prefix(3) ?? [])
        }
        let title = visibleRules.map(\.name).max(by: { $0.count < $1.count }) ?? "提醒"
        let referenceDate = model?.now ?? Date()
        let maxMinutes = visibleRules.map { max(1, Int(ceil($0.nextFireAt.timeIntervalSince(referenceDate) / 60))) }.max() ?? 99
        let timeSample = "\(min(999, maxMinutes)) 分后"
        let titleWidth = ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
        ]).width)
        let timeWidth = ceil((timeSample as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold)
        ]).width)
        let timerWidth = Self.combinedTimerWidth(for: settings.timerIconStyle)
        let fixedContentWidth: CGFloat = 10 + timerWidth + 10 + 1 + 10 + 38 + 9 + 12 + 6
        return min(380, max(300, fixedContentWidth + titleWidth + timeWidth))
    }

    private func resize(_ panel: FloatingPanel?, to size: NSSize) {
        guard let panel, panel.frame.size != size else { return }
        var frame = panel.frame
        let topRight = NSPoint(x: frame.maxX, y: frame.maxY)
        frame.size = size
        frame.origin = NSPoint(x: topRight.x - size.width, y: topRight.y - size.height)
        panel.isProgrammaticMove = true
        panel.setFrame(clamped(frame), display: true, animate: false)
        panel.isProgrammaticMove = false
    }

    private func resizePetPanel(to size: NSSize) {
        guard let petPanel, petPanel.frame.size != size else { return }
        var frame = petPanel.frame
        let bottomRight = NSPoint(x: frame.maxX, y: frame.minY)
        frame.size = size
        frame.origin = NSPoint(x: bottomRight.x - size.width, y: bottomRight.y)
        petPanel.isProgrammaticMove = true
        petPanel.setFrame(clamped(frame), display: true, animate: false)
        petPanel.isProgrammaticMove = false
    }

    private func position(_ panel: FloatingPanel?, offset: NSPoint) {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - panel.frame.width - offset.x,
            y: visible.minY + offset.y
        )
        panel.isProgrammaticMove = true
        panel.setFrameOrigin(origin)
        panel.isProgrammaticMove = false
        if let key = panel.storageKey {
            UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: key)
        }
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main else { return frame }
        return FloatingPanelPlacement.clamped(frame, to: screen.visibleFrame)
    }

    private func recoverPanelIfNeeded(_ panel: FloatingPanel?) {
        guard let panel else { return }
        let safeFrame = clamped(panel.frame)
        guard safeFrame.origin != panel.frame.origin else { return }
        move(panel, to: safeFrame)
        saveFrame(panel)
    }
}

final class FloatingPanel: NSPanel {
    var storageKey: String?
    var isProgrammaticMove = false
    var isDraggingWindow = false
    var onDragEnded: (() -> Void)?
    var onClick: ((NSPoint, Int) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var delaysSingleClickForDoubleClick = false
    private var dragMouseDownEvent: NSEvent?
    private var dragMouseDownLocation: NSPoint?
    private var didDragSinceMouseDown = false
    private var pendingSingleClick: DispatchWorkItem?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 悬浮窗的尺寸只由 WindowManager 管理。SwiftUI/AppKit 在弹窗切页时偶尔会
    /// 尝试根据 fittingSize 重设 NSPanel，这会引发「布局 → 缩放窗口 → 再布局」循环。
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(resolvedManagedFrame(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(resolvedManagedFrame(frameRect), display: flag, animate: animateFlag)
    }

    private func resolvedManagedFrame(_ proposedFrame: NSRect) -> NSRect {
        var resolvedFrame = proposedFrame
        if !isProgrammaticMove,
           frame.width > 0,
           frame.height > 0,
           resolvedFrame.size != frame.size {
            resolvedFrame.size = frame.size
        }
        return resolvedFrame
    }

    static func resolvedClickLocation(mouseDown: NSPoint?, mouseUp: NSPoint) -> NSPoint {
        mouseDown ?? mouseUp
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragMouseDownEvent = event
            dragMouseDownLocation = event.locationInWindow
            didDragSinceMouseDown = false
            if event.clickCount >= 2 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
            }
            super.sendEvent(event)

        case .leftMouseDragged where isMovable:
            if let start = dragMouseDownLocation {
                let dx = event.locationInWindow.x - start.x
                let dy = event.locationInWindow.y - start.y
                // 允许点击时的细微手抖，超过阈值才进入窗口拖动。
                guard hypot(dx, dy) >= 4 else {
                    super.sendEvent(event)
                    return
                }
            }
            // 必须把最初的 mouseDown 交给 WindowServer。只保留这一条拖动路径，
            // 避免背景拖动与手动 performDrag 同时运行而留下原位置副本。
            let initialEvent = dragMouseDownEvent ?? event
            dragMouseDownEvent = nil
            dragMouseDownLocation = nil
            didDragSinceMouseDown = true
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            isDraggingWindow = true
            performDrag(with: initialEvent)
            isDraggingWindow = false
            onDragEnded?()

        case .leftMouseUp:
            // 面板内容可能在按钮动作中即时收缩。必须沿用 mouseDown 时的坐标，
            // 否则提醒按钮原本位于卡片区域，收缩后会被误判成点击了宠物本体。
            let clickLocation = Self.resolvedClickLocation(
                mouseDown: dragMouseDownLocation,
                mouseUp: event.locationInWindow
            )
            dragMouseDownEvent = nil
            dragMouseDownLocation = nil
            super.sendEvent(event)
            guard !didDragSinceMouseDown, let onClick else { return }
            // 单击即时触发（暂停/继续）；双击打开应用（抵消逻辑在 handleTimerPanelClick 内）。
            onClick(clickLocation, event.clickCount)

        case .rightMouseDown:
            if let onRightClick {
                onRightClick(event)
            } else {
                super.sendEvent(event)
            }

        default:
            super.sendEvent(event)
        }
    }
}
