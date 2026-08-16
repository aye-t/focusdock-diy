import Foundation
import Testing
@testable import FocusDockMac

@Suite("Daily plan model")
struct DailyPlanModelTests {
    @Test("Live standalone focus overrides an idle plan preview")
    func resolvesStandaloneTimerPresentation() throws {
        let presentation = try #require(
            ActiveTimerPresentationPolicy.resolve(
                phase: .focusRunning,
                timeText: "24:44",
                taskTitle: "英语",
                activePlanItemID: nil
            )
        )

        #expect(presentation.source == .standalone)
        #expect(presentation.title == "英语")
        #expect(presentation.timeText == "24:44")
    }

    @Test("A daily plan is only the source of the same live timer")
    func resolvesPlanTimerPresentation() throws {
        let planID = UUID()
        let presentation = try #require(
            ActiveTimerPresentationPolicy.resolve(
                phase: .focusPaused,
                timeText: "18:09",
                taskTitle: "论文 · 第 2 轮",
                activePlanItemID: planID
            )
        )

        #expect(presentation.source == .dailyPlan(planID))
        #expect(presentation.title == "论文 · 第 2 轮")
        #expect(presentation.timeText == "18:09")
    }

    @Test("An idle timer does not override the next-plan preview")
    func hidesInactiveTimerPresentation() {
        #expect(
            ActiveTimerPresentationPolicy.resolve(
                phase: .idle,
                timeText: "25:00",
                taskTitle: "英语",
                activePlanItemID: nil
            ) == nil
        )
    }

    @Test("Rest replaces the task label but keeps the same remaining time")
    func resolvesRestTimerPresentation() throws {
        let presentation = try #require(
            ActiveTimerPresentationPolicy.resolve(
                phase: .restRunning,
                timeText: "04:12",
                taskTitle: "英语",
                activePlanItemID: nil
            )
        )

        #expect(presentation.title == "休息")
        #expect(presentation.timeText == "04:12")
    }

    @Test("Completed history follows the completion date and identifies quick focus")
    func buildsQuickCompletionRecord() throws {
        let formatter = ISO8601DateFormatter()
        let startedAt = try #require(formatter.date(from: "2026-07-30T23:55:00Z"))
        let endedAt = try #require(formatter.date(from: "2026-07-31T00:20:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let session = FocusSession(
            id: UUID(),
            task: "英语",
            startedAt: startedAt,
            endedAt: endedAt,
            minutes: 25,
            result: .done,
            note: "",
            todoID: nil,
            planItemID: nil
        )

        let records = CompletionRecordPolicy.records(
            sessions: [session],
            planItems: [],
            on: endedAt,
            calendar: calendar
        )

        #expect(records.count == 1)
        #expect(records[0].origin == .quickFocus)
        #expect(records[0].minutes == 25)
    }

    @Test("A timed plan completion is not duplicated by its plan item")
    func deduplicatesTimedPlanCompletion() throws {
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let planID = UUID()
        let plan = DailyPlanItem(
            id: planID,
            templateID: UUID(),
            title: "论文",
            date: completedAt,
            reminderStartMinute: nil,
            focusMinutes: 50,
            restMinutes: 5,
            order: 0,
            status: .completed,
            actualStartedAt: completedAt.addingTimeInterval(-3_000),
            actualEndedAt: completedAt
        )
        let session = FocusSession(
            id: UUID(),
            task: "论文",
            startedAt: completedAt.addingTimeInterval(-3_000),
            endedAt: completedAt,
            minutes: 50,
            result: .done,
            note: "",
            todoID: plan.templateID,
            planItemID: planID
        )

        let records = CompletionRecordPolicy.records(
            sessions: [session],
            planItems: [plan],
            on: completedAt
        )

        #expect(records.count == 1)
        #expect(records[0].origin == .plan)
        #expect(records[0].sessionID == session.id)
    }

    @Test("A manually completed plan remains visible without inventing focus minutes")
    func buildsManualPlanCompletionRecord() {
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = DailyPlanItem(
            id: UUID(),
            templateID: nil,
            title: "整理资料",
            date: completedAt,
            reminderStartMinute: nil,
            focusMinutes: 30,
            restMinutes: 5,
            order: 0,
            status: .completed,
            actualStartedAt: nil,
            actualEndedAt: completedAt
        )

        let records = CompletionRecordPolicy.records(
            sessions: [],
            planItems: [plan],
            on: completedAt
        )

        #expect(records.count == 1)
        #expect(records[0].origin == .plan)
        #expect(records[0].minutes == nil)
    }

    @Test("Today's focus records include every ending result and use end-time order")
    func buildsTodayFocusRecords() throws {
        let formatter = ISO8601DateFormatter()
        let day = try #require(formatter.date(from: "2026-08-04T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        func session(_ result: SessionResult, endedAt: String) throws -> FocusSession {
            let end = try #require(formatter.date(from: endedAt))
            return FocusSession(
                id: UUID(),
                task: result.title,
                startedAt: end.addingTimeInterval(-900),
                endedAt: end,
                minutes: 15,
                result: result,
                note: "",
                todoID: nil,
                planItemID: nil
            )
        }

        let records = TodayFocusRecordPolicy.records(
            sessions: [
                try session(.done, endedAt: "2026-08-04T10:30:00Z"),
                try session(.progress, endedAt: "2026-08-04T20:13:00Z"),
                try session(.interrupted, endedAt: "2026-08-04T16:40:00Z"),
                try session(.abandoned, endedAt: "2026-08-04T20:55:00Z"),
                try session(.done, endedAt: "2026-08-03T23:59:00Z")
            ],
            on: day,
            calendar: calendar
        )

        #expect(records.map(\.result) == [.abandoned, .progress, .interrupted, .done])
    }

    @Test("Decodes a V1 todo as a reusable V2 task template")
    func decodesLegacyTodo() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "id": id.uuidString,
            "title": "阅读论文",
            "focusMinutes": 50,
            "isCompleted": true,
            "completedFocusCount": 3,
            "createdAt": createdAt.timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        let task = try decoder.decode(TodoItem.self, from: data)

        #expect(task.id == id)
        #expect(task.title == "阅读论文")
        #expect(task.resolvedRestMinutes == 5)
        #expect(task.resolvedCategory == "全部")
    }

    @Test("Keeps stable template and plan identifiers through persistence")
    func planRoundTrip() throws {
        let templateID = UUID()
        let item = DailyPlanItem(
            id: UUID(),
            templateID: templateID,
            title: "修改简历",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            reminderStartMinute: 9 * 60,
            focusMinutes: 45,
            restMinutes: 5,
            order: 0,
            status: .pending,
            actualStartedAt: nil,
            actualEndedAt: nil
        )

        let copy = try JSONDecoder().decode(
            DailyPlanItem.self,
            from: JSONEncoder().encode(item)
        )
        #expect(copy == item)
        #expect(copy.templateID == templateID)
    }

    @Test("Migrates the old mandatory schedule without creating overdue reminders")
    func migratesLegacySchedule() throws {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "title": "论文",
            "date": Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSinceReferenceDate,
            "plannedStartMinute": 8 * 60,
            "focusMinutes": 50,
            "restMinutes": 5,
            "order": 0,
            "status": "overdue"
        ]
        let item = try JSONDecoder().decode(
            DailyPlanItem.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        #expect(item.reminderStartMinute == nil)
        #expect(item.status == .pending)
    }
}
