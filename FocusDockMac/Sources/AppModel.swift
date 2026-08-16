import AppKit
import AVFoundation
import Combine
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var selectedSection: AppSection = .focus
    @Published var settings = AppSettings()
    @Published var reminders: [ReminderRule] = []
    @Published var todos: [TodoItem] = []
    @Published var taskSets: [TaskSet] = []
    @Published var dailyPlanItems: [DailyPlanItem] = []
    @Published var sessions: [FocusSession] = []
    @Published var reminderEvents: [ReminderEvent] = []

    @Published var phase: TimerPhase = .idle
    @Published var mode: TimerMode = .countdown
    @Published var timerTitle = ""
    @Published var task = ""
    @Published var durationSeconds: TimeInterval = 45 * 60
    @Published var displayedSeconds: TimeInterval = 45 * 60
    @Published var targetDate: Date?
    @Published var countupReferenceDate: Date?
    @Published var sessionStartedAt: Date?
    @Published var activeTodoID: UUID?
    @Published var activePlanItemID: UUID?
    @Published var activePlanReminderID: UUID?

    @Published var activeReminderIDs: [UUID] = []
    @Published var queuedReminderIDs: [UUID] = []
    @Published var isCompletionPresented = false
    /// 最近完成的一轮专注，仅用于短暂的悬浮成功反馈，不参与计时状态。
    @Published var completionFeedback: FocusSession?
    /// 外部（如悬浮窗完成气泡「查看记录」）请求计划页切换到指定 Tab
    @Published var requestedPlanTab: PlanTab? = nil
    @Published var requestedPlanDate: Date? = nil
    @Published var reminderPulse = false
    /// 提醒触发时由宠物演示的场景情态（drink/eye/stretch/wave），配合 petReminderToken 触发一次性动画
    @Published var petReminderScene: PetMood? = nil
    @Published var petReminderToken = 0
    /// 由原生计时悬浮窗转发的点击，用于打开今日任务顺序弹层。
    @Published var floatingPlanPopoverToken = 0
    /// 由原生悬浮窗转发的桌宠点击，避免轻微拖动或非激活面板吞掉 SwiftUI TapGesture。
    @Published var petInteractionToken = 0
    @Published var petQuickControlsExpanded = false
    @Published var petPlanListCollapsed = true
    @Published var obsidianSyncStatus = "尚未连接"
    @Published var notificationHint: String?
    @Published var notificationBlocked = false
    @Published var now = Date()

    private var clock: AnyCancellable?
    /// 提醒播放期间强持有播放器，避免后台悬浮窗触发时音频被提前释放。
    private var activeAudioPlayer: AVAudioPlayer?
    private let storageKey = "FocusDock.AppState.v2"
    private let v1StorageKey = "FocusDock.AppState.v1"
    private let v1SuiteName = "com.focusdock.mac"
    private let standaloneV2SuiteName = "com.focusdock.mac.v2"
    private let v1MigrationMarker = "FocusDock.V2.DidCopyV1"
    private let promotionMarker = "FocusDock.V2.DidPromoteToMainApp"
    private let independentFloatingMigrationMarker = "FocusDock.FloatingLayout.DidRestoreIndependent"
    private var isLoading = true
    private var lastPublishedSecond = 0

    private init() {
        let promotedFromStandaloneV2 = copyStandaloneV2StateIfNeeded()
        let migratedFromV1 = promotedFromStandaloneV2 ? false : copyV1StateIfNeeded()
        loadState()
        var restoredIndependentFloatingLayout = false
        if !UserDefaults.standard.bool(forKey: independentFloatingMigrationMarker) {
            if settings.floatingLayout == .combinedBar {
                settings.floatingLayout = .independent
                restoredIndependentFloatingLayout = true
            }
            UserDefaults.standard.set(true, forKey: independentFloatingMigrationMarker)
        }
        if promotedFromStandaloneV2 {
            obsidianSyncStatus = "已将 FocusDock V2 数据合并到 FocusDock"
        } else if migratedFromV1 {
            obsidianSyncStatus = "已复制旧版数据 · Obsidian 自动同步默认关闭"
        }
        let restoredStateChanged = normalizeRestoredTimer()
        isLoading = false
        if restoredStateChanged || restoredIndependentFloatingLayout { persist() }
        // 不在 AppModel 初始化期间读写 Obsidian：仓库位于 iCloud /
        // File Provider 时，打开占位文件可能长时间阻塞主线程，导致任何窗口都无法创建。
        // 自动同步仍在数据变更后触发，启动本身不再被外部文件系统卡住。
        if settings.obsidianAutoSync {
            obsidianSyncStatus = "已开启自动同步 · 数据更新时同步"
        }
        refreshNotificationAuthorization()
        startClock()
    }

    var isRest: Bool { phase.isRest }
    var isRunning: Bool { phase.isRunning }
    var isPaused: Bool { phase.isPaused }
    var timerColor: NSColor { isRest ? .systemGreen : .systemRed }

    var progress: Double {
        let total = isRest ? TimeInterval(settings.restMinutes * 60) : max(durationSeconds, 1)
        if mode == .countup && !isRest {
            return min(1, displayedSeconds / total)
        }
        return min(1, max(0, (total - displayedSeconds) / total))
    }

    var timeText: String {
        let value = max(0, Int(displayedSeconds.rounded(.down)))
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let seconds = value % 60
        if hours > 0 { return String(format: "%02d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 所有悬浮组件共享的唯一实时计时展示。
    /// `activePlanItemID` 只标记入口来源，不创建第二套计时器。
    var activeTimerPresentation: ActiveTimerPresentation? {
        ActiveTimerPresentationPolicy.resolve(
            phase: phase,
            timeText: timeText,
            taskTitle: floatingFocusTaskLabel,
            activePlanItemID: activePlanItemID
        )
    }

    var phaseText: String {
        switch phase {
        case .idle: "尚未开始"
        case .focusRunning: mode == .countup ? "自由计时" : "专注中"
        case .focusPaused: "已暂停"
        case .focusFinished: "专注完成"
        case .restRunning: "休息中"
        case .restPaused: "休息已暂停"
        case .restFinished: "休息完成"
        }
    }

    var primaryActionTitle: String {
        switch phase {
        case .idle: "开始专注"
        case .focusRunning, .restRunning: "暂停"
        case .focusPaused, .restPaused: "继续"
        case .focusFinished: "开始休息"
        case .restFinished: "开始下一轮"
        }
    }

    var floatingTimerTitle: String {
        let title = timerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if mode == .countup && phase != .idle { return "自由计时" }
        return "专注"
    }

    /// 浮窗任务名标签：暂停态显示「已暂停 · 任务名」，空闲显示时长，其余显示任务名
    var floatingTaskLabel: String {
        let name = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty ? "未命名专注" : name
        let planPrefix: String
        if let activePlanItemID,
           let index = todayPlanItems.firstIndex(where: { $0.id == activePlanItemID }) {
            planPrefix = "\(index + 1)/\(todayPlanItems.count) · "
        } else {
            planPrefix = ""
        }
        if phase == .focusPaused || phase == .restPaused {
            return "已暂停 · \(planPrefix)\(base)"
        }
        if phase == .idle {
            return settings.focusMinutes > 0 ? "\(settings.focusMinutes) 分钟专注" : "未开始"
        }
        return planPrefix + base
    }

    /// 计时图形内部使用的简短任务名；状态由图形中的独立一行表达。
    var floatingFocusTaskLabel: String {
        if let active = activePlanItem {
            return planDisplayTitle(active)
        }
        let name = task.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名专注" : name
    }

    var todaySessions: [FocusSession] {
        sessions.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    var todayFocusMinutes: Int { todaySessions.reduce(0) { $0 + $1.minutes } }

    var todayCompletedTodos: Int {
        Set(todaySessions.filter { $0.result == .done }.compactMap(\.todoID)).count
    }

    // MARK: 已完成专注记录（今日完成视图）
    func completedSessions(on date: Date) -> [FocusSession] {
        sessions.filter {
            Calendar.current.isDate($0.endedAt, inSameDayAs: date) && $0.result == .done
        }
        .sorted { $0.endedAt > $1.endedAt }
    }

    func completionRecords(on date: Date) -> [CompletionRecord] {
        CompletionRecordPolicy.records(
            sessions: sessions,
            planItems: dailyPlanItems,
            on: date
        )
    }

    var todayCompletedSessionCount: Int { completedSessions(on: Date()).count }
    var todayCompletedSessionMinutes: Int { completedSessions(on: Date()).reduce(0) { $0 + $1.minutes } }
    var todayCompletionRecordCount: Int { completionRecords(on: Date()).count }

    /// 本轮专注实际时长使用完成记录快照，避免庆祝气泡停留时数字继续增长。
    var finishedMinutes: Int {
        completionFeedback?.minutes ?? settings.focusMinutes
    }

    func renameSession(_ id: UUID, to name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[index].task = trimmed.isEmpty ? "未命名专注" : trimmed
        persist()
    }

    func updateSessionNote(_ id: UUID, note: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if completionFeedback?.id == id { completionFeedback = nil }
        persist()
    }

    func requestPlanDestination(_ tab: PlanTab, date: Date = Date()) {
        requestedPlanDate = date
        requestedPlanTab = tab
        selectedSection = .dailyPlan
    }

    var todayPlanItems: [DailyPlanItem] {
        dailyPlanItems
            .filter { Calendar.current.isDateInToday($0.date) }
            .sorted { $0.order < $1.order }
    }

    var todayCompletedPlanItems: Int {
        todayPlanItems.filter { $0.status == .completed }.count
    }

    var todayPlanCompletionRate: Int {
        guard !todayPlanItems.isEmpty else { return 0 }
        return Int((Double(todayCompletedPlanItems) / Double(todayPlanItems.count) * 100).rounded())
    }

    var activePlanItem: DailyPlanItem? {
        guard let activePlanItemID else { return nil }
        return dailyPlanItems.first { $0.id == activePlanItemID }
    }

    var nextPlanItem: DailyPlanItem? {
        todayPlanItems.first { $0.status == .pending || $0.status == .skipped || $0.status == .overdue }
    }

    func effectivePlanStatus(_ item: DailyPlanItem, at date: Date = Date()) -> DailyPlanStatus {
        if activePlanItemID == item.id,
           item.status != .completed,
           phase == .focusRunning || phase == .focusPaused {
            return .running
        }
        return item.status == .overdue ? .pending : item.status
    }

    var activePlanReminderItem: DailyPlanItem? {
        guard let activePlanReminderID else { return nil }
        return dailyPlanItems.first { $0.id == activePlanReminderID }
    }

    func planDisplayTitle(_ item: DailyPlanItem) -> String {
        let sameDay = dailyPlanItems
            .filter {
                Calendar.current.isDate($0.date, inSameDayAs: item.date)
                    && (($0.templateID != nil && $0.templateID == item.templateID) || ($0.templateID == nil && $0.title == item.title))
            }
            .sorted { $0.order < $1.order }
        guard sameDay.count > 1,
              let index = sameDay.firstIndex(where: { $0.id == item.id }) else { return item.title }
        return "\(item.title) · 第 \(index + 1) 轮"
    }

    var todayReminderEvents: [ReminderEvent] {
        reminderEvents.filter { Calendar.current.isDateInToday($0.date) }
    }

    var reminderCompletionRate: Int {
        guard !todayReminderEvents.isEmpty else { return 0 }
        let completed = todayReminderEvents.filter(\.completed).count
        return Int((Double(completed) / Double(todayReminderEvents.count) * 100).rounded())
    }

    var activeReminderNames: [String] {
        activeReminderIDs.compactMap { id in reminders.first(where: { $0.id == id })?.name }
    }

    var nextReminder: ReminderRule? {
        reminders.filter(\.isEnabled).min(by: { $0.nextFireAt < $1.nextFireAt })
    }

    func selectDuration(_ minutes: Int) {
        guard phase == .idle else { return }
        settings.focusMinutes = minutes
        durationSeconds = TimeInterval(minutes * 60)
        displayedSeconds = mode == .countdown ? durationSeconds : 0
        persist()
    }

    /// 暂停专注后允许直接重设剩余倒计时时长，再由用户手动继续。
    func replacePausedCountdownDuration(_ minutes: Int) {
        guard phase == .focusPaused, mode == .countdown else { return }
        let safeMinutes = max(1, min(180, minutes))
        durationSeconds = TimeInterval(safeMinutes * 60)
        displayedSeconds = durationSeconds
        targetDate = nil
        persist()
    }

    func configureFloatingTimer(title: String, task taskTitle: String, minutes: Int) {
        guard phase == .idle || (phase == .focusPaused && mode == .countdown) else { return }
        let safeMinutes = max(1, min(180, minutes))
        timerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTask = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        task = normalizedTask
        activeTodoID = nil
        let matchedPlanItem = matchingTodayPlanItem(for: normalizedTask)
        activePlanItemID = matchedPlanItem?.id
        activeTodoID = matchedPlanItem?.templateID
        activePlanReminderID = nil
        mode = .countdown
        settings.focusMinutes = safeMinutes
        durationSeconds = TimeInterval(safeMinutes * 60)
        displayedSeconds = durationSeconds
        targetDate = nil
        countupReferenceDate = nil
        persist()
    }

    private func matchingTodayPlanItem(for title: String) -> DailyPlanItem? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return todayPlanItems.first {
            $0.status != .completed
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    func startFloatingTimer(title: String, task taskTitle: String, minutes: Int) {
        guard phase == .idle || (phase == .focusPaused && mode == .countdown) else { return }
        configureFloatingTimer(title: title, task: taskTitle, minutes: minutes)
        startFocus()
    }

    /// 从任一悬浮入口开启新的临时倒计时。调用方负责在替换运行中计时前取得用户确认。
    func startNewFloatingCountdown(minutes: Int) {
        let safeMinutes = max(1, min(180, minutes))
        if phase != .idle { resetTimer() }
        startFloatingTimer(title: "", task: "临时专注", minutes: safeMinutes)
    }

    func updateCurrentTask(_ title: String) {
        task = title
        if let activeTodoID,
           let activeTodo = todos.first(where: { $0.id == activeTodoID }),
           activeTodo.title != title {
            self.activeTodoID = nil
        }
        persist()
    }

    func previewPetScene(_ mood: PetMood) {
        petReminderScene = mood
        petReminderToken += 1
    }

    func setMode(_ nextMode: TimerMode) {
        guard phase == .idle else { return }
        mode = nextMode
        displayedSeconds = nextMode == .countdown ? durationSeconds : 0
        persist()
    }

    func performPrimaryAction() {
        switch phase {
        case .idle: startFocus()
        case .focusRunning, .restRunning: pause()
        case .focusPaused, .restPaused: resume()
        case .focusFinished: startRest()
        case .restFinished: startNextFocus()
        }
    }

    func startFocus() {
        dismissCompletionFeedback()
        let now = Date()
        sessionStartedAt = now
        phase = .focusRunning
        if let activePlanItemID,
           let index = dailyPlanItems.firstIndex(where: { $0.id == activePlanItemID }),
           dailyPlanItems[index].status != .completed {
            dailyPlanItems[index].status = .running
            dailyPlanItems[index].actualStartedAt = dailyPlanItems[index].actualStartedAt ?? now
        }
        if mode == .countdown {
            displayedSeconds = durationSeconds
            targetDate = now.addingTimeInterval(durationSeconds)
            countupReferenceDate = nil
        } else {
            displayedSeconds = 0
            countupReferenceDate = now
            targetDate = nil
        }
        persist()
        syncToObsidianIfEnabled()
    }

    func startTodo(_ todo: TodoItem) {
        // 如果计时器正在运行，先停掉
        if phase != .idle {
            resetTimer()
        }
        mode = .countdown
        timerTitle = ""
        task = todo.title
        activeTodoID = todo.id
        activePlanItemID = nil
        durationSeconds = TimeInterval(todo.focusMinutes * 60)
        displayedSeconds = durationSeconds
        targetDate = nil
        countupReferenceDate = nil
        selectedSection = .focus
        startFocus()
    }

    func saveCurrentTaskAsTodo() {
        let title = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if let existing = todos.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            activeTodoID = existing.id
        } else {
            let todo = TodoItem(
                id: UUID(),
                title: title,
                focusMinutes: max(1, Int(durationSeconds / 60)),
                isCompleted: false,
                completedFocusCount: 0,
                createdAt: Date()
            )
            todos.insert(todo, at: 0)
            activeTodoID = todo.id
        }
        persist()
        syncToObsidianIfEnabled()
    }

    func addTodo(title: String, focusMinutes: Int) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        todos.insert(TodoItem(
            id: UUID(),
            title: normalized,
            focusMinutes: max(1, min(180, focusMinutes)),
            isCompleted: false,
            completedFocusCount: 0,
            createdAt: Date()
        ), at: 0)
        persist()
        syncToObsidianIfEnabled()
    }

    func addTaskTemplate(
        title: String,
        focusMinutes: Int,
        restMinutes: Int,
        category: String,
        symbol: String = "checkmark.square"
    ) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        todos.insert(TodoItem(
            id: UUID(),
            title: normalized,
            focusMinutes: max(1, min(180, focusMinutes)),
            isCompleted: false,
            completedFocusCount: 0,
            createdAt: Date(),
            restMinutes: max(1, min(60, restMinutes)),
            category: category,
            symbol: symbol
        ), at: 0)
        persist()
        syncToObsidianIfEnabled()
    }

    func addToDailyPlan(
        template: TodoItem,
        date: Date = Date(),
        reminderStartMinute: Int? = nil
    ) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let dayItems = dailyPlanItems.filter { calendar.isDate($0.date, inSameDayAs: day) }
        dailyPlanItems.append(DailyPlanItem(
            id: UUID(),
            templateID: template.id,
            title: template.title,
            date: day,
            reminderStartMinute: reminderStartMinute.map { max(0, min(23 * 60 + 59, $0)) },
            focusMinutes: template.focusMinutes,
            restMinutes: template.resolvedRestMinutes,
            order: (dayItems.map(\.order).max() ?? -1) + 1,
            status: .pending,
            actualStartedAt: nil,
            actualEndedAt: nil
        ))
        persist()
        syncToObsidianIfEnabled()
    }

    func addDailyPlanItem(
        title: String,
        date: Date,
        reminderStartMinute: Int?,
        focusMinutes: Int,
        restMinutes: Int
    ) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let template = TodoItem(
            id: UUID(),
            title: normalized,
            focusMinutes: max(1, min(180, focusMinutes)),
            isCompleted: false,
            completedFocusCount: 0,
            createdAt: Date(),
            restMinutes: max(1, min(60, restMinutes)),
            category: "自定义",
            symbol: "calendar.badge.clock"
        )
        todos.insert(template, at: 0)
        addToDailyPlan(template: template, date: date, reminderStartMinute: reminderStartMinute)
    }

    func startTodayPlan() {
        guard let next = nextPlanItem else { return }
        startPlanItem(next)
    }

    func startPlanItem(_ item: DailyPlanItem) {
        if phase != .idle { resetTimer() }
        guard let index = dailyPlanItems.firstIndex(where: { $0.id == item.id }) else { return }
        mode = .countdown
        timerTitle = ""
        task = item.title
        activeTodoID = item.templateID
        activePlanItemID = item.id
        if activePlanReminderID == item.id { activePlanReminderID = nil }
        settings.restMinutes = item.restMinutes
        durationSeconds = TimeInterval(item.focusMinutes * 60)
        displayedSeconds = durationSeconds
        dailyPlanItems[index].status = .running
        dailyPlanItems[index].actualStartedAt = Date()
        selectedSection = .focus
        startFocus()
    }

    func updatePlanItem(_ item: DailyPlanItem) {
        guard let index = dailyPlanItems.firstIndex(where: { $0.id == item.id }) else { return }
        dailyPlanItems[index] = item
        persist()
        syncToObsidianIfEnabled()
    }

    func setPlanItemStatus(_ id: UUID, status: DailyPlanStatus) {
        guard let index = dailyPlanItems.firstIndex(where: { $0.id == id }) else { return }
        dailyPlanItems[index].status = status
        if status == .completed { dailyPlanItems[index].actualEndedAt = Date() }
        if activePlanItemID == id && status != .running { activePlanItemID = nil }
        persist()
        syncToObsidianIfEnabled()
    }

    func togglePlanItemCompleted(_ id: UUID) {
        guard let index = dailyPlanItems.firstIndex(where: { $0.id == id }) else { return }
        if dailyPlanItems[index].status == .completed {
            dailyPlanItems[index].status = .pending
            dailyPlanItems[index].actualEndedAt = nil
        } else {
            dailyPlanItems[index].status = .completed
            dailyPlanItems[index].actualEndedAt = Date()
            if activePlanItemID == id {
                activePlanItemID = nil
                resetTimer()
            }
        }
        persist()
        syncToObsidianIfEnabled()
    }

    func deletePlanItem(_ id: UUID) {
        dailyPlanItems.removeAll { $0.id == id }
        if activePlanItemID == id { activePlanItemID = nil }
        normalizePlanOrder()
        persist()
        syncToObsidianIfEnabled()
    }

    func movePlanItem(_ id: UUID, offset: Int) {
        guard let movedItem = dailyPlanItems.first(where: { $0.id == id }) else { return }
        let sorted = dailyPlanItems
            .filter { Calendar.current.isDate($0.date, inSameDayAs: movedItem.date) }
            .sorted { $0.order < $1.order }
        guard let source = sorted.firstIndex(where: { $0.id == id }) else { return }
        let destination = max(0, min(sorted.count - 1, source + offset))
        guard source != destination else { return }
        var reordered = sorted
        let moved = reordered.remove(at: source)
        reordered.insert(moved, at: destination)
        for (order, item) in reordered.enumerated() {
            if let index = dailyPlanItems.firstIndex(where: { $0.id == item.id }) {
                dailyPlanItems[index].order = order
            }
        }
        persist()
        syncToObsidianIfEnabled()
    }

    func reorderPlanItem(_ draggedID: UUID, before targetID: UUID) {
        reorderPlanItemPreview(draggedID, relativeTo: targetID)
        commitPlanOrder()
    }

    /// 拖动经过行时只更新内存顺序，避免每一帧都写盘和同步 Obsidian。
    func reorderPlanItemPreview(_ draggedID: UUID, relativeTo targetID: UUID) {
        guard let draggedItem = dailyPlanItems.first(where: { $0.id == draggedID }) else { return }
        var items = dailyPlanItems
            .filter { Calendar.current.isDate($0.date, inSameDayAs: draggedItem.date) }
            .sorted { $0.order < $1.order }
        guard let source = items.firstIndex(where: { $0.id == draggedID }),
              let target = items.firstIndex(where: { $0.id == targetID }),
              source != target else { return }
        items.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: target > source ? target + 1 : target
        )
        for (order, item) in items.enumerated() {
            if let index = dailyPlanItems.firstIndex(where: { $0.id == item.id }) {
                dailyPlanItems[index].order = order
            }
        }
    }

    func commitPlanOrder() {
        persist()
        syncToObsidianIfEnabled()
    }

    func snoozePlanReminder(minutes: Int = 10) {
        guard let activePlanReminderID,
              let index = dailyPlanItems.firstIndex(where: { $0.id == activePlanReminderID }) else { return }
        dailyPlanItems[index].reminderSnoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        dailyPlanItems[index].reminderLastTriggeredAt = nil
        self.activePlanReminderID = nil
        persist()
    }

    func dismissPlanReminder() {
        activePlanReminderID = nil
        persist()
    }

    func startActivePlanReminder() {
        guard let item = activePlanReminderItem else { return }
        activePlanReminderID = nil
        startPlanItem(item)
    }

    func addTaskSet(name: String, templateIDs: [UUID]) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !templateIDs.isEmpty else { return }
        taskSets.append(TaskSet(id: UUID(), name: normalized, templateIDs: templateIDs, createdAt: Date()))
        persist()
        syncToObsidianIfEnabled()
    }

    func updateTaskSet(_ set: TaskSet) {
        guard let index = taskSets.firstIndex(where: { $0.id == set.id }) else { return }
        let normalized = set.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !set.templateIDs.isEmpty else { return }
        taskSets[index].name = normalized
        taskSets[index].templateIDs = set.templateIDs
        persist()
        syncToObsidianIfEnabled()
    }

    func deleteTaskSet(_ id: UUID) {
        taskSets.removeAll { $0.id == id }
        persist()
        syncToObsidianIfEnabled()
    }

    func addTaskSetToToday(_ set: TaskSet, date: Date = Date()) {
        for id in set.templateIDs {
            if let template = todos.first(where: { $0.id == id }) {
                addToDailyPlan(template: template, date: date)
            }
        }
    }

    private func normalizePlanOrder() {
        let grouped = Dictionary(grouping: dailyPlanItems, by: { Calendar.current.startOfDay(for: $0.date) })
        for items in grouped.values {
            for (order, item) in items.sorted(by: { $0.order < $1.order }).enumerated() {
                if let index = dailyPlanItems.firstIndex(where: { $0.id == item.id }) {
                    dailyPlanItems[index].order = order
                }
            }
        }
    }

    func toggleTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        persist()
        syncToObsidianIfEnabled()
    }

    func updateTodo(_ todo: TodoItem) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index] = todo
        persist()
        syncToObsidianIfEnabled()
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
        if activeTodoID == id { activeTodoID = nil }
        persist()
        syncToObsidianIfEnabled()
    }

    func pause() {
        guard phase.isRunning else { return }
        updateClock()
        phase = isRest ? .restPaused : .focusPaused
        targetDate = nil
        countupReferenceDate = nil
        persist()
    }

    func resume() {
        guard phase.isPaused else { return }
        let now = Date()
        phase = isRest ? .restRunning : .focusRunning
        if isRest || mode == .countdown {
            targetDate = now.addingTimeInterval(displayedSeconds)
        } else {
            countupReferenceDate = now.addingTimeInterval(-displayedSeconds)
        }
        persist()
    }

    func resetTimer() {
        phase = .idle
        targetDate = nil
        countupReferenceDate = nil
        sessionStartedAt = nil
        durationSeconds = TimeInterval(settings.focusMinutes * 60)
        displayedSeconds = mode == .countdown ? durationSeconds : 0
        isCompletionPresented = false
        completionFeedback = nil
        if let activePlanItemID,
           let index = dailyPlanItems.firstIndex(where: { $0.id == activePlanItemID }),
           dailyPlanItems[index].status == .running {
            dailyPlanItems[index].status = .pending
            dailyPlanItems[index].actualStartedAt = nil
        }
        activePlanItemID = nil
        persist()
    }

    /// 手动完成当前任务（倒计时提前结束 / 自由计时结束）。
    /// 与自动完成保持一致：记录完成结果后立即进入休息，休息可由用户手动跳过。
    func finishEarly() {
        guard phase == .focusRunning || phase == .focusPaused else { return }
        updateClock()
        let end = Date()
        // 记录实际专注时长（countdown 提前结束时也用真实 elapsed，而非计划时长）
        let session = appendFocusSession(result: .done, note: "", endedAt: end)
        isCompletionPresented = false
        presentCompletionFeedback(session)
        playSound(settings.timerAlertSound)
        notify(title: "任务完成", body: "已开始休息 (settings.restMinutes) 分钟，也可手动跳过。")
        startRest()
    }

    /// 跳过当前阶段：专注不计为完成，休息则直接结束。
    func skipCurrentPhase() {
        switch phase {
        case .focusRunning, .focusPaused:
            abandon(reason: "已跳过")
            activeTodoID = nil
            activePlanItemID = nil
            mode = .countdown
            durationSeconds = TimeInterval(settings.focusMinutes * 60)
            displayedSeconds = durationSeconds
            persist()
        case .restRunning, .restPaused:
            phase = .idle
            targetDate = nil
            countupReferenceDate = nil
            sessionStartedAt = nil
            activeTodoID = nil
            activePlanItemID = nil
            mode = .countdown
            durationSeconds = TimeInterval(settings.focusMinutes * 60)
            displayedSeconds = durationSeconds
            isCompletionPresented = false
            notify(title: "已跳过休息", body: "休息已结束。")
            persist()
        case .idle, .focusFinished, .restFinished:
            break
        }
    }

    /// 撤销悬浮成功反馈对应的完成记录，避免误删稍后产生的另一条记录。
    func undoCompletedSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id && $0.result == .done }) else {
            resetAfterUndo()
            return
        }
        removeCompletedSessionAndRollback(session)
        resetAfterUndo()
    }

    /// 兼容旧入口：撤销最近一次「已完成」记录。
    func undoLastCompletedSession() {
        guard let last = sessions.first(where: { $0.result == .done }) else {
            resetAfterUndo()
            return
        }
        removeCompletedSessionAndRollback(last)
        resetAfterUndo()
    }

    private func removeCompletedSessionAndRollback(_ session: FocusSession) {
        sessions.removeAll { $0.id == session.id }
        if let planItemID = session.planItemID,
           let index = dailyPlanItems.firstIndex(where: { $0.id == planItemID }) {
            dailyPlanItems[index].status = .pending
            dailyPlanItems[index].actualEndedAt = nil
        }
        if let todoID = session.todoID,
           let index = todos.firstIndex(where: { $0.id == todoID }) {
            todos[index].completedFocusCount = max(0, todos[index].completedFocusCount - 1)
        }
        if completionFeedback?.id == session.id { completionFeedback = nil }
    }

    private func resetAfterUndo() {
        phase = .idle
        sessionStartedAt = nil
        activePlanItemID = nil
        activeTodoID = nil
        mode = .countdown
        durationSeconds = TimeInterval(settings.focusMinutes * 60)
        displayedSeconds = durationSeconds
        targetDate = nil
        countupReferenceDate = nil
        isCompletionPresented = false
        completionFeedback = nil
        persist()
    }

    func dismissCompletionFeedback() {
        completionFeedback = nil
        if activeReminderIDs.isEmpty && activePlanReminderID == nil {
            petQuickControlsExpanded = false
            petPlanListCollapsed = true
        }
    }

    private func presentCompletionFeedback(_ session: FocusSession) {
        completionFeedback = session
        petQuickControlsExpanded = true
        petPlanListCollapsed = true
        let feedbackID = session.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard self?.completionFeedback?.id == feedbackID else { return }
            self?.dismissCompletionFeedback()
        }
    }

    func abandon(reason: String) {
        guard phase == .focusRunning || phase == .focusPaused else { return }
        updateClock()
        targetDate = nil
        countupReferenceDate = nil
        // 记录本轮实际专注时间 + 放弃原因，不计为完成，不触发休息
        appendFocusSession(result: .abandoned, note: reason, endedAt: Date())
        phase = .idle
        sessionStartedAt = nil
        durationSeconds = TimeInterval(settings.focusMinutes * 60)
        displayedSeconds = mode == .countdown ? durationSeconds : 0
        isCompletionPresented = false
        if let activePlanItemID {
            setPlanItemStatus(activePlanItemID, status: .skipped)
        }
        persist()
    }

    func extendFiveMinutes() {
        displayedSeconds += 300
        phase = .focusRunning
        targetDate = Date().addingTimeInterval(displayedSeconds)
        isCompletionPresented = false
        persist()
    }

    func saveProgress(result: SessionResult, note: String, startBreak: Bool = true) {
        let end = Date()
        let session = appendFocusSession(result: result, note: note, endedAt: end)
        isCompletionPresented = false
        if startBreak { startRest() } else { resetTimer() }
        if result == .done { presentCompletionFeedback(session) }
        persist()
    }

    @discardableResult
    private func appendFocusSession(
        result: SessionResult,
        note: String,
        endedAt end: Date,
        minutesOverride: Int? = nil
    ) -> FocusSession {
        let start = sessionStartedAt ?? end.addingTimeInterval(-max(1, durationSeconds - displayedSeconds))
        let minutes = minutesOverride ?? max(1, Int(ceil(end.timeIntervalSince(start) / 60)))
        let session = FocusSession(
            id: UUID(),
            task: task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名专注" : task,
            startedAt: start,
            endedAt: end,
            minutes: minutes,
            result: result,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            todoID: activeTodoID,
            planItemID: activePlanItemID
        )
        sessions.insert(session, at: 0)
        if result == .done,
           let activeTodoID,
           let index = todos.firstIndex(where: { $0.id == activeTodoID }) {
            todos[index].completedFocusCount += 1
            todos[index].isCompleted = false
        }
        if let activePlanItemID,
           let index = dailyPlanItems.firstIndex(where: { $0.id == activePlanItemID }) {
            dailyPlanItems[index].status = result == .done ? .completed : .pending
            dailyPlanItems[index].actualEndedAt = result == .done ? end : nil
        }
        syncToObsidianIfEnabled()
        return session
    }

    func updateSessionTask(id: UUID, newTask: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTask = trimmed.isEmpty ? "未命名专注" : trimmed
        var s = sessions[index]
        s.task = finalTask
        sessions[index] = s
        persist()
        syncToObsidianIfEnabled()
    }

    func startRest() {
        let seconds = TimeInterval(settings.restMinutes * 60)
        phase = .restRunning
        durationSeconds = seconds
        displayedSeconds = seconds
        targetDate = Date().addingTimeInterval(seconds)
        countupReferenceDate = nil
        sessionStartedAt = Date()
        activePlanItemID = nil
        if !queuedReminderIDs.isEmpty {
            activeReminderIDs = queuedReminderIDs
            queuedReminderIDs = []
            signalReminder()
        }
        persist()
    }

    func startNextFocus() {
        dismissCompletionFeedback()
        mode = .countdown
        durationSeconds = TimeInterval(settings.focusMinutes * 60)
        displayedSeconds = durationSeconds
        sessionStartedAt = Date()
        phase = .focusRunning
        targetDate = Date().addingTimeInterval(durationSeconds)
        persist()
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        if phase == .idle {
            durationSeconds = TimeInterval(settings.focusMinutes * 60)
            displayedSeconds = mode == .countdown ? durationSeconds : 0
        }
        persist()
    }

    func previewSound(_ sound: AlertSound) {
        playSound(sound)
    }

    func chooseObsidianVault() {
        let panel = NSOpenPanel()
        panel.title = "选择 Obsidian 仓库"
        panel.message = "请选择包含 .obsidian 文件夹的仓库根目录。"
        panel.prompt = "连接仓库"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let metadata = url.appendingPathComponent(".obsidian", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: metadata.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                obsidianSyncStatus = "所选文件夹不是 Obsidian 仓库"
                return
            }
            settings.obsidianVaultPath = url.standardizedFileURL.path
            obsidianSyncStatus = "已连接：\(url.lastPathComponent)"
            persist()
            syncToObsidian()
        }
    }

    func disconnectObsidian() {
        settings.obsidianVaultPath = nil
        obsidianSyncStatus = "已取消链接"
        persist()
    }

    func syncToObsidian() {
        guard let vaultPath = settings.obsidianVaultPath, !vaultPath.isEmpty else {
            obsidianSyncStatus = "请先选择 Obsidian 仓库"
            return
        }
        let fileManager = FileManager.default
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true).standardizedFileURL
        let metadataURL = vaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: metadataURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            obsidianSyncStatus = "仓库路径已失效，请重新选择"
            return
        }

        let outputFolder = vaultURL.appendingPathComponent("FocusDock", isDirectory: true)
        do {
            try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            let calendar = Calendar.current
            let eventDates = sessions.map(\.startedAt) + reminderEvents.map(\.date) + dailyPlanItems.map(\.date)
            let days = Set(eventDates.map { calendar.startOfDay(for: $0) } + [calendar.startOfDay(for: Date())])
            for day in days.sorted() {
                try writeObsidianDay(day, to: outputFolder)
            }
            try writeObsidianTaskDatabase(to: outputFolder)
            obsidianSyncStatus = "已同步 \(days.count) 天记录 · \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch {
            obsidianSyncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    private func syncToObsidianIfEnabled() {
        if settings.obsidianAutoSync { syncToObsidian() }
    }

    private func writeObsidianDay(_ day: Date, to folder: URL) throws {
        let calendar = Calendar.current
        let daySessions = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }.sorted { $0.startedAt < $1.startedAt }
        let dayReminders = reminderEvents.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
        let dayPlan = dailyPlanItems
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.order < $1.order }
        let totalFocusMinutes = daySessions.reduce(0) { $0 + $1.minutes }
        let completedSessions = daySessions.filter { $0.result == .done }.count
        let progressSessions = daySessions.filter { $0.result == .progress }.count
        let abandonedSessions = daySessions.filter { $0.result == .abandoned }.count
        let reminderDoneCount = dayReminders.filter(\.completed).count
        let reminderPendingCount = dayReminders.count - reminderDoneCount
        let completedPlanCount = dayPlan.filter { $0.status == .completed }.count
        let focusedTaskNames = Set(daySessions.map { markdownSafe($0.task) }.filter { !$0.isEmpty })
        let topTasks = focusedTaskNames.sorted().prefix(3).joined(separator: "、")
        let filenameFormatter = DateFormatter()
        filenameFormatter.calendar = calendar
        filenameFormatter.timeZone = calendar.timeZone
        filenameFormatter.locale = Locale(identifier: "en_US_POSIX")
        filenameFormatter.dateFormat = "yyyy-MM-dd"
        let filename = filenameFormatter.string(from: day) + ".md"
        let fileURL = folder.appendingPathComponent(filename)
        let title = day.formatted(.dateTime.year().month().day())

        var lines = [
            "## 今日节奏",
            "",
            "| 指标 | 数值 |",
            "| --- | ---: |",
            "| 专注轮次 | \(daySessions.count) |",
            "| 专注时长 | \(totalFocusMinutes) 分钟 |",
            "| 完成轮次 | \(completedSessions) |",
            "| 提醒 | \(reminderDoneCount)/\(dayReminders.count) 已完成 |",
            "",
            "> \(topTasks.isEmpty ? "今天还没有记录专注任务。" : "主要投入：\(topTasks)。")\(reminderPendingCount > 0 ? " 还有 \(reminderPendingCount) 条提醒未处理。" : "")",
            "",
            "## 每日计划"
        ]
        lines.append("")
        lines.append("关联：[[FocusDock/任务库|任务库]] · [[FocusDock/任务集|任务集]]")
        lines.append("")
        if dayPlan.isEmpty {
            lines.append("- [ ] 暂无计划")
        } else {
            lines.append(contentsOf: [
                "| 提醒开始 | 任务 | 专注 | 休息 | 状态 | ID |",
                "| --- | --- | ---: | ---: | --- | --- |"
            ])
            for item in dayPlan {
                let status = effectivePlanStatus(item)
                let checked = status == .completed ? "✅ " : ""
                let planLink = "[[\(folder.lastPathComponent)/每日计划数据库/\(item.id.uuidString)|\(tableSafe(item.title))]]"
                lines.append("| \(item.reminderTimeText ?? "不设时间") | \(checked)\(planLink) | \(item.focusMinutes) 分钟 | \(item.restMinutes) 分钟 | \(status.title) | `\(item.id.uuidString)` |")
            }
        }
        lines.append(contentsOf: [
            "",
            "## 专注记录"
        ])
        if daySessions.isEmpty {
            lines.append("- 暂无专注记录")
        } else {
            lines.append(contentsOf: [
                "| 开始 | 任务 | 时长 | 结果 | 备注 |",
                "| --- | --- | ---: | --- | --- |"
            ])
            for session in daySessions {
                let time = session.startedAt.formatted(date: .omitted, time: .shortened)
                let task = tableSafe(session.task.isEmpty ? "未命名专注" : session.task)
                let note = session.note.isEmpty ? "" : tableSafe(session.note)
                lines.append("| \(time) | \(task) | \(session.minutes) 分钟 | \(session.result.title) | \(note) |")
            }
        }

        if calendar.isDateInToday(day) {
            lines.append(contentsOf: ["", "## 任务库快照"])
            if todos.isEmpty {
                lines.append("- 暂无任务模板")
            } else {
                for todo in todos {
                    lines.append("- \(markdownSafe(todo.title)) · \(todo.focusMinutes)+\(todo.resolvedRestMinutes) 分钟 · \(markdownSafe(todo.resolvedCategory)) · `\(todo.id.uuidString)`")
                }
            }
        }

        lines.append(contentsOf: ["", "## 提醒"])
        if dayReminders.isEmpty {
            lines.append("- 暂无提醒记录")
        } else {
            let groupedReminders = Dictionary(grouping: dayReminders, by: \.reminderName)
            lines.append(contentsOf: [
                "| 提醒 | 完成 | 未处理 |",
                "| --- | ---: | ---: |"
            ])
            for name in groupedReminders.keys.sorted() {
                let events = groupedReminders[name] ?? []
                let done = events.filter(\.completed).count
                lines.append("| \(tableSafe(name)) | \(done) | \(events.count - done) |")
            }
            lines.append("")
            lines.append("<details>")
            lines.append("<summary>查看提醒明细</summary>")
            lines.append("")
            for event in dayReminders {
                lines.append("- [\(event.completed ? "x" : " ")] \(event.date.formatted(date: .omitted, time: .shortened)) · \(markdownSafe(event.reminderName))")
            }
            lines.append("")
            lines.append("</details>")
        }
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let output = ObsidianNoteDocument.render(
            existing: existing,
            displayTitle: title,
            managedLines: lines,
            properties: ObsidianDailyProperties(
                date: String(filename.dropLast(3)),
                focusMinutes: totalFocusMinutes,
                focusSessions: daySessions.count,
                completedSessions: completedSessions,
                progressSessions: progressSessions,
                abandonedSessions: abandonedSessions,
                reminderDone: reminderDoneCount,
                reminderTotal: dayReminders.count,
                plannedTasks: dayPlan.count,
                completedPlanTasks: completedPlanCount
            )
        )
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeObsidianTaskDatabase(to folder: URL) throws {
        let fileManager = FileManager.default
        let taskDatabaseURL = folder.appendingPathComponent("任务数据库", isDirectory: true)
        let planDatabaseURL = folder.appendingPathComponent("每日计划数据库", isDirectory: true)
        try fileManager.createDirectory(at: taskDatabaseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: planDatabaseURL, withIntermediateDirectories: true)

        let libraryURL = folder.appendingPathComponent("任务库.md")
        var library = [
            "---",
            "type: focusdock-task-library",
            "title: FocusDock 任务库",
            "tags: [focusdock, task-library, productivity]",
            "source: FocusDock",
            "focusdock_schema: 3",
            "updated_at: \(Date.now.formatted(.iso8601))",
            "---",
            "",
            "# FocusDock 任务库",
            "",
            "> 此文件由 FocusDock 管理。UUID 用于应用与 Obsidian 之间稳定关联。",
            "",
            "| 任务 | 分类 | 专注 | 休息 | 累计执行 | UUID |",
            "| --- | --- | ---: | ---: | ---: | --- |"
        ]
        for item in todos {
            let link = "[[\(folder.lastPathComponent)/任务数据库/\(item.id.uuidString)|\(tableSafe(item.title))]]"
            library.append("| \(link) | \(tableSafe(item.resolvedCategory)) | \(item.focusMinutes) | \(item.resolvedRestMinutes) | \(item.completedFocusCount) | `\(item.id.uuidString)` |")

            let entityURL = taskDatabaseURL.appendingPathComponent("\(item.id.uuidString).md")
            let existing = (try? String(contentsOf: entityURL, encoding: .utf8)) ?? ""
            let frontmatter = [
                "type: focusdock-task",
                "title: \(yamlQuoted(item.title))",
                "tags: [focusdock, task-template, productivity]",
                "source: FocusDock",
                "focusdock_schema: 3",
                "task_id: \(item.id.uuidString)",
                "category: \(yamlQuoted(item.resolvedCategory))",
                "focus_minutes: \(item.focusMinutes)",
                "rest_minutes: \(item.resolvedRestMinutes)",
                "completed_focus_count: \(item.completedFocusCount)",
                "updated_at: \(Date.now.formatted(.iso8601))"
            ]
            let body = renderManagedEntity(
                existing: existing,
                frontmatterLines: frontmatter,
                title: item.title,
                managedLines: [
                    "## FocusDock 数据",
                    "",
                    "- 分类：\(markdownSafe(item.resolvedCategory))",
                    "- 专注 / 休息：\(item.focusMinutes) / \(item.resolvedRestMinutes) 分钟",
                    "- 累计执行：\(item.completedFocusCount) 次"
                ]
            )
            try body.write(to: entityURL, atomically: true, encoding: .utf8)
        }
        try (library.joined(separator: "\n") + "\n").write(to: libraryURL, atomically: true, encoding: .utf8)

        let setsURL = folder.appendingPathComponent("任务集.md")
        var sets = [
            "---",
            "type: focusdock-task-sets",
            "title: FocusDock 任务集",
            "tags: [focusdock, task-set, productivity]",
            "source: FocusDock",
            "focusdock_schema: 3",
            "---",
            "",
            "# FocusDock 任务集",
            ""
        ]
        if taskSets.isEmpty {
            sets.append("- 暂无任务集")
        } else {
            for set in taskSets {
                sets.append("## \(markdownSafe(set.name))")
                sets.append("")
                sets.append("<!-- focusdock-set-id: \(set.id.uuidString) -->")
                for id in set.templateIDs {
                    let title = todos.first(where: { $0.id == id })?.title ?? "已删除任务"
                    sets.append("- \(markdownSafe(title)) `\(id.uuidString)`")
                }
                sets.append("")
            }
        }
        try (sets.joined(separator: "\n") + "\n").write(to: setsURL, atomically: true, encoding: .utf8)

        for item in dailyPlanItems {
            let entityURL = planDatabaseURL.appendingPathComponent("\(item.id.uuidString).md")
            let existing = (try? String(contentsOf: entityURL, encoding: .utf8)) ?? ""
            let date = item.date.formatted(.iso8601.year().month().day())
            let templateID = item.templateID?.uuidString ?? ""
            let taskLink = item.templateID.map {
                "[[\(folder.lastPathComponent)/任务数据库/\($0.uuidString)|\(markdownSafe(item.title))]]"
            } ?? markdownSafe(item.title)
            let frontmatter = [
                "type: focusdock-daily-plan-item",
                "title: \(yamlQuoted(item.title))",
                "tags: [focusdock, daily-plan, productivity]",
                "source: FocusDock",
                "focusdock_schema: 3",
                "plan_id: \(item.id.uuidString)",
                "task_id: \(templateID.isEmpty ? "null" : templateID)",
                "date: \(date)",
                "reminder_start: \(item.reminderTimeText.map(yamlQuoted) ?? "null")",
                "focus_minutes: \(item.focusMinutes)",
                "rest_minutes: \(item.restMinutes)",
                "plan_order: \(item.order)",
                "status: \(item.status.rawValue)",
                "actual_started_at: \(item.actualStartedAt?.formatted(.iso8601) ?? "null")",
                "actual_ended_at: \(item.actualEndedAt?.formatted(.iso8601) ?? "null")"
            ]
            let body = renderManagedEntity(
                existing: existing,
                frontmatterLines: frontmatter,
                title: item.title,
                managedLines: [
                    "## FocusDock 数据",
                    "",
                    "- 所属任务：\(taskLink)",
                    "- 日期：\(date)",
                    "- 提醒开始：\(item.reminderTimeText ?? "不设时间")",
                    "- 专注 / 休息：\(item.focusMinutes) / \(item.restMinutes) 分钟",
                    "- 状态：\(item.status.title)"
                ]
            )
            try body.write(to: entityURL, atomically: true, encoding: .utf8)
        }
    }

    private func renderManagedEntity(
        existing: String,
        frontmatterLines: [String],
        title: String,
        managedLines: [String]
    ) -> String {
        let start = "<!-- focusdock-entity:start -->"
        let end = "<!-- focusdock-entity:end -->"
        let managed = ([start] + managedLines + [end]).joined(separator: "\n")
        var manual = existing
        if manual.hasPrefix("---\n"),
           let close = manual.range(of: "\n---\n", range: manual.index(manual.startIndex, offsetBy: 4)..<manual.endIndex) {
            manual.removeSubrange(manual.startIndex..<close.upperBound)
        }
        if let startRange = manual.range(of: start),
           let endRange = manual.range(of: end, range: startRange.upperBound..<manual.endIndex) {
            manual.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: managed)
        } else if manual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manual = "# \(markdownSafe(title))\n\n\(managed)\n\n## 我的备注\n\n"
        } else {
            manual = managed + "\n\n" + manual.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
        return (["---"] + frontmatterLines + ["---", ""]).joined(separator: "\n")
            + manual.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    private func yamlQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " "))\""
    }

    private func markdownSafe(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    private func tableSafe(_ value: String) -> String {
        markdownSafe(value)
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func addReminder(
        name: String,
        interval: Int,
        policy: ReminderPolicy,
        symbol: String = "figure.stand",
        activeStartMinute: Int = 9 * 60,
        activeEndMinute: Int = 22 * 60
    ) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = max(1, interval)
        let now = Date()
        reminders.append(ReminderRule(
            id: UUID(),
            name: normalized.isEmpty ? "自定义提醒" : normalized,
            symbol: symbol,
            intervalMinutes: minutes,
            isEnabled: true,
            policy: policy,
            activeStartMinute: activeStartMinute,
            activeEndMinute: activeEndMinute,
            nextFireAt: nextReminderDate(from: now, intervalMinutes: minutes, activeStartMinute: activeStartMinute, activeEndMinute: activeEndMinute)
        ))
        persist()
    }

    func toggleReminder(_ id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].isEnabled.toggle()
        reminders[index].nextFireAt = nextReminderDate(for: reminders[index], from: Date())
        persist()
    }

    func updateReminder(_ rule: ReminderRule) {
        guard let index = reminders.firstIndex(where: { $0.id == rule.id }) else { return }
        var updated = rule
        updated.nextFireAt = nextReminderDate(for: updated, from: Date())
        reminders[index] = updated
        persist()
    }

    func deleteReminder(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        activeReminderIDs.removeAll { $0 == id }
        queuedReminderIDs.removeAll { $0 == id }
        persist()
    }

    func previewReminders() {
        activeReminderIDs = reminders.filter(\.isEnabled).prefix(3).map(\.id)
        signalReminder()
    }

    func resolveActiveReminders(completed: Bool) {
        let now = Date()
        activeReminderNames.forEach { name in
            reminderEvents.insert(ReminderEvent(id: UUID(), reminderName: name, date: now, completed: completed), at: 0)
        }
        activeReminderIDs = []
        collapsePetControlsToTimerBoard()
        persist()
        syncToObsidianIfEnabled()
    }

    func snoozeActiveReminders(minutes: Int = 10) {
        let active = Set(activeReminderIDs)
        let nextDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        for index in reminders.indices where active.contains(reminders[index].id) {
            reminders[index].nextFireAt = nextDate
        }
        activeReminderIDs = []
        collapsePetControlsToTimerBoard()
        persist()
    }

    func collapsePetControlsToTimerBoard() {
        petQuickControlsExpanded = false
        petPlanListCollapsed = true
        petReminderScene = nil
    }

    func clearAllData() {
        sessions = []
        reminderEvents = []
        resetTimer()
        persist()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .notDetermined:
                    do {
                        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        self.settings.notificationsEnabled = granted
                        self.notificationBlocked = false
                        self.notificationHint = granted ? nil : "已选择暂不开启，需要时可在系统设置里重新允许。"
                        self.persist()
                    } catch {
                        self.settings.notificationsEnabled = false
                        self.notificationBlocked = false
                        self.notificationHint = "请求通知授权失败，请检查系统设置。"
                        self.persist()
                    }
                case .denied:
                    self.settings.notificationsEnabled = false
                    self.notificationBlocked = true
                    self.notificationHint = "通知已被系统拒绝。请打开「系统设置 → 通知 → FocusDock」手动开启。"
                    self.persist()
                case .authorized, .provisional, .ephemeral:
                    self.settings.notificationsEnabled = true
                    self.notificationBlocked = false
                    self.notificationHint = nil
                    self.persist()
                @unknown default:
                    self.settings.notificationsEnabled = false
                    self.notificationBlocked = false
                    self.notificationHint = "无法读取通知权限状态，请检查系统设置。"
                    self.persist()
                }
            }
        }
    }

    func refreshNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                guard let self else { return }
                let authorized = status == .authorized || status == .provisional
                self.settings.notificationsEnabled = authorized
                self.notificationBlocked = status == .denied
                self.persist()
            }
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func startClock() {
        clock = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateClock() }
    }

    private func updateClock() {
        let now = Date()
        let second = Int(now.timeIntervalSinceReferenceDate)
        if second != lastPublishedSecond {
            lastPublishedSecond = second
            self.now = now
        }
        if phase == .focusRunning {
            if mode == .countdown, let targetDate {
                displayedSeconds = max(0, targetDate.timeIntervalSince(now).rounded(.up))
                if displayedSeconds <= 0 { finishFocus() }
            } else if let countupReferenceDate {
                displayedSeconds = max(0, now.timeIntervalSince(countupReferenceDate).rounded(.down))
            }
        } else if phase == .restRunning, let targetDate {
            displayedSeconds = max(0, targetDate.timeIntervalSince(now).rounded(.up))
            if displayedSeconds <= 0 { finishRest() }
        }
        checkReminders(at: now)
        checkPlanReminders(at: now)
    }

    private func checkPlanReminders(at now: Date) {
        let calendar = Calendar.current
        guard activePlanReminderID == nil else { return }
        guard let index = dailyPlanItems.indices.first(where: { index in
            let item = dailyPlanItems[index]
            guard calendar.isDateInToday(item.date),
                  item.status == .pending,
                  item.reminderLastTriggeredAt.map({ !calendar.isDate($0, inSameDayAs: now) }) ?? true else {
                return false
            }
            if let snoozed = item.reminderSnoozedUntil {
                return snoozed <= now
            }
            guard let minute = item.reminderStartMinute,
                  let due = calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: now)) else {
                return false
            }
            return due <= now
        }) else { return }

        dailyPlanItems[index].reminderLastTriggeredAt = now
        dailyPlanItems[index].reminderSnoozedUntil = nil
        activePlanReminderID = dailyPlanItems[index].id
        petQuickControlsExpanded = true
        reminderPulse.toggle()
        playSound(settings.reminderAlertSound, repetitions: 2)
        notify(
            title: "计划现在开始",
            body: "\(dailyPlanItems[index].title) · 专注 \(dailyPlanItems[index].focusMinutes) 分钟"
        )
        persist()
    }

    private func finishFocus() {
        guard phase == .focusRunning else { return }
        let end = Date()
        displayedSeconds = 0
        targetDate = nil
        countupReferenceDate = nil
        let session = appendFocusSession(
            result: .done,
            note: "",
            endedAt: end,
            minutesOverride: mode == .countdown ? max(1, Int(durationSeconds / 60)) : nil
        )
        isCompletionPresented = false
        playSound(settings.timerAlertSound)
        notify(title: "专注完成", body: "已自动开始休息 \(settings.restMinutes) 分钟。")
        startRest()
        presentCompletionFeedback(session)
    }

    private func finishRest() {
        guard phase == .restRunning else { return }
        phase = .idle
        targetDate = nil
        countupReferenceDate = nil
        sessionStartedAt = nil
        activeTodoID = nil
        mode = .countdown
        durationSeconds = TimeInterval(settings.focusMinutes * 60)
        displayedSeconds = durationSeconds
        selectedSection = .focus
        playSound(settings.timerAlertSound)
        notify(title: "休息结束", body: "已回到专注首页。")
        persist()
    }

    private func checkReminders(at now: Date) {
        let dueIndices = reminders.indices.filter { reminders[$0].isEnabled && reminders[$0].nextFireAt <= now }
        guard !dueIndices.isEmpty else { return }
        var immediate: [UUID] = []
        for index in dueIndices {
            let rule = reminders[index]
            if !isWithinReminderWindow(rule, at: now) {
                reminders[index].nextFireAt = nextReminderDate(for: rule, from: now)
            } else if phase == .focusRunning && rule.policy == .deferToBreak {
                if !queuedReminderIDs.contains(rule.id) { queuedReminderIDs.append(rule.id) }
                reminders[index].nextFireAt = nextReminderDate(for: rule, from: now)
            } else {
                immediate.append(rule.id)
                reminders[index].nextFireAt = nextReminderDate(for: rule, from: now)
            }
        }
        if !immediate.isEmpty {
            activeReminderIDs = Array(Set(activeReminderIDs + immediate))
            signalReminder()
        }
        persist()
    }

    private func signalReminder() {
        reminderPulse.toggle()
        petQuickControlsExpanded = true
        playSound(settings.reminderAlertSound, repetitions: 2)
        let names = activeReminderNames.joined(separator: " · ")
        notify(title: "提醒", body: names)
        // 让桌宠演示与提醒对应的场景动作（喝水/活动/护眼/挥手）
        if let firstName = activeReminderNames.first {
            petReminderScene = PetMood.reminderScene(named: firstName)
            petReminderToken += 1
        }
    }

    private func playSound(_ sound: AlertSound, repetitions: Int = 1) {
        guard settings.soundEnabled else { return }
        let soundURL = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
            .appendingPathComponent("\(sound.systemName).aiff")
        guard FileManager.default.fileExists(atPath: soundURL.path) else {
            NSSound.beep()
            return
        }
        do {
            activeAudioPlayer?.stop()
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.volume = 1
            player.numberOfLoops = max(0, repetitions - 1)
            player.prepareToPlay()
            activeAudioPlayer = player
            if !player.play() {
                NSSound.beep()
            }
        } catch {
            NSSound.beep()
        }
    }

    private func notify(title: String, body: String) {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    @discardableResult
    private func normalizeRestoredTimer() -> Bool {
        let now = Date()
        if phase == .focusRunning || phase == .restRunning {
            if let targetDate {
                displayedSeconds = max(0, targetDate.timeIntervalSince(now).rounded(.up))
                if displayedSeconds <= 0 {
                    if phase == .focusRunning {
                        let focusEndedAt = targetDate
                        let session = appendFocusSession(
                            result: .done,
                            note: "",
                            endedAt: focusEndedAt,
                            minutesOverride: max(1, Int(durationSeconds / 60))
                        )
                        let restDuration = TimeInterval(settings.restMinutes * 60)
                        let restEndsAt = focusEndedAt.addingTimeInterval(restDuration)
                        if restEndsAt > now {
                            phase = .restRunning
                            durationSeconds = restDuration
                            displayedSeconds = restEndsAt.timeIntervalSince(now).rounded(.up)
                            self.targetDate = restEndsAt
                            countupReferenceDate = nil
                            sessionStartedAt = focusEndedAt
                        } else {
                            restoreIdleAfterCompletedRest()
                        }
                        presentCompletionFeedback(session)
                    } else {
                        restoreIdleAfterCompletedRest()
                    }
                    return true
                }
            } else if mode == .countup, let countupReferenceDate {
                displayedSeconds = max(0, now.timeIntervalSince(countupReferenceDate).rounded(.down))
            }
        }
        return false
    }

    private func restoreIdleAfterCompletedRest() {
        phase = .idle
        mode = .countdown
        targetDate = nil
        countupReferenceDate = nil
        sessionStartedAt = nil
        activeTodoID = nil
        durationSeconds = TimeInterval(settings.focusMinutes * 60)
        displayedSeconds = durationSeconds
        selectedSection = .focus
    }

    private func defaultReminders() -> [ReminderRule] {
        let now = Date()
        return [
            ReminderRule(id: UUID(), name: "喝水", symbol: "drop.fill", intervalMinutes: 40, isEnabled: true, policy: .deferToBreak, nextFireAt: now.addingTimeInterval(40 * 60)),
            ReminderRule(id: UUID(), name: "站起来活动", symbol: "figure.stand", intervalMinutes: 60, isEnabled: true, policy: .deferToBreak, nextFireAt: now.addingTimeInterval(60 * 60)),
            ReminderRule(id: UUID(), name: "远眺 20 秒", symbol: "eye.fill", intervalMinutes: 20, isEnabled: true, policy: .gentle, nextFireAt: now.addingTimeInterval(20 * 60))
        ]
    }

    private func nextReminderDate(for rule: ReminderRule, from date: Date) -> Date {
        nextReminderDate(
            from: date,
            intervalMinutes: rule.intervalMinutes,
            activeStartMinute: rule.activeStartMinute,
            activeEndMinute: rule.activeEndMinute
        )
    }

    private func nextReminderDate(from date: Date, intervalMinutes: Int, activeStartMinute: Int, activeEndMinute: Int) -> Date {
        let calendar = Calendar.current
        let candidate = date.addingTimeInterval(TimeInterval(max(1, intervalMinutes) * 60))
        if isMinuteWindow(activeStartMinute, activeEndMinute, containing: candidate) { return candidate }

        let day = calendar.startOfDay(for: candidate)
        let candidateMinute = calendar.component(.hour, from: candidate) * 60 + calendar.component(.minute, from: candidate)
        if candidateMinute < activeStartMinute {
            return calendar.date(byAdding: .minute, value: activeStartMinute, to: day) ?? candidate
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return calendar.date(byAdding: .minute, value: activeStartMinute, to: nextDay) ?? candidate
    }

    private func isWithinReminderWindow(_ rule: ReminderRule, at date: Date) -> Bool {
        isMinuteWindow(rule.activeStartMinute, rule.activeEndMinute, containing: date)
    }

    private func isMinuteWindow(_ startMinute: Int, _ endMinute: Int, containing date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if startMinute <= endMinute {
            return minute >= startMinute && minute <= endMinute
        }
        return minute >= startMinute || minute <= endMinute
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(PersistedAppState.self, from: data) else {
            reminders = defaultReminders()
            durationSeconds = TimeInterval(settings.focusMinutes * 60)
            displayedSeconds = durationSeconds
            return
        }
        settings = state.settings
        reminders = state.reminders
        todos = state.todos ?? []
        taskSets = state.taskSets ?? []
        dailyPlanItems = state.dailyPlanItems ?? []
        sessions = state.sessions
        reminderEvents = state.reminderEvents
        phase = state.timer.phase
        mode = state.timer.mode
        timerTitle = state.timer.timerTitle ?? ""
        task = state.timer.task
        durationSeconds = state.timer.durationSeconds
        displayedSeconds = state.timer.displayedSeconds
        targetDate = state.timer.targetDate
        countupReferenceDate = state.timer.countupReferenceDate
        sessionStartedAt = state.timer.sessionStartedAt
        activeTodoID = state.timer.activeTodoID
        activePlanItemID = state.timer.activePlanItemID
    }

    /// V2 升级为正式 FocusDock 后，优先复制独立 V2 应用的完整状态。
    /// V1 使用的 `FocusDock.AppState.v1` 保留不动，因此切回稳定标签仍可读取旧数据。
    private func copyStandaloneV2StateIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: storageKey) == nil,
              !defaults.bool(forKey: promotionMarker) else { return false }

        defer { defaults.set(true, forKey: promotionMarker) }
        guard let standaloneDefaults = UserDefaults(suiteName: standaloneV2SuiteName),
              let v2Data = standaloneDefaults.data(forKey: storageKey),
              (try? JSONDecoder().decode(PersistedAppState.self, from: v2Data)) != nil else {
            return false
        }

        defaults.set(v2Data, forKey: storageKey)
        return true
    }

    /// 没有独立 V2 数据时才复制 V1；不修改或删除 V1 的偏好域。
    /// 复制后的计时器回到空闲，且 Obsidian 自动同步关闭，避免两个版本同时计时或写入同一目录。
    private func copyV1StateIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: storageKey) == nil,
              !defaults.bool(forKey: v1MigrationMarker) else { return false }

        defer { defaults.set(true, forKey: v1MigrationMarker) }
        guard let v1Defaults = UserDefaults(suiteName: v1SuiteName),
              let v1Data = v1Defaults.data(forKey: v1StorageKey),
              var state = try? JSONDecoder().decode(PersistedAppState.self, from: v1Data) else {
            return false
        }

        state.settings.obsidianAutoSync = false
        state.timer.phase = .idle
        state.timer.displayedSeconds = state.timer.mode == .countdown ? state.timer.durationSeconds : 0
        state.timer.targetDate = nil
        state.timer.countupReferenceDate = nil
        state.timer.sessionStartedAt = nil
        state.timer.activeTodoID = nil
        state.timer.activePlanItemID = nil

        guard let v2Data = try? JSONEncoder().encode(state) else { return false }
        defaults.set(v2Data, forKey: storageKey)
        return true
    }

    func persist() {
        guard !isLoading else { return }
        let state = PersistedAppState(
            settings: settings,
            reminders: reminders,
            sessions: sessions,
            reminderEvents: reminderEvents,
            todos: todos,
            taskSets: taskSets,
            dailyPlanItems: dailyPlanItems,
            timer: PersistedTimer(
                phase: phase,
                mode: mode,
                timerTitle: timerTitle,
                task: task,
                durationSeconds: durationSeconds,
                displayedSeconds: displayedSeconds,
                targetDate: targetDate,
                countupReferenceDate: countupReferenceDate,
                sessionStartedAt: sessionStartedAt,
                activeTodoID: activeTodoID,
                activePlanItemID: activePlanItemID
            )
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
