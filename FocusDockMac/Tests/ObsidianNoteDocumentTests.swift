import Testing
@testable import FocusDockMac

@Suite("Obsidian daily note rendering")
struct ObsidianNoteDocumentTests {
    private let properties = ObsidianDailyProperties(
        date: "2026-07-25",
        focusMinutes: 178,
        focusSessions: 10,
        completedSessions: 8,
        progressSessions: 1,
        abandonedSessions: 1,
        reminderDone: 50,
        reminderTotal: 52,
        plannedTasks: 4,
        completedPlanTasks: 2
    )

    @Test("Refreshes metrics and moves a legacy review outside the managed block")
    func refreshesLegacyNote() {
        let existing = """
        ---
        type: focusdock-daily
        date: 2026-07-25
        tags: [focusdock, custom]
        focus_minutes: 0
        focus_sessions: 0
        ---

        # Existing title

        <!-- focusdock:start -->
        ## 今日节奏
        old data

        ## 手写复盘

        - 今天最有效的节奏：上午写论文
        - 明天要避开的打断：
        - 下一步：继续实验

        <!-- focusdock:end -->
        """

        let output = ObsidianNoteDocument.render(
            existing: existing,
            displayTitle: "2026年7月25日",
            managedLines: ["## 今日节奏", "", "new data"],
            properties: properties
        )

        #expect(output.contains("focus_minutes: 178"))
        #expect(output.contains("completed_sessions: 8"))
        #expect(output.contains("focusdock_schema: 3"))
        #expect(output.contains("planned_tasks: 4"))
        #expect(output.contains("completed_plan_tasks: 2"))
        #expect(output.contains("tags: [focusdock, custom, daily-note, productivity]"))
        #expect(output.contains("<!-- focusdock:end -->\n\n## 手写复盘"))
        #expect(output.contains("上午写论文"))
        #expect(output.components(separatedBy: "## 手写复盘").count == 2)
    }

    @Test("Preserves an existing review and custom properties on repeated sync")
    func repeatedSyncIsSafe() {
        let first = ObsidianNoteDocument.render(
            existing: "",
            displayTitle: "2026年7月25日",
            managedLines: ["## 今日节奏", "", "first"],
            properties: properties
        )
        let edited = first
            .replacingOccurrences(of: "source: FocusDock", with: "source: FocusDock\nproject: thesis")
            .replacingOccurrences(of: "- 下一步：", with: "- 下一步：完成实验")
        let second = ObsidianNoteDocument.render(
            existing: edited,
            displayTitle: "2026年7月25日",
            managedLines: ["## 今日节奏", "", "second"],
            properties: properties
        )

        #expect(second.contains("project: thesis"))
        #expect(second.contains("- 下一步：完成实验"))
        #expect(!second.contains("first"))
        #expect(second.contains("second"))
        #expect(second.components(separatedBy: "## 手写复盘").count == 2)
    }
}
