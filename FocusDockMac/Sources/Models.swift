import Foundation
import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Codable, Identifiable {
    case focus
    case dailyPlan
    case todos
    case reminders
    case review
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "专注"
        case .dailyPlan: "计划"
        case .todos: "任务"
        case .reminders: "提醒"
        case .review: "统计"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "timer"
        case .dailyPlan: "calendar.badge.clock"
        case .todos: "square.grid.2x2"
        case .reminders: "bell"
        case .review: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

enum TimerMode: String, Codable, CaseIterable {
    case countdown
    case countup
}

enum TimerPhase: String, Codable {
    case idle
    case focusRunning
    case focusPaused
    case focusFinished
    case restRunning
    case restPaused
    case restFinished

    var isRunning: Bool { self == .focusRunning || self == .restRunning }
    var isPaused: Bool { self == .focusPaused || self == .restPaused }
    var isRest: Bool { self == .restRunning || self == .restPaused || self == .restFinished }
    var isFocus: Bool { !isRest }
}

enum TimerEntrySource: Equatable {
    case standalone
    case dailyPlan(UUID)
}

struct ActiveTimerPresentation: Equatable {
    let source: TimerEntrySource
    let title: String
    let timeText: String
    let phase: TimerPhase
}

enum ActiveTimerPresentationPolicy {
    static func resolve(
        phase: TimerPhase,
        timeText: String,
        taskTitle: String,
        activePlanItemID: UUID?
    ) -> ActiveTimerPresentation? {
        guard phase.isRunning || phase.isPaused else { return nil }
        let source = activePlanItemID.map(TimerEntrySource.dailyPlan) ?? .standalone
        return ActiveTimerPresentation(
            source: source,
            title: phase.isRest ? "休息" : taskTitle,
            timeText: timeText,
            phase: phase
        )
    }
}

enum PlanTab: String, CaseIterable {
    case upcoming
    case completed

    var title: String {
        switch self {
        case .upcoming: "待完成"
        case .completed: "已完成"
        }
    }
}

enum SessionResult: String, Codable, CaseIterable, Identifiable {
    case done
    case progress
    case interrupted
    case abandoned

    var id: String { rawValue }
    var title: String {
        switch self {
        case .done: "已完成"
        case .progress: "有一些进展"
        case .interrupted: "被打断了"
        case .abandoned: "已放弃"
        }
    }
}

struct FocusSession: Codable, Identifiable {
    let id: UUID
    var task: String
    var startedAt: Date
    var endedAt: Date
    var minutes: Int
    var result: SessionResult
    var note: String
    var todoID: UUID?
    var planItemID: UUID? = nil
}

enum CompletionRecordOrigin: String, Equatable {
    case plan
    case quickFocus

    var title: String {
        switch self {
        case .plan: "来自计划"
        case .quickFocus: "快速专注"
        }
    }
}

enum CompletionRecordID: Hashable {
    case session(UUID)
    case planItem(UUID)
}

struct CompletionRecord: Identifiable, Equatable {
    let id: CompletionRecordID
    let sessionID: UUID?
    let planItemID: UUID?
    let title: String
    let minutes: Int?
    let completedAt: Date
    let origin: CompletionRecordOrigin
    let note: String
}

struct TodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var focusMinutes: Int
    var isCompleted: Bool
    var completedFocusCount: Int
    let createdAt: Date
    var restMinutes: Int? = nil
    var category: String? = nil
    var symbol: String? = nil

    var resolvedRestMinutes: Int { restMinutes ?? 5 }
    var resolvedCategory: String {
        let value = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "全部" : value
    }
    var resolvedSymbol: String { symbol ?? "checkmark.square" }
}

enum DailyPlanStatus: String, Codable, CaseIterable {
    case pending
    case running
    case completed
    case skipped
    case overdue

    var title: String {
        switch self {
        case .pending: "未开始"
        case .running: "进行中"
        case .completed: "已完成"
        case .skipped: "已跳过"
        case .overdue: "已逾期"
        }
    }
}

struct DailyPlanItem: Codable, Identifiable, Equatable {
    let id: UUID
    var templateID: UUID?
    var title: String
    var date: Date
    var reminderStartMinute: Int?
    var focusMinutes: Int
    var restMinutes: Int
    var order: Int
    var status: DailyPlanStatus
    var actualStartedAt: Date?
    var actualEndedAt: Date?
    var reminderLastTriggeredAt: Date?
    var reminderSnoozedUntil: Date?

    var reminderTimeText: String? {
        guard let reminderStartMinute else { return nil }
        return String(format: "%02d:%02d", reminderStartMinute / 60, reminderStartMinute % 60)
    }

    private enum CodingKeys: String, CodingKey {
        case id, templateID, title, date, reminderStartMinute, plannedStartMinute
        case focusMinutes, restMinutes, order, status, actualStartedAt, actualEndedAt
        case reminderLastTriggeredAt, reminderSnoozedUntil
    }

    init(
        id: UUID,
        templateID: UUID?,
        title: String,
        date: Date,
        reminderStartMinute: Int?,
        focusMinutes: Int,
        restMinutes: Int,
        order: Int,
        status: DailyPlanStatus,
        actualStartedAt: Date?,
        actualEndedAt: Date?,
        reminderLastTriggeredAt: Date? = nil,
        reminderSnoozedUntil: Date? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.date = date
        self.reminderStartMinute = reminderStartMinute
        self.focusMinutes = focusMinutes
        self.restMinutes = restMinutes
        self.order = order
        self.status = status == .overdue ? .pending : status
        self.actualStartedAt = actualStartedAt
        self.actualEndedAt = actualEndedAt
        self.reminderLastTriggeredAt = reminderLastTriggeredAt
        self.reminderSnoozedUntil = reminderSnoozedUntil
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        templateID = try values.decodeIfPresent(UUID.self, forKey: .templateID)
        title = try values.decode(String.self, forKey: .title)
        date = try values.decode(Date.self, forKey: .date)
        // 旧版 plannedStartMinute 是强制日程时间，不能悄悄升级为用户主动设置的提醒。
        reminderStartMinute = try values.decodeIfPresent(Int.self, forKey: .reminderStartMinute)
        focusMinutes = try values.decode(Int.self, forKey: .focusMinutes)
        restMinutes = try values.decode(Int.self, forKey: .restMinutes)
        order = try values.decode(Int.self, forKey: .order)
        let decodedStatus = try values.decode(DailyPlanStatus.self, forKey: .status)
        status = decodedStatus == .overdue ? .pending : decodedStatus
        actualStartedAt = try values.decodeIfPresent(Date.self, forKey: .actualStartedAt)
        actualEndedAt = try values.decodeIfPresent(Date.self, forKey: .actualEndedAt)
        reminderLastTriggeredAt = try values.decodeIfPresent(Date.self, forKey: .reminderLastTriggeredAt)
        reminderSnoozedUntil = try values.decodeIfPresent(Date.self, forKey: .reminderSnoozedUntil)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(templateID, forKey: .templateID)
        try values.encode(title, forKey: .title)
        try values.encode(date, forKey: .date)
        try values.encodeIfPresent(reminderStartMinute, forKey: .reminderStartMinute)
        try values.encode(focusMinutes, forKey: .focusMinutes)
        try values.encode(restMinutes, forKey: .restMinutes)
        try values.encode(order, forKey: .order)
        try values.encode(status, forKey: .status)
        try values.encodeIfPresent(actualStartedAt, forKey: .actualStartedAt)
        try values.encodeIfPresent(actualEndedAt, forKey: .actualEndedAt)
        try values.encodeIfPresent(reminderLastTriggeredAt, forKey: .reminderLastTriggeredAt)
        try values.encodeIfPresent(reminderSnoozedUntil, forKey: .reminderSnoozedUntil)
    }
}

enum CompletionRecordPolicy {
    static func records(
        sessions: [FocusSession],
        planItems: [DailyPlanItem],
        on date: Date,
        calendar: Calendar = .current
    ) -> [CompletionRecord] {
        let completedSessions = sessions.filter {
            $0.result == .done && calendar.isDate($0.endedAt, inSameDayAs: date)
        }
        let recordedPlanIDs = Set(
            sessions
                .filter { $0.result == .done }
                .compactMap(\.planItemID)
        )

        var records = completedSessions.map { session in
            CompletionRecord(
                id: .session(session.id),
                sessionID: session.id,
                planItemID: session.planItemID,
                title: session.task,
                minutes: session.minutes,
                completedAt: session.endedAt,
                origin: session.planItemID == nil ? .quickFocus : .plan,
                note: session.note
            )
        }

        records.append(contentsOf: planItems.compactMap { item in
            guard item.status == .completed,
                  !recordedPlanIDs.contains(item.id) else { return nil }
            let completedAt = item.actualEndedAt ?? item.date
            guard calendar.isDate(completedAt, inSameDayAs: date) else { return nil }
            return CompletionRecord(
                id: .planItem(item.id),
                sessionID: nil,
                planItemID: item.id,
                title: item.title,
                minutes: nil,
                completedAt: completedAt,
                origin: .plan,
                note: ""
            )
        })

        return records.sorted { $0.completedAt > $1.completedAt }
    }
}

enum TodayFocusRecordPolicy {
    static func records(
        sessions: [FocusSession],
        on date: Date,
        calendar: Calendar = .current
    ) -> [FocusSession] {
        sessions
            .filter { calendar.isDate($0.endedAt, inSameDayAs: date) }
            .sorted { $0.endedAt > $1.endedAt }
    }
}

struct TaskSet: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var templateIDs: [UUID]
    var createdAt: Date
}

enum ReminderPolicy: String, Codable, CaseIterable, Identifiable {
    case gentle
    case deferToBreak

    var id: String { rawValue }
    var title: String { self == .gentle ? "到点即提醒" : "专注结束后提醒" }
}

struct ReminderRule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var symbol: String
    var intervalMinutes: Int
    var isEnabled: Bool
    var policy: ReminderPolicy
    var activeStartMinute: Int
    var activeEndMinute: Int
    var nextFireAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, intervalMinutes, isEnabled, policy, activeStartMinute, activeEndMinute, nextFireAt
    }

    init(
        id: UUID,
        name: String,
        symbol: String,
        intervalMinutes: Int,
        isEnabled: Bool,
        policy: ReminderPolicy,
        activeStartMinute: Int = 9 * 60,
        activeEndMinute: Int = 22 * 60,
        nextFireAt: Date
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.intervalMinutes = intervalMinutes
        self.isEnabled = isEnabled
        self.policy = policy
        self.activeStartMinute = activeStartMinute
        self.activeEndMinute = activeEndMinute
        self.nextFireAt = nextFireAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        symbol = try values.decode(String.self, forKey: .symbol)
        intervalMinutes = try values.decode(Int.self, forKey: .intervalMinutes)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        policy = try values.decode(ReminderPolicy.self, forKey: .policy)
        activeStartMinute = try values.decodeIfPresent(Int.self, forKey: .activeStartMinute) ?? 9 * 60
        activeEndMinute = try values.decodeIfPresent(Int.self, forKey: .activeEndMinute) ?? 22 * 60
        nextFireAt = try values.decode(Date.self, forKey: .nextFireAt)
    }
}

struct ReminderEvent: Codable, Identifiable {
    let id: UUID
    let reminderName: String
    let date: Date
    let completed: Bool
}

enum FloatingLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case independent
    // Legacy saved value. New settings expose only independent and combinedBar.
    case compactCircles
    case combinedBar

    static var allCases: [FloatingLayoutStyle] { [.independent, .combinedBar] }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .independent: "各自独立"
        case .compactCircles: "合并控制条"
        case .combinedBar: "合并控制条"
        }
    }
}

enum TimerIconStyle: String, Codable, CaseIterable, Identifiable {
    case progressRing
    case tomato
    case hourglass
    case digital

    var id: String { rawValue }
    var title: String {
        switch self {
        case .progressRing: "进度圆环"
        case .tomato: "番茄"
        case .hourglass: "沙漏"
        case .digital: "纯数字"
        }
    }
    var previewSymbol: String {
        switch self {
        case .progressRing: "circle.dashed"
        case .tomato: "circle.fill"
        case .hourglass: "hourglass"
        case .digital: "textformat.123"
        }
    }
}

enum ReminderIconStyle: String, Codable, CaseIterable, Identifiable {
    case automatic
    case bell
    case water
    case breakCup
    case customEmoji

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "智能匹配"
        case .bell: "铃铛"
        case .water: "水滴"
        case .breakCup: "咖啡杯"
        case .customEmoji: "自定义"
        }
    }
    var previewSymbol: String {
        switch self {
        case .automatic: "wand.and.stars"
        case .bell: "bell.fill"
        case .water: "drop.fill"
        case .breakCup: "cup.and.saucer.fill"
        case .customEmoji: "face.smiling"
        }
    }
}

enum FloatingTint: String, Codable, CaseIterable, Identifiable {
    case purple
    case coral
    case green
    case blue
    case graphite

    var id: String { rawValue }
}

enum AlertSound: String, Codable, CaseIterable, Identifiable {
    case glass
    case ping
    case pop
    case hero
    case submarine

    var id: String { rawValue }
    var systemName: String {
        switch self {
        case .glass: "Glass"
        case .ping: "Ping"
        case .pop: "Pop"
        case .hero: "Hero"
        case .submarine: "Submarine"
        }
    }
    var title: String {
        switch self {
        case .glass: "玻璃清响"
        case .ping: "清脆一声"
        case .pop: "轻柔气泡"
        case .hero: "醒目提示"
        case .submarine: "低沉提示"
        }
    }
}

enum ReminderEmphasis: String, Codable, CaseIterable, Identifiable {
    case subtle
    case enlarge
    case bounce

    var id: String { rawValue }
    var title: String {
        switch self {
        case .subtle: "轻提示"
        case .enlarge: "放大提醒"
        case .bounce: "弹跳提醒"
        }
    }
}

enum PetSpecies: String, Codable, CaseIterable, Identifiable {
    case cat
    case dog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cat: "小猫咪"
        case .dog: "小狗狗"
        }
    }

    var previewSymbol: String {
        switch self {
        case .cat: "cat.fill"
        case .dog: "dog.fill"
        }
    }

    /// 资源目录名（对应 Bundle.module 中的 PetAssets/{dir}/）
    var assetDir: String {
        switch self {
        case .cat: "cat"
        case .dog: "dog"
        }
    }

    /// 全部 19 个姿态文件名（与 Resources/PetAssets/{species}/ 下的 PNG 对应）
    static let poseNames: [String] = [
        "idleStand",   // 01_standing
        "walk",        // 02_running
        "question",    // 03_question
        "think",       // 04_thinking_of_fish / thinking
        "partySit",    // 05_party_hat_sitting
        "sleep",       // 06_sleeping
        "wave",        // 07_waving
        "pillow",      // 08_pillow
        "yarn",        // 09_yarn_ball
        "partyStand",  // 10_party_hat_standing
        "clipboard",   // 11_clipboard
        "idle",        // 12_sitting
        "pen",         // 13_pen
        "folder",      // 14_folder
        "celebrate",   // 15_completed_sign
        "painter",     // 16_painter
        "drink",       // 17_drinking_water
        "eye",         // 18_eye_relaxation
        "stretch",     // 19_stretching
    ]

    /// 文件名 → 姿态 key 的映射（用于从文件名反查）
    static func poseKey(fromFileName name: String) -> String? {
        let map: [String: String] = [
            "01_standing": "idleStand",
            "02_running": "walk",
            "03_question": "question",
            "04_thinking_of_fish": "think",
            "04_thinking": "think",
            "05_party_hat_sitting": "partySit",
            "06_sleeping": "sleep",
            "07_waving": "wave",
            "08_pillow": "pillow",
            "09_yarn_ball": "yarn",
            "09_yarn": "yarn",
            "10_party_hat_standing": "partyStand",
            "11_clipboard": "clipboard",
            "12_sitting": "idle",
            "13_pen": "pen",
            "14_folder": "folder",
            "15_completed_sign": "celebrate",
            "15_completed": "celebrate",
            "16_painter": "painter",
            "17_drinking_water": "drink",
            "17_drinking": "drink",
            "18_eye_relaxation": "eye",
            "18_eye_relax": "eye",
            "19_stretching": "stretch",
        ]
        return map[name]
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "白天"
        case .dark: "黑夜"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var symbol: String {
        switch self {
        case .system: "gearshift"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var appearance = AppAppearance.system
    var focusMinutes = 45
    var restMinutes = 5
    var soundEnabled = true
    var notificationsEnabled = false
    var showTimerPanel = true
    var showReminderPanel = true
    var launchAtLogin = false
    var floatingLayout = FloatingLayoutStyle.independent
    var timerIconStyle = TimerIconStyle.progressRing
    var reminderIconStyle = ReminderIconStyle.automatic
    var floatingTint = FloatingTint.purple
    var customReminderEmoji = "🌱"
    var lockFloatingPosition = true
    var timerAlertSound = AlertSound.glass
    var reminderAlertSound = AlertSound.pop
    var reminderEmphasis = ReminderEmphasis.enlarge
    var obsidianVaultPath: String?
    var obsidianAutoSync = false
    var showPetPanel = false
    var petSpecies = PetSpecies.cat
    var petSize = 120

    /// 只开启番茄钟时，“合并”已经没有第二个内容可合并。
    /// 此时自动退化为独立番茄钟，避免在图标背后留下无意义的长条背景。
    var usesStandaloneTimerSurface: Bool {
        floatingLayout == .independent || !showReminderPanel
    }

    private enum CodingKeys: String, CodingKey {
        case appearance
        case focusMinutes, restMinutes, soundEnabled, notificationsEnabled
        case showTimerPanel, showReminderPanel, launchAtLogin
        case floatingLayout, timerIconStyle, reminderIconStyle, floatingTint, customReminderEmoji, lockFloatingPosition
        case timerAlertSound, reminderAlertSound, reminderEmphasis, obsidianVaultPath, obsidianAutoSync
        case showPetPanel, petSpecies, petSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        focusMinutes = try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 45
        restMinutes = try values.decodeIfPresent(Int.self, forKey: .restMinutes) ?? 5
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        showTimerPanel = try values.decodeIfPresent(Bool.self, forKey: .showTimerPanel) ?? true
        showReminderPanel = try values.decodeIfPresent(Bool.self, forKey: .showReminderPanel) ?? true
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        let decodedFloatingLayout = try values.decodeIfPresent(FloatingLayoutStyle.self, forKey: .floatingLayout) ?? .independent
        floatingLayout = decodedFloatingLayout == .compactCircles ? .combinedBar : decodedFloatingLayout
        timerIconStyle = try values.decodeIfPresent(TimerIconStyle.self, forKey: .timerIconStyle) ?? .progressRing
        reminderIconStyle = try values.decodeIfPresent(ReminderIconStyle.self, forKey: .reminderIconStyle) ?? .automatic
        floatingTint = try values.decodeIfPresent(FloatingTint.self, forKey: .floatingTint) ?? .purple
        customReminderEmoji = try values.decodeIfPresent(String.self, forKey: .customReminderEmoji) ?? "🌱"
        lockFloatingPosition = try values.decodeIfPresent(Bool.self, forKey: .lockFloatingPosition) ?? true
        timerAlertSound = try values.decodeIfPresent(AlertSound.self, forKey: .timerAlertSound) ?? .glass
        reminderAlertSound = try values.decodeIfPresent(AlertSound.self, forKey: .reminderAlertSound) ?? .pop
        reminderEmphasis = try values.decodeIfPresent(ReminderEmphasis.self, forKey: .reminderEmphasis) ?? .enlarge
        obsidianVaultPath = try values.decodeIfPresent(String.self, forKey: .obsidianVaultPath)
        obsidianAutoSync = try values.decodeIfPresent(Bool.self, forKey: .obsidianAutoSync) ?? false
        showPetPanel = try values.decodeIfPresent(Bool.self, forKey: .showPetPanel) ?? false
        // 先按字符串读取，避免旧版 tomato/chick/custom* 因枚举值失效而让整个 AppState 解码失败。
        let rawSpecies = try values.decodeIfPresent(String.self, forKey: .petSpecies)
        petSpecies = rawSpecies.flatMap(PetSpecies.init(rawValue:)) ?? .cat
        petSize = min(220, max(88, try values.decodeIfPresent(Int.self, forKey: .petSize) ?? 120))
        // 旧字段 customPetEmoji / customPetImagePath 不在 CodingKeys 中，Codable 自动忽略（不报错）
    }
}

struct PersistedTimer: Codable {
    var phase: TimerPhase
    var mode: TimerMode
    var timerTitle: String? = nil
    var task: String
    var durationSeconds: TimeInterval
    var displayedSeconds: TimeInterval
    var targetDate: Date?
    var countupReferenceDate: Date?
    var sessionStartedAt: Date?
    var activeTodoID: UUID?
    var activePlanItemID: UUID? = nil
}

struct PersistedAppState: Codable {
    var settings: AppSettings
    var reminders: [ReminderRule]
    var sessions: [FocusSession]
    var reminderEvents: [ReminderEvent]
    var todos: [TodoItem]?
    var taskSets: [TaskSet]? = nil
    var dailyPlanItems: [DailyPlanItem]? = nil
    var timer: PersistedTimer
}
