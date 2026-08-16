#!/usr/bin/env swift

import Foundation

let suiteName = "com.focusdock.mac"
let storageKey = "FocusDock.AppState.v2"
let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: restore_from_obsidian.swift <FocusDock notes directory>\n", stderr)
    exit(2)
}

let notesDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
let dailyFiles = try fileManager.contentsOfDirectory(
    at: notesDirectory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)
.filter { $0.pathExtension == "md" && $0.deletingPathExtension().lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

guard let defaults = UserDefaults(suiteName: suiteName),
      let currentData = defaults.data(forKey: storageKey),
      var state = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
    fputs("Could not read the current FocusDock state.\n", stderr)
    exit(1)
}

let sessionPattern = try NSRegularExpression(
    pattern: #"^\|\s*([0-9]{1,2}:[0-9]{2})\s*\|\s*(.*?)\s*\|\s*([0-9]+)\s*分钟\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|$"#
)
let reminderPattern = try NSRegularExpression(
    pattern: #"^-\s*\[([ xX])\]\s*([0-9]{1,2}):([0-9]{2})\s*·\s*(.+?)\s*$"#
)

let resultMap = [
    "已完成": "done",
    "有一些进展": "progress",
    "被打断了": "interrupted",
    "已放弃": "abandoned",
]

let dateFormatter = DateFormatter()
dateFormatter.calendar = Calendar(identifier: .gregorian)
dateFormatter.locale = Locale(identifier: "en_US_POSIX")
dateFormatter.timeZone = TimeZone.current
dateFormatter.dateFormat = "yyyy-MM-dd H:mm"

func capture(_ match: NSTextCheckingResult, _ index: Int, in line: String) -> String {
    let range = match.range(at: index)
    guard let swiftRange = Range(range, in: line) else { return "" }
    return String(line[swiftRange]).trimmingCharacters(in: .whitespaces)
}

var recoveredSessions: [[String: Any]] = []
var recoveredReminderEvents: [[String: Any]] = []

for file in dailyFiles {
    let day = file.deletingPathExtension().lastPathComponent
    let text = try String(contentsOf: file, encoding: .utf8)
    for line in text.components(separatedBy: .newlines) {
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)

        if let match = sessionPattern.firstMatch(in: line, range: fullRange) {
            let time = capture(match, 1, in: line)
            let task = capture(match, 2, in: line)
            let minutes = Int(capture(match, 3, in: line)) ?? 0
            let displayedResult = capture(match, 4, in: line)
            let note = capture(match, 5, in: line)
            guard minutes > 0,
                  let startedAt = dateFormatter.date(from: "\(day) \(time)"),
                  let result = resultMap[displayedResult] else { continue }

            recoveredSessions.append([
                "id": UUID().uuidString,
                "task": task,
                "startedAt": startedAt.timeIntervalSince(referenceDate),
                "endedAt": startedAt.addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSince(referenceDate),
                "minutes": minutes,
                "result": result,
                "note": note,
            ])
            continue
        }

        if let match = reminderPattern.firstMatch(in: line, range: fullRange) {
            let completed = capture(match, 1, in: line).lowercased() == "x"
            let hour = capture(match, 2, in: line)
            let minute = capture(match, 3, in: line)
            let name = capture(match, 4, in: line)
            guard let date = dateFormatter.date(from: "\(day) \(hour):\(minute)") else { continue }

            recoveredReminderEvents.append([
                "id": UUID().uuidString,
                "reminderName": name,
                "date": date.timeIntervalSince(referenceDate),
                "completed": completed,
            ])
        }
    }
}

func sessionSignature(_ session: [String: Any]) -> String {
    let startedAt = session["startedAt"] as? Double ?? 0
    let minuteBucket = Int(startedAt / 60)
    return [
        String(minuteBucket),
        session["task"] as? String ?? "",
        String(session["minutes"] as? Int ?? 0),
        session["result"] as? String ?? "",
    ].joined(separator: "|")
}

func reminderSignature(_ event: [String: Any]) -> String {
    let date = event["date"] as? Double ?? 0
    let minuteBucket = Int(date / 60)
    return [
        String(minuteBucket),
        event["reminderName"] as? String ?? "",
        String(event["completed"] as? Bool ?? false),
    ].joined(separator: "|")
}

let existingSessions = state["sessions"] as? [[String: Any]] ?? []
var sessionSignatures = Set(recoveredSessions.map(sessionSignature))
let uniqueExistingSessions = existingSessions.filter { sessionSignatures.insert(sessionSignature($0)).inserted }
state["sessions"] = (recoveredSessions + uniqueExistingSessions).sorted {
    ($0["startedAt"] as? Double ?? 0) > ($1["startedAt"] as? Double ?? 0)
}

let existingReminderEvents = state["reminderEvents"] as? [[String: Any]] ?? []
var reminderSignatures = Set(recoveredReminderEvents.map(reminderSignature))
let uniqueExistingReminderEvents = existingReminderEvents.filter {
    reminderSignatures.insert(reminderSignature($0)).inserted
}
state["reminderEvents"] = (recoveredReminderEvents + uniqueExistingReminderEvents).sorted {
    ($0["date"] as? Double ?? 0) > ($1["date"] as? Double ?? 0)
}

let todoDefinitions: [(String, Int, Int)] = [
    ("论文", 50, 1),
    ("英语", 25, 2),
    ("运动", 5, 2),
    ("阅读", 25, 2),
    ("学习", 25, 2),
]
let todoCreatedAt = dateFormatter.date(from: "2026-07-20 00:00")!.timeIntervalSince(referenceDate)
let recoveredTodos: [[String: Any]] = todoDefinitions.map { title, focusMinutes, completedFocusCount in
    [
        "id": UUID().uuidString,
        "title": title,
        "focusMinutes": focusMinutes,
        "isCompleted": true,
        "completedFocusCount": completedFocusCount,
        "createdAt": todoCreatedAt,
    ]
}
let existingTodos = state["todos"] as? [[String: Any]] ?? []
let recoveredTodoTitles = Set(recoveredTodos.compactMap { $0["title"] as? String })
state["todos"] = recoveredTodos + existingTodos.filter {
    guard let title = $0["title"] as? String else { return true }
    return !recoveredTodoTitles.contains(title)
}

let restoredData = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
defaults.set(restoredData, forKey: storageKey)
guard defaults.synchronize() else {
    fputs("Failed to synchronize the restored FocusDock state.\n", stderr)
    exit(1)
}

let sessionCount = (state["sessions"] as? [[String: Any]])?.count ?? 0
let reminderCount = (state["reminderEvents"] as? [[String: Any]])?.count ?? 0
let todoCount = (state["todos"] as? [[String: Any]])?.count ?? 0
print("Restored \(sessionCount) sessions, \(reminderCount) reminder events, and \(todoCount) todos.")
