import Foundation

struct ObsidianDailyProperties {
    let date: String
    let focusMinutes: Int
    let focusSessions: Int
    let completedSessions: Int
    let progressSessions: Int
    let abandonedSessions: Int
    let reminderDone: Int
    let reminderTotal: Int
    var plannedTasks: Int = 0
    var completedPlanTasks: Int = 0

    var orderedValues: [(key: String, value: String)] {
        [
            ("type", "focusdock-daily"),
            ("title", "FocusDock · \(date)"),
            ("date", date),
            ("source", "FocusDock"),
            ("focusdock_schema", "3"),
            ("focus_minutes", String(focusMinutes)),
            ("focus_sessions", String(focusSessions)),
            ("completed_sessions", String(completedSessions)),
            ("progress_sessions", String(progressSessions)),
            ("abandoned_sessions", String(abandonedSessions)),
            ("reminder_done", String(reminderDone)),
            ("reminder_total", String(reminderTotal)),
            ("planned_tasks", String(plannedTasks)),
            ("completed_plan_tasks", String(completedPlanTasks))
        ]
    }
}

enum ObsidianNoteDocument {
    static let startMarker = "<!-- focusdock:start -->"
    static let endMarker = "<!-- focusdock:end -->"
    static let reviewHeader = "## 手写复盘"

    static let defaultReview = """
    ## 手写复盘

    - 今天最有效的节奏：
    - 明天要避开的打断：
    - 下一步：
    """

    static func render(
        existing: String,
        displayTitle: String,
        managedLines: [String],
        properties: ObsidianDailyProperties
    ) -> String {
        let managedBlock = ([startMarker] + managedLines + [endMarker]).joined(separator: "\n")
        let legacyReview = reviewInsideManagedBlock(in: existing)
        var body: String

        if let managedRange = markerRange(in: existing) {
            body = existing
            body.replaceSubrange(managedRange, with: managedBlock)
            if !containsReviewOutsideManagedBlock(in: body) {
                body = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    + "\n\n"
                    + (legacyReview ?? defaultReview)
                    + "\n"
            }
        } else if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = "# FocusDock · \(displayTitle)\n\n\(managedBlock)\n\n\(defaultReview)\n"
        } else {
            body = existing.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n\n\(managedBlock)\n\n\(defaultReview)\n"
        }

        return upsertingFrontmatter(in: body, properties: properties)
    }

    private static func markerRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: startMarker),
              let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return start.lowerBound..<end.upperBound
    }

    private static func reviewInsideManagedBlock(in text: String) -> String? {
        guard let managedRange = markerRange(in: text) else { return nil }
        let managed = String(text[managedRange])
        guard let header = managed.range(of: reviewHeader) else { return nil }
        let review = String(managed[header.lowerBound...])
            .replacingOccurrences(of: endMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return review.isEmpty ? nil : review
    }

    private static func containsReviewOutsideManagedBlock(in text: String) -> Bool {
        guard let managedRange = markerRange(in: text) else {
            return text.contains(reviewHeader)
        }
        var outside = text
        outside.removeSubrange(managedRange)
        return outside.contains(reviewHeader)
    }

    private static func upsertingFrontmatter(
        in text: String,
        properties: ObsidianDailyProperties
    ) -> String {
        var lines = text.components(separatedBy: "\n")
        let hasFrontmatter = lines.first == "---"
        let closingIndex = hasFrontmatter
            ? lines.dropFirst().firstIndex(of: "---")
            : nil

        if let closingIndex {
            for property in properties.orderedValues {
                if let index = lines[1..<closingIndex].firstIndex(where: {
                    frontmatterKey(in: $0) == property.key
                }) {
                    lines[index] = "\(property.key): \(property.value)"
                } else {
                    lines.insert("\(property.key): \(property.value)", at: closingIndex)
                }
            }
            ensureCanonicalTags(in: &lines)
            return normalizedDocument(lines.joined(separator: "\n"))
        }

        let frontmatter = [
            "---",
            "type: focusdock-daily",
            "title: FocusDock · \(properties.date)",
            "date: \(properties.date)",
            "tags: [focusdock, daily-note, productivity]",
            "source: FocusDock",
            "focusdock_schema: 3",
            "focus_minutes: \(properties.focusMinutes)",
            "focus_sessions: \(properties.focusSessions)",
            "completed_sessions: \(properties.completedSessions)",
            "progress_sessions: \(properties.progressSessions)",
            "abandoned_sessions: \(properties.abandonedSessions)",
            "reminder_done: \(properties.reminderDone)",
            "reminder_total: \(properties.reminderTotal)",
            "planned_tasks: \(properties.plannedTasks)",
            "completed_plan_tasks: \(properties.completedPlanTasks)",
            "---",
            ""
        ]
        return normalizedDocument((frontmatter + lines).joined(separator: "\n"))
    }

    private static func frontmatterKey(in line: String) -> String? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"),
              let colon = line.firstIndex(of: ":") else {
            return nil
        }
        return String(line[..<colon]).trimmingCharacters(in: .whitespaces)
    }

    private static func ensureCanonicalTags(in lines: inout [String]) {
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else { return }
        if let tagIndex = lines[1..<closingIndex].firstIndex(where: {
            frontmatterKey(in: $0) == "tags"
        }), lines[tagIndex].contains("[") {
            let requiredTags = ["focusdock", "daily-note", "productivity"]
            var values = lines[tagIndex]
                .replacingOccurrences(of: "tags:", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for tag in requiredTags where !values.contains(tag) {
                values.append(tag)
            }
            lines[tagIndex] = "tags: [\(values.joined(separator: ", "))]"
        } else if !lines[1..<closingIndex].contains(where: {
            frontmatterKey(in: $0) == "tags"
        }) {
            lines.insert("tags: [focusdock, daily-note, productivity]", at: closingIndex)
        }
    }

    private static func normalizedDocument(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
