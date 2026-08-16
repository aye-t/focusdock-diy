import SwiftUI

enum FloatingFocusPanelMetrics {
    static let width: CGFloat = 270
    static let compactHeight: CGFloat = 176
    static let quickAddHeight: CGFloat = 210
    static let todayPlanHeight: CGFloat = FloatingTodayPlanMetrics.height
}

struct FloatingTimerCapsuleView: View {
    @EnvironmentObject private var model: AppModel

    var width: CGFloat = 240
    var onOpen: () -> Void

    private var accent: Color {
        model.isRest ? Color.fdGreen : Color.fdPurple
    }

    private var displayTime: String {
        model.phase == .idle ? String(format: "%02d:00", model.settings.focusMinutes) : model.timeText
    }

    private var displayTask: String {
        if model.phase == .idle { return "未开始" }
        if model.isRest { return "休息" }
        return model.floatingFocusTaskLabel
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayTime)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fdInk)
                    Text(displayTask)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { model.performPrimaryAction() } label: {
                Image(systemName: model.phase.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.fdPurple)
                    .frame(width: 28, height: 28)
                    .background(Color.fdPurpleSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.primaryActionTitle)

            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                Button { model.skipCurrentPhase() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.fdCoral)
                        .frame(width: 28, height: 28)
                        .background(Color.fdCoral.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(model.isRest ? "跳过休息" : "跳过当前任务")
            }
        }
        .padding(.horizontal, 11)
        .frame(width: width, height: 48)
        .background(
            ZStack {
                Color.fdPanel.opacity(0.97)
                LinearGradient(
                    colors: [accent.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 1))
        .shadow(color: accent.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

}

struct MinimalFloatingFocusPanelView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)?
    var onPreferredSizeChange: ((CGSize) -> Void)?
    @State private var pendingMinutes: Int?
    @State private var showingQuickAdd = false
    @State private var showingTodayPlan = false

    private var displayTime: String {
        model.phase == .idle ? String(format: "%02d:00", model.settings.focusMinutes) : model.timeText
    }

    private var displayTask: String {
        if model.phase == .idle { return "未开始" }
        if model.isRest { return "休息" }
        return model.floatingFocusTaskLabel
    }

    private var timerAccent: Color {
        model.isRest ? Color.fdGreen : Color.fdPurple
    }

    private var planTotal: Int { model.todayPlanItems.count }
    private var planCompleted: Int { model.todayCompletedPlanItems }
    private var planProgress: Double {
        guard planTotal > 0 else { return 0 }
        return Double(planCompleted) / Double(planTotal)
    }

    private var preferredHeight: CGFloat {
        if showingTodayPlan { return FloatingFocusPanelMetrics.todayPlanHeight }
        if showingQuickAdd { return FloatingFocusPanelMetrics.quickAddHeight }
        return FloatingFocusPanelMetrics.compactHeight
    }

    var body: some View {
        Group {
            if showingTodayPlan {
                FloatingTodayPlanPopoverView(onClose: { showingTodayPlan = false })
                    .environmentObject(model)
            } else if showingQuickAdd {
                FloatingQuickAddTaskView { showingQuickAdd = false }
                    .environmentObject(model)
                    .padding(10)
                    .frame(width: 270, height: 210)
                    .background(Color.fdPanel.opacity(0.99))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                compactPanel
            }
        }
        .frame(width: FloatingFocusPanelMetrics.width, height: preferredHeight, alignment: .top)
        .transaction { transaction in
            // 悬浮面板使用固定尺寸切页，避免 AppKit 在弹窗动画中反复重算窗口约束。
            transaction.animation = nil
        }
        .onAppear(perform: reportPreferredSize)
        .onChange(of: showingQuickAdd) { _, _ in reportPreferredSize() }
        .onChange(of: showingTodayPlan) { _, _ in reportPreferredSize() }
        .alert("开始新的倒计时？", isPresented: replacementAlertBinding) {
            Button("取消", role: .cancel) { pendingMinutes = nil }
            Button("结束当前并开始", role: .destructive) {
                guard let minutes = pendingMinutes else { return }
                model.startNewFloatingCountdown(minutes: minutes)
                pendingMinutes = nil
                close()
            }
        } message: {
            Text("当前倒计时将结束，不会记为完成。")
        }
    }

    private var compactPanel: some View {
        VStack(spacing: 0) {
            timerHeader
            Divider()
            progressRow
            priorityRow
            Divider()
            footer
        }
        .frame(width: 270)
        .background(Color.fdPanel.opacity(0.99))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.13), radius: 12, y: 5)
    }

    private var timerHeader: some View {
        HStack(spacing: 5) {
            timerBadge
            Spacer(minLength: 2)
            iconButton(
                model.phase.isRunning ? "pause.fill" : "play.fill",
                help: model.primaryActionTitle
            ) { model.performPrimaryAction() }

            if model.phase == .focusRunning || model.phase == .focusPaused {
                iconButton("checkmark", help: "完成当前任务", tint: .fdGreen) {
                    model.finishEarly()
                }
            }

            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                skipButton(model.isRest ? "跳过休息" : "跳过任务") {
                    model.skipCurrentPhase()
                    close()
                }
            }

            if onClose != nil {
                iconButton("chevron.down", help: "收起") { close() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private var timerBadge: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(displayTime)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fdInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            TextField("名称", text: taskNameBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdInk)
                .lineLimit(1)
                .disabled(model.isRest)
        }
        .padding(.horizontal, 11)
        .frame(width: 88, height: 48, alignment: .leading)
        .background(timerAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(timerAccent.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTask)，\(displayTime)")
    }

    private var taskNameBinding: Binding<String> {
        Binding(
            get: { model.task.isEmpty ? model.timerTitle : model.task },
            set: { model.updateCurrentTask($0) }
        )
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(planTotal == 0 ? "今日暂无计划" : "今日 \(planCompleted)/\(planTotal)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdMuted)
                .frame(width: 74, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.fdLine)
                    Capsule()
                        .fill(Color.fdPurple)
                        .frame(width: max(planProgress > 0 ? 4 : 0, proxy.size.width * planProgress))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    @ViewBuilder
    private var priorityRow: some View {
        if let reminder = model.activePlanReminderItem {
            planReminderRow(reminder)
        } else {
            nextPlanRow
        }
    }

    private var reminderRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.fdCoral)
                .frame(width: 16)
            Text(model.activeReminderNames.first ?? "提醒")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fdInk)
                .lineLimit(1)
            Spacer()
            iconButton("checkmark", help: "完成提醒", tint: .fdGreen) {
                model.resolveActiveReminders(completed: true)
                WindowManager.shared.showMainWindow(section: .focus)
            }
            iconButton("clock", help: "10 分钟后提醒") {
                model.snoozeActiveReminders()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color.fdCoral.opacity(0.08))
    }

    private func planReminderRow(_ item: DailyPlanItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.fdCoral)
                .frame(width: 16)
            Text(model.planDisplayTitle(item))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fdInk)
                .lineLimit(1)
            Spacer()
            iconButton("play.fill", help: "现在开始") {
                model.startActivePlanReminder()
                close()
            }
            iconButton("clock", help: "10 分钟后提醒") { model.snoozePlanReminder() }
            iconButton("xmark", help: "暂不开始") { model.dismissPlanReminder() }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color.fdCoral.opacity(0.08))
    }

    private var nextPlanRow: some View {
        Button {
            guard let item = model.nextPlanItem else { return }
            model.startPlanItem(item)
            close()
        } label: {
            HStack(spacing: 9) {
            Image(systemName: model.nextPlanItem == nil ? "checkmark.circle" : "clock")
                .foregroundStyle(model.nextPlanItem == nil ? Color.fdGreen : Color.fdMuted)
                .frame(width: 16)
            if let item = model.nextPlanItem {
                if let minute = item.reminderStartMinute {
                    Text(String(format: "%02d:%02d", minute / 60, minute % 60))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.fdMuted)
                }
                Text(model.planDisplayTitle(item))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
                Spacer()
                Text("下一项")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.fdMuted)
            } else {
                Text(planTotal == 0 ? "暂无下一项" : "今日计划已完成")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                Spacer()
            }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.nextPlanItem == nil)
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button {
                showingQuickAdd = true
            } label: {
                footerIcon("plus", help: "新倒计时")
            }
            .buttonStyle(.plain)

            Button {
                showingTodayPlan = true
            } label: {
                footerIcon("list.bullet", help: "在悬浮窗管理今日任务")
            }
            .buttonStyle(.plain)

            Menu {
                Button("打开 FocusDock") {
                    WindowManager.shared.showMainWindow(section: .focus)
                    close()
                }
                Button("重置倒计时") { model.resetTimer() }
                Divider()
                Button("悬浮窗设置") {
                    WindowManager.shared.showMainWindow(section: .settings)
                    close()
                }
            } label: {
                footerIcon("ellipsis", help: "更多")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .frame(height: 40)
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        tint: Color = .fdPurple,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func skipButton(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "forward.end.fill")
                Text("跳过")
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.fdCoral)
            .frame(width: 48, height: 28)
            .background(Color.fdCoral.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func footerIcon(_ systemName: String, help: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.fdInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .help(help)
    }

    private var replacementAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingMinutes != nil },
            set: { if !$0 { pendingMinutes = nil } }
        )
    }

    private func requestNewCountdown(minutes: Int) {
        if model.phase == .idle {
            model.startNewFloatingCountdown(minutes: minutes)
            close()
        } else {
            pendingMinutes = minutes
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func reportPreferredSize() {
        onPreferredSizeChange?(
            CGSize(width: FloatingFocusPanelMetrics.width, height: preferredHeight)
        )
    }
}

struct FloatingQuickAddTaskView: View {
    @EnvironmentObject private var model: AppModel
    @State private var taskName = ""
    @State private var minutes = 25
    let onClose: () -> Void

    private var trimmedTaskName: String {
        taskName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.fdPurple)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("添加任务")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.fdInk)
                    Text("加入今天的专注安排")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.fdMuted)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fdPurple)
                TextField("任务名称", text: $taskName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdInk)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.fdPanel.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.fdPurple.opacity(0.20), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Label("专注时长", systemImage: "timer")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                Spacer()
                minuteButton("minus") { minutes = max(1, minutes - 5) }
                Text("\(minutes) 分钟")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.fdInk)
                    .frame(width: 58)
                minuteButton("plus") { minutes = min(180, minutes + 5) }
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(Color.fdPurpleSoft.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.fdPurple.opacity(0.12), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Button("取消", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(Color.fdPanel.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Button(action: addTask) {
                    Label("添加任务", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.fdPurple.opacity(trimmedTaskName.isEmpty ? 0.38 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .disabled(trimmedTaskName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [Color.fdPurpleSoft.opacity(0.96), Color.fdBackground.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.fdPurple.opacity(0.16), lineWidth: 1)
        )
    }

    private func minuteButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.fdPurple)
                .frame(width: 25, height: 25)
                .background(Color.fdPanel.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(systemName == "minus" ? "减少 5 分钟" : "增加 5 分钟")
    }

    private func addTask() {
        guard !trimmedTaskName.isEmpty else { return }
        model.addDailyPlanItem(
            title: trimmedTaskName,
            date: Date(),
            reminderStartMinute: nil,
            focusMinutes: minutes,
            restMinutes: model.settings.restMinutes
        )
        onClose()
    }
}
