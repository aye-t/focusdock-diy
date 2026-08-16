import SwiftUI

struct FocusView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCustomDuration = false
    @State private var customMinutes = 45

    private var phaseColor: Color { model.isRest ? .fdGreen : .fdCoral }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("专注").font(.system(size: 22, weight: .semibold))
                    Text(model.phaseText).font(.system(size: 11)).foregroundStyle(Color.fdMuted)
                }
                Spacer()
                Text(Date.now.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
            }

            if let plan = model.activePlanItem {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(Color.fdPurple)
                    Text("今日计划").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.fdPurple)
                    Text(plan.title)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if let index = model.todayPlanItems.firstIndex(where: { $0.id == plan.id }) {
                        Text("第 \(index + 1) / \(model.todayPlanItems.count) 项")
                            .font(.system(size: 10)).foregroundStyle(Color.fdMuted)
                    }
                    Button("查看计划") { model.selectedSection = .dailyPlan }
                        .buttonStyle(.plain).foregroundStyle(Color.fdPurple)
                }
                .panel(padding: 12)
            } else if let next = model.nextPlanItem {
                HStack(spacing: 10) {
                    Image(systemName: "forward.end").foregroundStyle(Color.fdMuted)
                    Text("下一项：\(next.title)")
                        .font(.system(size: 10)).foregroundStyle(Color.fdMuted)
                    Spacer()
                    Button("开始") { model.startPlanItem(next) }.buttonStyle(SecondaryButtonStyle())
                    Button("今日计划") { model.selectedSection = .dailyPlan }.buttonStyle(.plain)
                }
                .panel(padding: 10)
            }

            HStack(spacing: 18) {
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("当前任务").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.fdMuted)
                            TextField("输入这一轮要做的事", text: $model.task)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .medium))
                                .onChange(of: model.task) { _, newValue in
                                    if let activeTodoID = model.activeTodoID,
                                       let activeTodo = model.todos.first(where: { $0.id == activeTodoID }),
                                       activeTodo.title != newValue {
                                        model.activeTodoID = nil
                                    }
                                    model.persist()
                                }
                            HStack(spacing: 12) {
                                Button("存为任务") { model.saveCurrentTaskAsTodo() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.fdPurple)
                                    .disabled(model.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("打开任务") { model.selectedSection = .todos }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.fdPurple)
                            }
                        }
                        Picker("模式", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                            Text("倒计时").tag(TimerMode.countdown)
                            Text("自由计时").tag(TimerMode.countup)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 178)
                        .disabled(model.phase != .idle)
                    }
                    .padding(.bottom, 14)
                    Divider().overlay(Color.fdLine)

                    Spacer(minLength: 14)
                    timerRing
                    Spacer(minLength: 12)

                    if (model.phase == .idle || model.phase == .focusPaused) && model.mode == .countdown {
                        if model.phase == .focusPaused {
                            Text("已暂停，可修改任务与剩余时间")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.fdPurple)
                                .padding(.bottom, 2)
                        }
                        HStack(spacing: 8) {
                            ForEach([10, 25, 45, 50], id: \.self) { minutes in
                                Button("\(minutes) 分钟") { applyDuration(minutes) }
                                    .buttonStyle(DurationButtonStyle(active: editableMinutes == minutes))
                            }
                            Button("自定义") {
                                customMinutes = editableMinutes
                                showCustomDuration = true
                            }
                            .buttonStyle(DurationButtonStyle(active: ![10, 25, 45, 50].contains(editableMinutes)))
                            .popover(isPresented: $showCustomDuration, arrowEdge: .bottom) {
                                CustomDurationPopover(minutes: $customMinutes) {
                                    applyDuration(customMinutes)
                                    showCustomDuration = false
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.fdGreen)
                            Text("休息").font(.system(size: 10, weight: .medium))
                            EditableStepper(
                                value: Binding(
                                    get: { model.settings.restMinutes },
                                    set: { newValue in model.updateSettings { $0.restMinutes = newValue } }
                                ),
                                range: 1...60,
                                unit: "分钟",
                                compact: true
                            )
                        }
                        .padding(.top, 8)
                    } else {
                        Text(model.isRest ? "休息 \(model.settings.restMinutes) 分钟" : model.task.isEmpty ? "未命名专注" : model.task)
                            .font(.system(size: 11)).foregroundStyle(Color.fdMuted).frame(height: 31)
                    }

                    HStack(spacing: 10) {
                        Button("重置") { model.resetTimer() }
                            .buttonStyle(SecondaryButtonStyle()).disabled(model.phase == .idle)
                        Button {
                            model.performPrimaryAction()
                        } label: {
                            Label(model.primaryActionTitle, systemImage: model.isRunning ? "pause.fill" : "play.fill")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        if model.phase == .focusRunning || model.phase == .focusPaused {
                            Button("完成") { model.finishEarly() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button(model.isRest ? "跳过休息" : "跳过任务") {
                            model.skipCurrentPhase()
                        }
                        .buttonStyle(DangerButtonStyle())
                        .disabled(!(model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused))
                    }
                    .padding(.top, 22)
                }
                .panel(padding: 25)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 16) {
                    nextReminderPanel
                    todayPanel
                }
                .frame(width: 285)
            }
        }
        .padding(28)
    }

    private var timerRing: some View {
        ZStack {
            Circle().stroke(Color.fdLine.opacity(0.75), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.002, model.progress))
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: model.progress)
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(phaseColor).frame(width: 6, height: 6)
                    Text(model.phaseText).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.fdMuted)
                }
                Text(model.timeText)
                    .font(.system(size: 51, weight: .medium, design: .monospaced))
                    .tracking(-3)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 280, height: 280)
    }

    private var nextReminderPanel: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "bell.badge.fill").foregroundStyle(Color.fdPurple)
                Text("下一次提醒").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            if let reminder = model.nextReminder {
                Text(reminder.name).font(.system(size: 18, weight: .semibold))
                Text("\(max(1, Int(ceil(reminder.nextFireAt.timeIntervalSince(model.now) / 60)))) 分钟后")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                if !model.queuedReminderIDs.isEmpty {
                    Text("\(model.queuedReminderIDs.count) 项待提醒")
                        .font(.system(size: 10)).foregroundStyle(Color.fdMuted)
                }
            } else {
                Text("没有启用的提醒").font(.system(size: 12)).foregroundStyle(Color.fdMuted)
            }
            Spacer()
            Button("管理提醒") { model.selectedSection = .reminders }.buttonStyle(.plain).foregroundStyle(Color.fdPurple).font(.system(size: 11, weight: .medium))
        }
        .panel()
        .frame(maxHeight: .infinity)
    }

    private var todayPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(Color.fdCoral)
                Text("今日").font(.system(size: 12, weight: .semibold))
            }
            Text(todayFocusDisplay)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                + Text(" \(todayFocusUnit)").font(.system(size: 11)).foregroundStyle(Color.fdMuted)
            HStack {
                Label("\(model.todaySessions.count) 轮", systemImage: "timer")
                Spacer()
                Label("\(model.reminderCompletionRate)%", systemImage: "checkmark.circle")
            }
            .font(.system(size: 10)).foregroundStyle(Color.fdMuted)
            Spacer()
            Button("查看记录") { model.selectedSection = .review }.buttonStyle(.plain).foregroundStyle(Color.fdPurple).font(.system(size: 11, weight: .medium))
        }
        .panel()
        .frame(maxHeight: .infinity)
    }

    private var todayFocusDisplay: String {
        let m = model.todayFocusMinutes
        if m >= 60 {
            return "\(m / 60)"
        } else {
            return "\(m)"
        }
    }

    private var editableMinutes: Int {
        max(1, Int((model.phase == .focusPaused ? model.displayedSeconds : model.durationSeconds) / 60))
    }

    private func applyDuration(_ minutes: Int) {
        if model.phase == .focusPaused {
            model.replacePausedCountdownDuration(minutes)
        } else {
            model.selectDuration(minutes)
        }
    }

    private var todayFocusUnit: String {
        let m = model.todayFocusMinutes
        if m >= 60 {
            let rm = m % 60
            return rm > 0 ? "小时 \(rm)min" : "小时"
        } else {
            return "分钟"
        }
    }
}

private struct CustomDurationPopover: View {
    @Binding var minutes: Int
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自定义专注时长").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                TextField("分钟", value: $minutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onChange(of: minutes) { _, newValue in minutes = min(180, max(1, newValue)) }
                Text("分钟").font(.system(size: 11)).foregroundStyle(Color.fdMuted)
                Stepper("", value: $minutes, in: 1...180).labelsHidden()
            }
            Button("应用") { confirm() }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(width: 230)
    }
}

private struct AbandonPopover: View {
    @Binding var reason: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    private static let presetReasons = ["临时有事", "时间冲突", "状态不佳", "太难了想换思路", "其他原因"]
    @State private var selectedPreset: String? = nil

    private var reasonValid: Bool {
        if let s = selectedPreset, !s.isEmpty { return true }
        return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var finalReason: String {
        if let s = selectedPreset, !s.isEmpty { return s }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fdCoral)
                Text("放弃本轮专注").font(.system(size: 14, weight: .semibold))
            }

            Text("选择或输入放弃原因").font(.system(size: 10)).foregroundStyle(Color.fdMuted)

            // 预设选项（胶囊按钮）
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.presetReasons, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if selectedPreset == option {
                                selectedPreset = nil
                            } else {
                                selectedPreset = option
                                reason = ""
                            }
                        }
                    } label: {
                        Text(option)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedPreset == option ? .white : Color.fdMuted)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(selectedPreset == option ? Color.fdCoral : Color.fdPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedPreset == option ? Color.clear : Color.fdLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 自定义输入（选中"其他原因"时高亮提示）
            TextField("或自定义输入原因…", text: $reason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onChange(of: reason) { _, _ in
                    if !reason.isEmpty {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedPreset = nil }
                    }
                }

            HStack {
                Button("取消") { onCancel() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("确认放弃") { onConfirm(finalReason) }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(!reasonValid)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

private struct DurationButtonStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(active ? Color.fdPurple : Color.fdMuted)
            .padding(.horizontal, 12)
            .frame(height: 31)
            .background(active ? Color.fdPurpleSoft : Color.fdBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(active ? Color.fdPurple.opacity(0.25) : Color.fdLine))
    }
}
