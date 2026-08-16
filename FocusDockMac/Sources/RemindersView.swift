import SwiftUI

struct RemindersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddReminder = false

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("提醒").font(.system(size: 22, weight: .semibold))
                }
                Spacer()
                Button { showAddReminder = true } label: { Label("新建提醒", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.reminders) { reminder in
                        ReminderCard(rule: reminder)
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(Color.fdGreen)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("提醒合并").font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    Button("预览") { model.previewReminders() }.buttonStyle(SecondaryButtonStyle())
                }
                .panel(padding: 16)
                .padding(.top, 14)
            }
        }
        .padding(28)
        .sheet(isPresented: $showAddReminder) {
            AddReminderSheet().environmentObject(model)
        }
    }
}

private struct ReminderCard: View {
    @EnvironmentObject private var model: AppModel
    let rule: ReminderRule

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: rule.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.fdPurple)
                    .frame(width: 38, height: 38)
                    .background(Color.fdPurpleSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { _ in model.toggleReminder(rule.id) }))
                    .labelsHidden().toggleStyle(.switch).tint(Color.fdPurple)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name).font(.system(size: 14, weight: .semibold))
                Text("每 \(rule.intervalMinutes) 分钟").font(.system(size: 10)).foregroundStyle(Color.fdMuted)
                Text("生效 \(minuteText(rule.activeStartMinute)) - \(minuteText(rule.activeEndMinute))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.fdMuted)
            }
            Divider().overlay(Color.fdLine)
            HStack {
                Text(rule.policy.title).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.fdPurple)
                    .padding(.horizontal, 8).padding(.vertical, 5).background(Color.fdPurpleSoft).clipShape(Capsule())
                Spacer()
                Text(rule.isEnabled ? "\(minutesUntil(rule.nextFireAt)) 分钟后" : "已关闭")
                    .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            }
            HStack {
                Menu("提醒方式") {
                    Button("到点即提醒") { updatePolicy(.gentle) }
                    Button("专注结束后提醒") { updatePolicy(.deferToBreak) }
                }
                .font(.system(size: 9))
                Spacer()
                Button(role: .destructive) { model.deleteReminder(rule.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Color.fdMuted)
            }
            VStack(alignment: .leading, spacing: 10) {
                IntervalField(minutes: intervalBinding)
                HStack(spacing: 12) {
                    TimeField(title: "开始", minute: startBinding)
                    TimeField(title: "结束", minute: endBinding)
                    Spacer(minLength: 0)
                }
            }
        }
        .panel(padding: 18)
        .opacity(rule.isEnabled ? 1 : 0.62)
    }

    private var startBinding: Binding<Int> {
        Binding(
            get: { rule.activeStartMinute },
            set: { value in
                var copy = rule
                copy.activeStartMinute = min(value, copy.activeEndMinute - 1)
                model.updateReminder(copy)
            }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { rule.intervalMinutes },
            set: { value in
                var copy = rule
                copy.intervalMinutes = min(240, max(1, value))
                model.updateReminder(copy)
            }
        )
    }

    private var endBinding: Binding<Int> {
        Binding(
            get: { rule.activeEndMinute },
            set: { value in
                var copy = rule
                copy.activeEndMinute = max(value, copy.activeStartMinute + 1)
                model.updateReminder(copy)
            }
        )
    }

    private func updatePolicy(_ policy: ReminderPolicy) {
        var copy = rule
        copy.policy = policy
        model.updateReminder(copy)
    }

    private func minuteText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func minutesUntil(_ date: Date) -> Int {
        max(1, Int(ceil(date.timeIntervalSince(model.now) / 60)))
    }
}

private struct AddReminderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var interval = 45
    @State private var policy: ReminderPolicy = .deferToBreak
    @State private var activeStartMinute = 9 * 60
    @State private var activeEndMinute = 22 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建提醒").font(.system(size: 20, weight: .semibold))
            TextField("提醒名称", text: $name).textFieldStyle(.roundedBorder)
            IntervalField(minutes: $interval)
            VStack(alignment: .leading, spacing: 8) {
                Text("生效时间段").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.fdMuted)
                HStack(spacing: 12) {
                    TimeField(title: "开始", minute: startBinding)
                    TimeField(title: "结束", minute: endBinding)
                }
            }
            Picker("提醒方式", selection: $policy) {
                ForEach(ReminderPolicy.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("保存") {
                    model.addReminder(
                        name: name,
                        interval: interval,
                        policy: policy,
                        activeStartMinute: min(activeStartMinute, activeEndMinute - 1),
                        activeEndMinute: max(activeEndMinute, activeStartMinute + 1)
                    )
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(26)
        .frame(width: 420)
    }

    private func minuteText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private var startBinding: Binding<Int> {
        Binding(
            get: { activeStartMinute },
            set: { activeStartMinute = min($0, activeEndMinute - 1) }
        )
    }

    private var endBinding: Binding<Int> {
        Binding(
            get: { activeEndMinute },
            set: { activeEndMinute = max($0, activeStartMinute + 1) }
        )
    }
}

private struct TimeField: View {
    let title: String
    @Binding var minute: Int
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.fdMuted)
                .frame(width: 24, alignment: .leading)
            Button { adjust(-15) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(TimeAdjustButtonStyle())
            TextField("09:00", text: $text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .frame(width: 52, height: 26)
                .background(Color.fdBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
                .onSubmit { commit() }
                .onAppear { text = minuteText(minute) }
                .onChange(of: minute) { _, value in
                    let formatted = minuteText(value)
                    if text != formatted { text = formatted }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            Button { adjust(15) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(TimeAdjustButtonStyle())
        }
    }

    private func commit() {
        guard let parsed = parseMinute(text) else {
            text = minuteText(minute)
            return
        }
        minute = parsed
        text = minuteText(parsed)
    }

    private func adjust(_ delta: Int) {
        commit()
        let next = min(23 * 60 + 59, max(0, minute + delta))
        minute = next
        text = minuteText(next)
    }

    private func parseMinute(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: "：", with: ":")
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private func minuteText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private struct IntervalField: View {
    @Binding var minutes: Int
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text("每")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.fdMuted)
                .frame(width: 24, alignment: .leading)
            Button { adjust(-5) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(TimeAdjustButtonStyle())
            TextField("40", text: $text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .frame(width: 36, height: 26)
                .background(Color.fdBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
                .onSubmit { commit() }
                .onAppear { text = "\(minutes)" }
                .onChange(of: minutes) { _, value in
                    let formatted = "\(value)"
                    if text != formatted { text = formatted }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            Button { adjust(5) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(TimeAdjustButtonStyle())
            Text("分钟")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.fdMuted)
        }
    }

    private func commit() {
        guard let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            text = "\(minutes)"
            return
        }
        let clamped = min(240, max(1, parsed))
        minutes = clamped
        text = "\(clamped)"
    }

    private func adjust(_ delta: Int) {
        commit()
        let next = min(240, max(1, minutes + delta))
        minutes = next
        text = "\(next)"
    }
}

private struct TimeAdjustButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.fdMuted)
            .frame(width: 20, height: 20)
            .background(configuration.isPressed ? Color.fdLine : Color.fdBackground)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.fdLine, lineWidth: 1))
    }
}
