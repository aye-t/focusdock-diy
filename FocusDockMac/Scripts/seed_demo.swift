import Foundation

@main
enum FocusDockDemoSeeder {
    static func main() throws {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        func session(_ task: String, daysAgo: Int, hour: Int, minute: Int, duration: Int, result: SessionResult = .done) -> FocusSession {
            let start = date(daysAgo: daysAgo, hour: hour, minute: minute)
            return FocusSession(
                id: UUID(),
                task: task,
                startedAt: start,
                endedAt: start.addingTimeInterval(TimeInterval(duration * 60)),
                minutes: duration,
                result: result,
                note: "",
                todoID: nil
            )
        }

        func reminderEvent(_ name: String, daysAgo: Int, hour: Int, minute: Int, completed: Bool) -> ReminderEvent {
            ReminderEvent(
                id: UUID(),
                reminderName: name,
                date: date(daysAgo: daysAgo, hour: hour, minute: minute),
                completed: completed
            )
        }

        var settings = AppSettings()
        settings.focusMinutes = 25
        settings.restMinutes = 5
        settings.notificationsEnabled = false
        settings.showTimerPanel = true
        settings.showReminderPanel = true
        settings.floatingLayout = CommandLine.arguments.contains("--independent") ? .independent : .combinedBar
        settings.timerIconStyle = .tomato
        settings.reminderIconStyle = .automatic
        settings.floatingTint = .purple
        settings.lockFloatingPosition = false
        settings.obsidianVaultPath = nil
        settings.obsidianAutoSync = false

        let reminders = [
            ReminderRule(
                id: UUID(), name: "喝水", symbol: "drop.fill", intervalMinutes: 40,
                isEnabled: true, policy: .deferToBreak, activeStartMinute: 8 * 60,
                activeEndMinute: 22 * 60, nextFireAt: now.addingTimeInterval(12 * 60)
            ),
            ReminderRule(
                id: UUID(), name: "站起来活动", symbol: "figure.stand", intervalMinutes: 60,
                isEnabled: true, policy: .deferToBreak, activeStartMinute: 9 * 60,
                activeEndMinute: 21 * 60, nextFireAt: now.addingTimeInterval(18 * 60)
            ),
            ReminderRule(
                id: UUID(), name: "远眺 20 秒", symbol: "eye.fill", intervalMinutes: 20,
                isEnabled: true, policy: .gentle, activeStartMinute: 8 * 60 + 30,
                activeEndMinute: 22 * 60, nextFireAt: now.addingTimeInterval(6 * 60)
            )
        ]

        let sessions = [
            session("整理产品方案", daysAgo: 0, hour: 9, minute: 20, duration: 25),
            session("阅读行业资料", daysAgo: 0, hour: 10, minute: 15, duration: 35),
            session("撰写项目周报", daysAgo: 0, hour: 14, minute: 10, duration: 25),
            session("整理产品方案", daysAgo: 1, hour: 9, minute: 30, duration: 50),
            session("制作演示页面", daysAgo: 1, hour: 15, minute: 0, duration: 40),
            session("阅读行业资料", daysAgo: 2, hour: 10, minute: 0, duration: 45),
            session("梳理用户反馈", daysAgo: 3, hour: 14, minute: 20, duration: 60),
            session("撰写项目周报", daysAgo: 4, hour: 9, minute: 10, duration: 30),
            session("制作演示页面", daysAgo: 5, hour: 16, minute: 0, duration: 50)
        ]

        let reminderEvents = [
            reminderEvent("喝水", daysAgo: 0, hour: 9, minute: 40, completed: true),
            reminderEvent("远眺 20 秒", daysAgo: 0, hour: 10, minute: 0, completed: true),
            reminderEvent("站起来活动", daysAgo: 0, hour: 11, minute: 0, completed: false),
            reminderEvent("喝水", daysAgo: 0, hour: 11, minute: 20, completed: true),
            reminderEvent("远眺 20 秒", daysAgo: 0, hour: 14, minute: 40, completed: false),
            reminderEvent("喝水", daysAgo: 1, hour: 10, minute: 20, completed: true),
            reminderEvent("站起来活动", daysAgo: 1, hour: 11, minute: 0, completed: true),
            reminderEvent("远眺 20 秒", daysAgo: 2, hour: 10, minute: 40, completed: true)
        ]

        let todos = [
            TodoItem(id: UUID(), title: "完善产品介绍", focusMinutes: 25, isCompleted: false, completedFocusCount: 1, createdAt: date(daysAgo: 0, hour: 8, minute: 50)),
            TodoItem(id: UUID(), title: "整理功能截图", focusMinutes: 25, isCompleted: false, completedFocusCount: 0, createdAt: date(daysAgo: 0, hour: 9, minute: 0)),
            TodoItem(id: UUID(), title: "检查提醒体验", focusMinutes: 20, isCompleted: true, completedFocusCount: 2, createdAt: date(daysAgo: 1, hour: 9, minute: 0))
        ]

        let state = PersistedAppState(
            settings: settings,
            reminders: reminders,
            sessions: sessions,
            reminderEvents: reminderEvents,
            todos: todos,
            timer: PersistedTimer(
                phase: .idle,
                mode: .countdown,
                task: "完善产品介绍",
                durationSeconds: 25 * 60,
                displayedSeconds: 25 * 60,
                targetDate: nil,
                countupReferenceDate: nil,
                sessionStartedAt: nil,
                activeTodoID: nil
            )
        )

        let data = try JSONEncoder().encode(state)
        guard let defaults = UserDefaults(suiteName: "com.focusdock.mac.demo") else {
            throw NSError(domain: "FocusDockDemoSeeder", code: 1)
        }
        defaults.set(data, forKey: "FocusDock.AppState.v1")
        defaults.synchronize()
        print("Seeded FocusDock demo data")
    }
}
