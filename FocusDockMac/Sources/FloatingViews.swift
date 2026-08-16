import SwiftUI

enum FloatingTodayPlanMetrics {
    static let width: CGFloat = 270
    // Includes the view's 10-point vertical padding and enough baseline room
    // for both footer actions. The old 230-point value clipped their labels in
    // a real NSPopover even though the body itself still fit.
    static let height: CGFloat = 250
}

struct FloatingTimerPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.settings.usesStandaloneTimerSurface {
            IndependentFloatingTimerIconView()
        } else {
            CombinedFloatingView()
        }
    }
}

private struct FloatingPlanItemEditor: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: DailyPlanItem
    let onClose: () -> Void

    init(item: DailyPlanItem, onClose: @escaping () -> Void) {
        _draft = State(initialValue: item)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onClose) {
                    Label("返回今日任务", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fdPurple)
                Spacer()
                Text("修改任务")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.fdInk)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("任务名称")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("任务名称", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                durationEditor(
                    title: "专注时长",
                    value: $draft.focusMinutes,
                    range: 1...180,
                    symbol: "timer"
                )
                durationEditor(
                    title: "休息时长",
                    value: $draft.restMinutes,
                    range: 1...60,
                    symbol: "cup.and.saucer"
                )
            }

            Spacer()

            HStack {
                Button("删除任务", role: .destructive) {
                    model.deletePlanItem(draft.id)
                    onClose()
                }
                .buttonStyle(.plain)
                Spacer()
                Button("取消", action: onClose)
                    .buttonStyle(.plain)
                Button("保存") {
                    draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.updatePlanItem(draft)
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.fdPurple)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
    }

    private func durationEditor(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdMuted)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) 分钟")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fdInk)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.fdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct IndependentFloatingTimerIconView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color { model.settings.floatingTint.color }
    private var surface: Color { Color.fdPanel.opacity(0.98) }
    private var surfaceStroke: Color {
        colorScheme == .dark ? .white.opacity(0.12) : Color.fdLine.opacity(0.75)
    }
    private var surfaceShadow: Color { .black.opacity(colorScheme == .dark ? 0.30 : 0.14) }

    var body: some View {
        Button { WindowManager.shared.toggleFocusPopover() } label: {
            TimerIconView(
                style: model.settings.timerIconStyle,
                timeText: model.timeText,
                idleMinutes: model.settings.focusMinutes,
                progress: model.progress,
                isIdle: model.phase == .idle,
                isRunning: model.phase.isRunning,
                isRest: model.isRest,
                isFinished: model.phase == .focusFinished,
                tint: tint,
                finishedTint: Color.fdGreen,
                surface: surface,
                surfaceStroke: surfaceStroke,
                surfaceShadow: surfaceShadow
            )
            .padding(FloatingTimerPanelMetrics.independentContentInset)
        }
        .buttonStyle(.plain)
        .help("展开番茄钟")
        .accessibilityLabel("番茄钟，\(model.phaseText)，\(model.timeText)")
    }
}

struct FloatingTimerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var tint: Color { model.settings.floatingTint.color }
    private var surface: Color { Color.fdPanel.opacity(hovering ? 1 : 0.97) }
    private var surfaceStroke: Color { colorScheme == .dark ? .white.opacity(0.12) : Color.fdLine.opacity(0.75) }
    private var surfaceShadow: Color { .black.opacity(colorScheme == .dark ? 0.30 : 0.14) }

    var body: some View {
        FloatingTimerCapsuleView(width: 240) {
            WindowManager.shared.toggleFocusPopover()
        }
        .padding(4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onChange(of: model.floatingPlanPopoverToken) { _, _ in
            WindowManager.shared.showFocusPopover()
        }
        .contextMenu {
            Button("填写任务与时间…") { WindowManager.shared.showMainWindow(section: .focus) }
            Button("查看今日计划") { WindowManager.shared.showMainWindow(section: .dailyPlan) }
            if model.phase == .focusRunning || model.phase == .focusPaused {
                Button("完成专注") { model.finishEarly() }
            }
            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                Button(model.isRest ? "跳过休息" : "跳过当前任务") { model.skipCurrentPhase() }
            }
            if model.phase == .focusFinished {
                Button("开始休息") { model.performPrimaryAction() }
            }
            if let feedback = model.completionFeedback {
                Button("查看完成记录") {
                    model.requestPlanDestination(.completed, date: feedback.endedAt)
                    WindowManager.shared.showMainWindow(section: .dailyPlan)
                }
            }
            if model.phase != .focusFinished {
                Button(model.primaryActionTitle) { model.performPrimaryAction() }
            }
            Button("重置") { model.resetTimer() }
            Divider()
            Button("更换图标") { WindowManager.shared.showMainWindow(section: .settings) }
            Button("隐藏番茄钟") { model.updateSettings { $0.showTimerPanel = false }; WindowManager.shared.refreshPanelVisibility() }
        }
        .help("单击展开专注面板")
        .accessibilityLabel("番茄钟，\(model.phaseText)，\(model.timeText)")
        .accessibilityHint("单击展开专注面板")
    }

    @ViewBuilder
    private var timerBody: some View {
        // 所有布局模式统一使用 TimerIconView（独立/合并格式一致）
        TimerIconView(
            style: model.settings.timerIconStyle,
            timeText: model.timeText,
            idleMinutes: model.settings.focusMinutes,
            progress: model.progress,
            isIdle: model.phase == .idle,
            isRunning: model.phase.isRunning,
            isRest: model.isRest,
            isFinished: model.phase == .focusFinished,
            tint: tint,
            finishedTint: Color.fdGreen,
            surface: surface,
            surfaceStroke: surfaceStroke,
            surfaceShadow: surfaceShadow
        )
    }
}

private struct TimerIconView: View {
    @EnvironmentObject private var model: AppModel
    let style: TimerIconStyle
    let timeText: String
    let idleMinutes: Int
    let progress: Double
    let isIdle: Bool
    let isRunning: Bool
    let isRest: Bool
    let isFinished: Bool
    let tint: Color
    let finishedTint: Color
    let surface: Color
    let surfaceStroke: Color
    let surfaceShadow: Color

    private var activeTint: Color { isFinished ? finishedTint : tint }
    private var ringProgress: Double { isFinished ? 1.0 : (isIdle ? 0.001 : progress) }

    /// 专注阶段的任务名放在计时图形内部；休息阶段不显示任务。
    private var centerTaskLabel: some View {
        Text(model.floatingFocusTaskLabel)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(model.isPaused ? Color.fdMuted : Color.fdInk)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 74)
            .minimumScaleFactor(0.75)
    }

    private var timerContextLabel: String {
        if isIdle { return "开始" }
        if isRest { return "休息" }
        return model.floatingFocusTaskLabel
    }

    var body: some View {
        switch style {
        case .progressRing:
            ZStack {
                Circle().fill(surface).shadow(color: surfaceShadow, radius: 10, y: 4)
                Circle().stroke(surfaceStroke, lineWidth: 1)
                Circle().stroke(Color.fdLine, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.004, ringProgress))
                    .stroke(activeTint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RotatingCountdownHighlight(tint: activeTint, isActive: isRunning && !isFinished, lineWidth: 5)
                timerLabel
            }
            .frame(width: 84, height: 84)
        case .tomato:
            ZStack {
                Circle().fill(surface).shadow(color: surfaceShadow, radius: 10, y: 4)
                Circle().stroke(surfaceStroke, lineWidth: 1)
                Circle()
                    .trim(from: 0, to: max(0.004, isIdle ? 0.001 : progress))
                    .stroke(
                        Color.fdCoral.opacity(0.72),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.24), Color.fdCoral, Color.fdCoral.opacity(0.88)],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 48
                            )
                        )
                        .frame(width: 62, height: 62)
                        .shadow(color: Color.fdCoral.opacity(0.22), radius: 5, y: 2)
                    Ellipse()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 25, height: 11)
                        .rotationEffect(.degrees(-24))
                        .offset(x: -11, y: -14)
                    HStack(spacing: -4) {
                        Capsule().fill(Color.fdGreen).frame(width: 19, height: 7).rotationEffect(.degrees(32))
                        Capsule().fill(Color.fdGreen).frame(width: 19, height: 7).rotationEffect(.degrees(-32))
                    }
                    .offset(y: -31)
                    VStack(spacing: 1) {
                        Text(isIdle ? "\(idleMinutes)" : timeText)
                            .font(.system(size: timeText.count > 5 ? 9 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .tracking(-0.35)
                        Text(timerContextLabel)
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 54)
                            .minimumScaleFactor(0.72)
                    }
                }
                .offset(y: 2)
            }
            .frame(width: 84, height: 84)
        case .hourglass:
            ZStack {
                Circle().fill(surface).shadow(color: surfaceShadow, radius: 10, y: 4)
                Circle().stroke(surfaceStroke, lineWidth: 1)
            VStack(spacing: 3) {
                FlowingHourglassGlyph(size: 26, tint: activeTint, isActive: isRunning)
                Text(isIdle ? "\(idleMinutes) 分" : timeText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fdMuted)
                if !isIdle {
                    if isRest {
                        Text("休息").font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                    } else {
                        centerTaskLabel
                    }
                }
            }
            }
            .frame(width: 84, height: 84)
        case .digital:
            VStack(spacing: 5) {
                Text(isIdle ? "\(idleMinutes):00" : timeText)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(-0.8)
                    .foregroundStyle(.primary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fdLine)
                        Capsule().fill(activeTint).frame(width: max(4, proxy.size.width * (isIdle ? 0 : progress)))
                    }
                }
                .frame(height: 5)
                if !isIdle {
                    if isRest {
                        Text("休息").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                    } else {
                        centerTaskLabel
                    }
                }
            }
            .padding(.horizontal, 15)
            .frame(width: 120, height: 84)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(surfaceStroke, lineWidth: 1))
            .shadow(color: surfaceShadow, radius: 10, y: 4)
        }
    }

    private var timerLabel: some View {
        VStack(spacing: 4) {
            if isIdle {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(activeTint)
                Text("\(idleMinutes) 分").font(.system(size: 9, weight: .semibold))
        } else if isRest {
            Text(timeText).font(.system(size: timeText.count > 5 ? 10 : 13, weight: .semibold, design: .monospaced)).tracking(-0.7).foregroundStyle(tint)
            Text("休息").font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
        } else if isFinished {
            Text(timeText).font(.system(size: timeText.count > 5 ? 10 : 13, weight: .semibold, design: .monospaced)).tracking(-0.7).foregroundStyle(finishedTint)
            Text("已完成").font(.system(size: 8, weight: .bold)).foregroundStyle(finishedTint)
        } else {
            Text(timeText).font(.system(size: timeText.count > 5 ? 10 : 13, weight: .semibold, design: .monospaced)).tracking(-0.7)
            centerTaskLabel
        }
        }
    }
}

private struct CompactTimerGlyph: View {
    @EnvironmentObject private var model: AppModel
    let tint: Color
    let isDark: Bool
    let timerFace: Color

    private var isRest: Bool { model.isRest }
    private var isFinished: Bool { model.phase == .focusFinished }
    private var activeTint: Color { isFinished ? Color.fdGreen : tint }
    private var ringProgress: Double { isFinished ? 1.0 : (model.phase == .idle ? 0.001 : model.progress) }

    var body: some View {
        switch model.settings.timerIconStyle {
        case .progressRing:
            ZStack {
                Circle()
                    .fill(timerFace)
                    .shadow(color: .black.opacity(isDark ? 0.20 : 0.08), radius: 6, y: 2)
                Circle().stroke(Color.fdLine.opacity(isDark ? 0.95 : 1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.004, ringProgress))
                    .stroke(activeTint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RotatingCountdownHighlight(tint: activeTint, isActive: model.phase.isRunning && !isFinished, lineWidth: 5)
                VStack(spacing: 1) {
                    Text(model.phase == .idle ? "\(model.settings.focusMinutes)" : model.timeText)
                        .font(.system(size: model.timeText.count > 5 ? 9 : 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(isDark ? Color.fdInk.opacity(0.92) : Color.fdInk)
                        .tracking(-0.4)
                    if isRest && model.phase != .idle {
                        Text("休息").font(.system(size: 7, weight: .bold)).foregroundStyle(tint)
                    } else if isFinished {
                        Text("已完成").font(.system(size: 7, weight: .bold)).foregroundStyle(activeTint)
                    } else if model.phase != .idle {
                        Text(model.floatingFocusTaskLabel)
                            .font(.system(size: 6.5, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: 40)
                    }
                }
            }
            .frame(width: 54, height: 54)
        case .tomato:
            ZStack {
                Circle()
                    .fill(timerFace)
                    .shadow(color: .black.opacity(isDark ? 0.20 : 0.08), radius: 6, y: 2)
                Circle().stroke(Color.fdLine.opacity(isDark ? 0.95 : 1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.004, model.phase == .idle ? 0.001 : model.progress))
                    .stroke(Color.fdCoral, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(Color.fdCoral).frame(width: 38, height: 38)
                HStack(spacing: -2) {
                    Capsule().fill(Color.fdGreen).frame(width: 13, height: 5).rotationEffect(.degrees(28))
                    Capsule().fill(Color.fdGreen).frame(width: 13, height: 5).rotationEffect(.degrees(-28))
                }
                .offset(y: -22)
                VStack(spacing: 0) {
                    Text(model.phase == .idle ? "\(model.settings.focusMinutes)" : (model.timeText.split(separator: ":").first.map(String.init) ?? model.timeText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    if model.phase != .idle {
                        Text(isRest ? "休息" : model.floatingFocusTaskLabel)
                            .font(.system(size: 6, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: 34)
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            .overlay(alignment: .bottom) {
                if isRest && model.phase != .idle {
                    Text("休息")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tint.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(timerFace))
                        .overlay(Capsule().stroke(tint.opacity(0.2), lineWidth: 0.5))
                        .offset(y: 6)
                }
            }
        case .hourglass:
            VStack(spacing: 1) {
                FlowingHourglassGlyph(size: 21, tint: activeTint, isActive: model.phase.isRunning)
                Text(model.phase == .idle ? "\(model.settings.focusMinutes)分" : model.timeText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.fdInk)
                if isRest && model.phase != .idle {
                    Text("休").font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                } else if model.phase != .idle {
                    Text(model.floatingFocusTaskLabel)
                        .font(.system(size: 6.5, weight: .medium))
                        .lineLimit(1)
                }
            }
            .frame(width: 54, height: 54)
        case .digital:
            VStack(spacing: 2) {
                Text(model.phase == .idle ? "\(model.settings.focusMinutes):00" : model.timeText)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fdInk)
                    .tracking(-0.4)
                if isRest && model.phase != .idle {
                    Text("休息").font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                } else if model.phase != .idle {
                    Text(model.floatingFocusTaskLabel)
                        .font(.system(size: 7, weight: .medium))
                        .lineLimit(1)
                }
            }
            .frame(width: 72)
        }
    }
}

struct FloatingReminderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPopover = false

    private var reminderTitle: String {
        reminderSummary.rows.first?.title ?? "提醒"
    }

    private var reminderTime: String {
        reminderSummary.rows.first?.subtitle ?? "未启用"
    }

    private var tint: Color { model.settings.floatingTint.color }
    private var surface: Color { Color.fdPanel.opacity(0.98) }
    private var surfaceStroke: Color { colorScheme == .dark ? .white.opacity(0.12) : tint.opacity(0.18) }
    private var surfaceShadow: Color { .black.opacity(colorScheme == .dark ? 0.30 : 0.14) }
    private var reminderSummary: FloatingReminderSummary { FloatingReminderSummary(model: model) }

    private var reminderSymbol: String {
        if !model.activeReminderIDs.isEmpty { return "bell.badge.fill" }
        switch model.settings.reminderIconStyle {
        case .automatic: return model.nextReminder?.symbol ?? "bell.fill"
        case .bell: return "bell.fill"
        case .water: return "drop.fill"
        case .breakCup: return "cup.and.saucer.fill"
        case .customEmoji: return ""
        }
    }

    private var hasActiveReminder: Bool {
        !model.activeReminderIDs.isEmpty || model.activePlanReminderID != nil
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            reminderRowsCard
                .padding(FloatingReminderPanelMetrics.contentInset)
        }
        .buttonStyle(.plain)
        .modifier(ReminderAttentionEffect(pulse: model.reminderPulse, emphasis: model.settings.reminderEmphasis))
        .help("\(reminderTitle) · \(reminderTime)")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ReminderPopoverView().environmentObject(model)
        }
        .onChange(of: model.reminderPulse) { _, _ in showPopover = hasActiveReminder }
        .onChange(of: model.activeReminderIDs) { _, ids in
            if ids.isEmpty && model.activePlanReminderID == nil { showPopover = false }
        }
        .onChange(of: model.activePlanReminderID) { _, id in
            showPopover = id != nil || !model.activeReminderIDs.isEmpty
        }
        .onAppear {
            showPopover = hasActiveReminder
        }
        .contextMenu {
            Button("显示提醒") { WindowManager.shared.showMainWindow(section: .reminders) }
            Button("预览提醒") { model.previewReminders() }
            Divider()
            Button("更换图标") { WindowManager.shared.showMainWindow(section: .settings) }
            Button("隐藏提醒图标") { model.updateSettings { $0.showReminderPanel = false }; WindowManager.shared.refreshPanelVisibility() }
        }
        .accessibilityLabel("提醒")
    }

    @ViewBuilder
    private func reminderGlyph(size: CGFloat) -> some View {
        if model.settings.reminderIconStyle == .customEmoji && model.activeReminderIDs.isEmpty {
            Text(model.settings.customReminderEmoji.isEmpty ? "🌱" : model.settings.customReminderEmoji)
                .font(.system(size: size))
        } else {
            Image(systemName: reminderSymbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(model.activeReminderIDs.isEmpty ? tint : Color.fdCoral)
        }
    }

    private var reminderRowsCard: some View {
        let iconSize: CGFloat = 36
        let rowTitleSize: CGFloat = 9.5
        let rowSubtitleSize: CGFloat = 8.5

        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.activeReminderIDs.isEmpty ? tint.opacity(0.13) : Color.fdCoral.opacity(0.13))
                    .frame(width: iconSize, height: iconSize)
                reminderGlyph(size: iconSize * 0.52).frame(width: iconSize, height: iconSize)
                if !model.queuedReminderIDs.isEmpty && model.activeReminderIDs.isEmpty {
                    Circle().fill(Color.fdGreen).frame(width: 8, height: 8)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if reminderSummary.rows.isEmpty {
                    Text("提醒未启用")
                        .font(.system(size: rowTitleSize, weight: .semibold))
                        .foregroundStyle(Color.fdMuted)
                        .lineLimit(1)
                } else {
                    ForEach(reminderSummary.rows) { row in
                        HStack(spacing: 6) {
                            Text(row.title)
                                .font(.system(size: rowTitleSize, weight: .semibold))
                                .foregroundStyle(row.isActive ? Color.fdCoral : Color.fdInk)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 0)
                            Text(row.subtitle)
                                .font(.system(size: rowSubtitleSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(row.isActive ? Color.fdCoral : Color.fdMuted)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    if reminderSummary.hiddenCount > 0 {
                        Text("+\(reminderSummary.hiddenCount) 项")
                            .font(.system(size: rowSubtitleSize, weight: .semibold))
                            .foregroundStyle(Color.fdMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(
            width: FloatingReminderPanelMetrics.contentSize.width,
            height: FloatingReminderPanelMetrics.contentSize.height
        )
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(surfaceStroke, lineWidth: 1))
        .shadow(color: surfaceShadow, radius: 10, y: 4)
    }
}

private struct CombinedFloatingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: AppModel
    @State private var showPopover = false

    private var tint: Color { model.settings.floatingTint.color }
    private var isDark: Bool { colorScheme == .dark }
    private var hasActiveReminder: Bool {
        !model.activeReminderIDs.isEmpty || model.activePlanReminderID != nil
    }
    private var barGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color.fdPanel.opacity(0.98), Color.fdSidebar.opacity(0.94)]
                : [.white.opacity(0.99), Color.fdPurpleSoft.opacity(0.58)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private var outerStroke: Color { isDark ? .white.opacity(0.12) : .white.opacity(0.88) }
    private var timerFace: Color { isDark ? Color.fdBackground.opacity(0.92) : .white.opacity(0.90) }
    private var iconFace: Color { isDark ? tint.opacity(0.18) : tint.opacity(0.12) }
    private var timerStroke: Color { isDark ? .white.opacity(0.12) : Color.fdLine.opacity(0.75) }
    private var timerShadow: Color { .black.opacity(isDark ? 0.22 : 0.08) }
    private var reminderSummary: FloatingReminderSummary { FloatingReminderSummary(model: model) }
    private var symbolName: String {
        if !model.activeReminderIDs.isEmpty { return "bell.badge.fill" }
        switch model.settings.reminderIconStyle {
        case .automatic: return model.nextReminder?.symbol ?? "bell.fill"
        case .bell: return "bell.fill"
        case .water: return "drop.fill"
        case .breakCup: return "cup.and.saucer.fill"
        case .customEmoji: return ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if model.settings.showTimerPanel {
                Button { WindowManager.shared.toggleFocusPopover() } label: {
                    compactTimer
                }
                .buttonStyle(.plain)
                .help("查看今日任务顺序")
            }
            if model.settings.showTimerPanel && model.settings.showReminderPanel {
                Capsule()
                    .fill(Color.fdLine.opacity(0.85))
                    .frame(width: 1, height: 36)
            }
            if model.settings.showReminderPanel {
                Button { showPopover.toggle() } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(model.activeReminderIDs.isEmpty ? iconFace : Color.fdCoral.opacity(isDark ? 0.20 : 0.12))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke((model.activeReminderIDs.isEmpty ? tint : Color.fdCoral).opacity(isDark ? 0.18 : 0.10), lineWidth: 1)
                                )
                            if model.settings.reminderIconStyle == .customEmoji && model.activeReminderIDs.isEmpty {
                                Text(model.settings.customReminderEmoji.isEmpty ? "🌱" : model.settings.customReminderEmoji)
                                    .font(.system(size: 19))
                            } else {
                                Image(systemName: symbolName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(model.activeReminderIDs.isEmpty ? tint : Color.fdCoral)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if reminderSummary.rows.isEmpty {
                                Text("提醒未启用")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.fdMuted)
                                    .lineLimit(1)
                            } else {
                                ForEach(reminderSummary.rows) { row in
                                    HStack(spacing: 6) {
                                        Text(row.title)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(row.isActive ? Color.fdCoral : Color.fdInk)
                                            .fixedSize(horizontal: true, vertical: false)
                                        Spacer(minLength: 0)
                                        Text(row.subtitle)
                                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(row.isActive ? Color.fdCoral : Color.fdMuted)
                                            .lineLimit(1)
                                    }
                                }
                                if reminderSummary.hiddenCount > 0 {
                                    Text("+\(reminderSummary.hiddenCount) 项")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(Color.fdMuted)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .modifier(ReminderAttentionEffect(pulse: model.reminderPulse, emphasis: model.settings.reminderEmphasis))
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    ReminderPopoverView().environmentObject(model)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(barGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(outerStroke, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(tint.opacity(isDark ? 0.22 : 0.14), lineWidth: 1))
        .shadow(color: .black.opacity(isDark ? 0.28 : 0.12), radius: 13, y: 5)
        .padding(3)
        .onChange(of: model.reminderPulse) { _, _ in showPopover = hasActiveReminder }
        .onChange(of: model.activeReminderIDs) { _, ids in
            if ids.isEmpty && model.activePlanReminderID == nil { showPopover = false }
        }
        .onChange(of: model.activePlanReminderID) { _, id in
            showPopover = id != nil || !model.activeReminderIDs.isEmpty
        }
        .onAppear {
            showPopover = hasActiveReminder
        }
        .contextMenu {
            Button("打开 FocusDock") { WindowManager.shared.showMainWindow() }
            Button("更换样式") { WindowManager.shared.showMainWindow(section: .settings) }
            if model.phase == .focusRunning || model.phase == .focusPaused {
                Button("完成专注") { model.finishEarly() }
            }
            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                Button(model.isRest ? "跳过休息" : "跳过当前任务") { model.skipCurrentPhase() }
            }
            if model.phase == .focusFinished {
                Button("开始休息") { model.performPrimaryAction() }
            }
            if let feedback = model.completionFeedback {
                Button("查看完成记录") {
                    model.requestPlanDestination(.completed, date: feedback.endedAt)
                    WindowManager.shared.showMainWindow(section: .dailyPlan)
                }
            }
            if model.phase != .focusFinished {
                Button(model.primaryActionTitle) { model.performPrimaryAction() }
            }
            Divider()
            Button("隐藏悬浮控件") {
                model.updateSettings { $0.showTimerPanel = false; $0.showReminderPanel = false }
                WindowManager.shared.refreshPanelVisibility()
            }
        }
    }

    @ViewBuilder private var compactTimer: some View {
        switch model.settings.timerIconStyle {
        case .digital:
            VStack(spacing: 5) {
                Text(model.phase == .idle ? "\(model.settings.focusMinutes):00" : model.timeText)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .tracking(-0.7)
                    .foregroundStyle(Color.fdInk)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fdLine.opacity(0.8))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(4, proxy.size.width * (model.phase == .idle ? 0 : model.progress)))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 13)
            .frame(width: 108, height: 58)
            .background(timerFace)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(timerStroke, lineWidth: 1))
            .shadow(color: timerShadow, radius: 8, y: 3)
        default:
            TimerIconView(
                style: model.settings.timerIconStyle,
                timeText: model.timeText,
                idleMinutes: model.settings.focusMinutes,
                progress: model.progress,
                isIdle: model.phase == .idle,
                isRunning: model.phase.isRunning,
                isRest: model.isRest,
                isFinished: model.phase == .focusFinished,
                tint: tint,
                finishedTint: Color.fdGreen,
                surface: timerFace,
                surfaceStroke: timerStroke,
                surfaceShadow: timerShadow
            )
            .scaleEffect(0.76)
            .frame(width: 72, height: 72)
        }
    }
}

@MainActor
private struct FloatingReminderSummary {
    let rows: [FloatingReminderRow]
    let hiddenCount: Int

    init(model: AppModel) {
        var rows: [FloatingReminderRow] = []
        let now = model.now
        let activeIDs = Set(model.activeReminderIDs)
        let queuedIDs = Set(model.queuedReminderIDs)

        rows.append(contentsOf: model.activeReminderIDs.compactMap { id in
            guard let rule = model.reminders.first(where: { $0.id == id }) else { return nil }
            return FloatingReminderRow(title: rule.name, subtitle: "待处理", isActive: true)
        })

        if rows.count < 3 {
            rows.append(contentsOf: model.queuedReminderIDs.compactMap { id in
                guard let rule = model.reminders.first(where: { $0.id == id }), !activeIDs.contains(id) else { return nil }
                return FloatingReminderRow(title: rule.name, subtitle: "专注后", isActive: true)
            }.prefix(3 - rows.count))
        }

        if rows.count < 3 {
            let futureRows = model.reminders
                .filter { $0.isEnabled && !activeIDs.contains($0.id) && !queuedIDs.contains($0.id) }
                .sorted {
                    Self.effectiveReminderDate(for: $0, model: model, now: now) < Self.effectiveReminderDate(for: $1, model: model, now: now)
                }
                .prefix(3 - rows.count)
                .map { rule in
                    let effectiveDate = Self.effectiveReminderDate(for: rule, model: model, now: now)
                    let minutes = max(1, Int(ceil(effectiveDate.timeIntervalSince(now) / 60)))
                    return FloatingReminderRow(title: rule.name, subtitle: "\(minutes) 分后", isActive: false)
                }
            rows.append(contentsOf: futureRows)
        }

        let enabledIDs = Set(model.reminders.filter(\.isEnabled).map(\.id))
        let total = activeIDs.union(queuedIDs).union(enabledIDs).count
        self.rows = rows
        hiddenCount = max(0, total - rows.count)
    }

    private static func effectiveReminderDate(for rule: ReminderRule, model: AppModel, now: Date) -> Date {
        if model.phase == .focusRunning,
           rule.policy == .deferToBreak,
           let targetDate = model.targetDate,
           rule.nextFireAt <= targetDate {
            return targetDate
        }
        return rule.nextFireAt
    }
}

private struct FloatingReminderRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let isActive: Bool
}

private struct RotatingCountdownHighlight: View {
    let tint: Color
    let isActive: Bool
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
            let turn = isActive ? context.date.timeIntervalSinceReferenceDate * 55 : 0
            Circle()
                .trim(from: 0, to: 0.10)
                .stroke(.white.opacity(isActive ? 0.78 : 0), style: StrokeStyle(lineWidth: max(2, lineWidth - 2), lineCap: .round))
                .rotationEffect(.degrees(turn - 90))
        }
        .allowsHitTesting(false)
    }
}

private struct FlowingHourglassGlyph: View {
    let size: CGFloat
    let tint: Color
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.0)
            ZStack {
                Image(systemName: "hourglass")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(tint)
                Circle()
                    .fill(tint)
                    .frame(width: max(2, size * 0.10), height: max(2, size * 0.10))
                    .offset(y: -size * 0.16 + phase * size * 0.32)
                    .opacity(isActive ? 0.95 : 0)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .allowsHitTesting(false)
    }
}

private struct ReminderAttentionEffect: ViewModifier {
    let pulse: Bool
    let emphasis: ReminderEmphasis
    @State private var scale: CGFloat = 1
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: offset)
            .onChange(of: pulse) { _, _ in animate() }
    }

    private func animate() {
        scale = 1
        offset = 0
        switch emphasis {
        case .subtle:
            withAnimation(.easeInOut(duration: 0.22).repeatCount(2, autoreverses: true)) { scale = 1.06 }
        case .enlarge:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55).repeatCount(2, autoreverses: true)) { scale = 1.16 }
        case .bounce:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.48).repeatCount(3, autoreverses: true)) {
                scale = 1.10
                offset = -7
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.18)) {
                scale = 1
                offset = 0
            }
        }
    }
}

struct ReminderPopoverView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("提醒").font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                if !model.activeReminderNames.isEmpty {
                    ForEach(model.activeReminderNames, id: \.self) { name in
                        Label(name, systemImage: "checkmark.circle").font(.system(size: 10))
                    }
                } else if let item = model.activePlanReminderItem {
                    Label(item.title, systemImage: "calendar.badge.clock")
                        .font(.system(size: 10))
                    Text("计划提醒 · 专注 \(item.focusMinutes) 分钟")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.fdMuted)
                } else if let next = model.nextReminder {
                    Label(next.name, systemImage: next.symbol)
                        .font(.system(size: 10))
                    Text("下次提醒将在 \(next.nextFireAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.fdMuted)
                } else {
                    Label("尚未启用提醒", systemImage: "bell.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.fdMuted)
                }
            }
            if model.activePlanReminderID != nil {
                HStack(spacing: 6) {
                    reminderButton("10 分钟后") {
                        model.snoozePlanReminder()
                        dismiss()
                    }
                    reminderButton("跳过") {
                        model.dismissPlanReminder()
                        dismiss()
                    }
                    reminderButton("开始", prominent: true) {
                        model.startActivePlanReminder()
                        dismiss()
                    }
                }
            } else if !model.activeReminderIDs.isEmpty {
                HStack(spacing: 6) {
                    reminderButton("10 分钟后") {
                        model.snoozeActiveReminders()
                        dismiss()
                    }
                    reminderButton("跳过") {
                        model.resolveActiveReminders(completed: false)
                        dismiss()
                    }
                    reminderButton("完成", prominent: true) {
                        model.resolveActiveReminders(completed: true)
                        dismiss()
                    }
                }
            } else {
                reminderButton("管理提醒", prominent: true) {
                    dismiss()
                    WindowManager.shared.showMainWindow(section: .reminders)
                }
            }
        }
        .padding(12)
        .frame(width: 252)
    }

    private func reminderButton(
        _ title: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.fdPurple)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(prominent ? Color.fdPurple : Color.fdPurpleSoft)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct FloatingTodayPlanPopoverView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)? = nil
    @State private var selectedTab: PlanTab = .upcoming
    @State private var showingQuickEditor = false
    @State private var editingItem: DailyPlanItem?
    @State private var quickTitle = ""
    @State private var quickTask = ""
    @State private var quickMinutes = 25
    @State private var didHydrateQuickForm = false

    private var pendingPlanItems: [DailyPlanItem] {
        model.todayPlanItems.filter { model.effectivePlanStatus($0) != .completed }
    }

    private var completedPlanItems: [DailyPlanItem] {
        model.todayPlanItems.filter { model.effectivePlanStatus($0) == .completed }
    }

    private var visiblePlanItems: [DailyPlanItem] {
        selectedTab == .upcoming ? pendingPlanItems : completedPlanItems
    }

    private var todayFocusRecords: [FocusSession] {
        TodayFocusRecordPolicy.records(sessions: model.sessions, on: Date())
    }

    private var canEditQuickTimer: Bool {
        model.phase == .idle
    }

    var body: some View {
        Group {
            if let editingItem {
                FloatingPlanItemEditor(item: editingItem) {
                    self.editingItem = nil
                }
                .environmentObject(model)
            } else if showingQuickEditor {
                FloatingQuickAddTaskView { showingQuickEditor = false }
                    .environmentObject(model)
            } else {
                planOverview
            }
        }
        .padding(10)
        .frame(width: FloatingTodayPlanMetrics.width, height: FloatingTodayPlanMetrics.height)
        .background(Color.fdPanel.opacity(0.99))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
        .transaction { transaction in transaction.animation = nil }
    }

    private var planOverview: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                tabButton(.upcoming, count: pendingPlanItems.count)
                tabButton(.completed, count: todayFocusRecords.count)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fdMuted)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    if selectedTab == .upcoming, pendingPlanItems.isEmpty {
                        Text("待办已经清空")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.fdMuted)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.fdBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if selectedTab == .completed, todayFocusRecords.isEmpty {
                        Text("今天还没有专注记录")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.fdMuted)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.fdBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if selectedTab == .upcoming {
                        ForEach(pendingPlanItems) { item in
                            floatingPlanRow(item, completed: false)
                        }
                    } else {
                        ForEach(todayFocusRecords) { session in
                            floatingFocusRecordRow(session)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Button {
                    showingQuickEditor = true
                } label: {
                    Label("添加任务", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fdPurple)
                Spacer()
                Button("打开完整计划") {
                    WindowManager.shared.showMainWindow(section: .dailyPlan)
                    close()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fdMuted)
            }
        }
    }

    private func floatingPlanRow(_ item: DailyPlanItem, completed: Bool) -> some View {
        let status = model.effectivePlanStatus(item)
        let orderedItems = model.todayPlanItems
        let position = orderedItems.firstIndex(where: { $0.id == item.id }) ?? 0
        return HStack(spacing: 6) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(completed ? Color.fdGreen : Color.fdMuted)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.planDisplayTitle(item))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(completed ? Color.fdMuted : Color.fdInk)
                    .lineLimit(1)
                Text(status == .running ? model.timeText : "\(item.focusMinutes) 分钟")
                    .font(.system(size: 8, weight: .medium, design: status == .running ? .monospaced : .default))
                    .foregroundStyle(Color.fdMuted)
            }
            Spacer(minLength: 2)
            if completed {
                Button("撤销") { model.togglePlanItemCompleted(item.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.fdPurple)
            } else {
                Button {
                    model.startPlanItem(item)
                    close()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.fdPurple)
                        .frame(width: 24, height: 24)
                        .background(Color.fdPurpleSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button("修改任务") { editingItem = item }
                if !completed {
                    Button("开始任务") {
                        model.startPlanItem(item)
                        close()
                    }
                }
                Divider()
                Button("上移") { model.movePlanItem(item.id, offset: -1) }
                    .disabled(position == 0)
                Button("下移") { model.movePlanItem(item.id, offset: 1) }
                    .disabled(position == orderedItems.count - 1)
                Button(completed ? "撤销完成" : "标记完成") {
                    model.togglePlanItemCompleted(item.id)
                }
                Divider()
                Button("删除任务", role: .destructive) { model.deletePlanItem(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                    .frame(width: 22, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(status == .running ? Color.fdPurpleSoft : Color.fdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func floatingFocusRecordRow(_ session: FocusSession) -> some View {
        let appearance = focusRecordAppearance(for: session.result)
        return HStack(spacing: 7) {
            Image(systemName: appearance.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appearance.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.task)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
                Text("\(session.minutes) 分钟 · \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.fdMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(appearance.title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(appearance.color)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(appearance.color.opacity(0.11))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(Color.fdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func focusRecordAppearance(for result: SessionResult) -> (title: String, symbol: String, color: Color) {
        switch result {
        case .done:
            ("已完成", "checkmark.circle.fill", Color.fdGreen)
        case .progress:
            ("有进展", "circle.lefthalf.filled", Color.fdPurple)
        case .interrupted:
            ("被打断", "exclamationmark.circle.fill", Color.fdMuted)
        case .abandoned:
            ("提前结束", "stop.circle.fill", Color.fdCoral)
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var workbenchTimerStrip: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%02d:00", quickMinutes))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fdLine)
                        Capsule().fill(Color.fdPurple).frame(width: max(8, proxy.size.width * 0.28))
                    }
                }
                .frame(width: 48, height: 4)
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("倒计时名称")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("上午专注", text: $quickTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 28)
                    .background(Color.fdPanel.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("任务")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("英语复习", text: $quickTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 28)
                    .background(Color.fdPanel.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }
            .frame(width: 58)

            VStack(spacing: 3) {
                stepButton("minus") { quickMinutes = max(1, quickMinutes - 5) }
                stepButton("plus") { quickMinutes = min(180, quickMinutes + 5) }
            }
            .frame(width: 22)

            Button {
                model.startFloatingTimer(title: quickTitle, task: quickTask, minutes: quickMinutes)
                dismiss()
            } label: {
                Text("开始")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 28)
                    .background(Color.fdPurple)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.fdPanel.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }

    private var runningWorkbenchTimerStrip: some View {
        HStack(alignment: .center, spacing: 7) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.timeText)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fdInk)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fdLine)
                        Capsule().fill(Color.fdPurple).frame(width: max(8, proxy.size.width * model.progress))
                    }
                }
                .frame(width: 48, height: 4)
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isRest ? "休息" : model.floatingTimerTitle)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                Text(model.isRest ? "休息中" : model.floatingFocusTaskLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
            }

            Spacer()

            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                planButton(model.primaryActionTitle) { model.performPrimaryAction() }
            }
            if model.phase == .focusRunning || model.phase == .focusPaused {
                planButton("完成", prominent: true) {
                    model.finishEarly()
                    dismiss()
                }
            }
            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                planButton(model.isRest ? "跳过休息" : "跳过") {
                    model.skipCurrentPhase()
                    dismiss()
                }
            }
        }
        .padding(8)
        .background(Color.fdPurpleSoft.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.fdLine.opacity(0.8), lineWidth: 1))
    }

    private func workbenchPlanColumn(
        title: String,
        items: [DailyPlanItem],
        emptyTitle: String,
        completedColumn: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.fdInk)
                Rectangle()
                    .fill(Color.fdLine)
                    .frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 6) {
                    if items.isEmpty {
                        Text(emptyTitle)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.fdMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(Color.fdBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    ForEach(items) { item in
                        workbenchPlanRow(item, completedColumn: completedColumn)
                    }
                }
            }
            .frame(maxHeight: 58)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
        .background(Color.fdPanel.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }

    private func workbenchPlanRow(_ item: DailyPlanItem, completedColumn: Bool) -> some View {
        let status = model.effectivePlanStatus(item)
        return HStack(spacing: 6) {
            Button { model.togglePlanItemCompleted(item.id) } label: {
                Image(systemName: status == .completed ? "checkmark.circle.fill" : status == .running ? "play.circle.fill" : "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status == .completed ? Color.fdGreen : status == .running ? Color.fdPurple : Color.fdMuted)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.planDisplayTitle(item))
                    .font(.system(size: 9.5, weight: .semibold))
                    .strikethrough(status == .completed)
                    .foregroundStyle(status == .completed ? Color.fdMuted : Color.fdInk)
                    .lineLimit(1)
                Text(status == .running ? model.timeText : "\(item.focusMinutes) 分钟")
                    .font(.system(size: 8, weight: .semibold, design: status == .running ? .monospaced : .default))
                    .foregroundStyle(status == .running ? Color.fdCoral : Color.fdMuted)
            }

            Spacer(minLength: 6)

            if status == .running {
                planButton(model.primaryActionTitle) { model.performPrimaryAction() }
            } else if completedColumn {
                planButton("撤销") { model.togglePlanItemCompleted(item.id) }
            } else {
                planButton("开始") { model.startPlanItem(item) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(status == .running ? Color.fdPurpleSoft : Color.fdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.fdLine.opacity(0.9), lineWidth: 1))
    }

    private var quickStartEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("倒计时名称")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("上午专注", text: $quickTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.fdPanel.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("任务")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("英语复习", text: $quickTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.fdPanel.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }

            HStack(spacing: 10) {
                Text("倒计时")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                stepButton("minus") { quickMinutes = max(1, quickMinutes - 5) }
                Spacer()
                Text("\(quickMinutes) 分钟")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.fdInk)
                Spacer()
                stepButton("plus") { quickMinutes = min(180, quickMinutes + 5) }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(Color.fdPanel.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))

            HStack(spacing: 8) {
                Button {
                    model.startFloatingTimer(title: quickTitle, task: quickTask, minutes: quickMinutes)
                    dismiss()
                } label: {
                    Label("开始专注", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 38)
                .background(Color.fdPurple)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    model.configureFloatingTimer(title: quickTitle, task: quickTask, minutes: quickMinutes)
                    WindowManager.shared.showMainWindow(section: .focus)
                    dismiss()
                } label: {
                    Text("打开")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fdPurple)
                .frame(height: 38)
                .background(Color.fdPurpleSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }
        }
    }

    private var runningTimerSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: model.isRest ? "cup.and.saucer.fill" : "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdPurple)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.72))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.floatingTimerTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.fdInk)
                        .lineLimit(1)
                    Text(model.isRest ? "休息 · \(model.timeText)" : "\(model.floatingFocusTaskLabel) · \(model.timeText)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.fdMuted)
                        .lineLimit(1)
                }
                Spacer()
                if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                    planButton(model.primaryActionTitle) { model.performPrimaryAction() }
                }
                if model.phase == .focusRunning || model.phase == .focusPaused {
                    planButton("完成", prominent: true) {
                        model.finishEarly()
                        dismiss()
                    }
                }
                if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                    planButton(model.isRest ? "跳过休息" : "跳过") {
                        model.skipCurrentPhase()
                        dismiss()
                    }
                }
            }
        }
        .padding(10)
        .background(Color.fdPurpleSoft.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.fdLine.opacity(0.8), lineWidth: 1))
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                tabButton(.upcoming, count: pendingPlanItems.count)
                tabButton(.completed, count: completedPlanItems.count)
            }
            .padding(3)
            .background(Color.fdBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.fdLine, lineWidth: 1))

            if model.todayPlanItems.isEmpty {
                emptyPlanState("今天还没有安排任务")
            } else if visiblePlanItems.isEmpty {
                emptyPlanState(selectedTab == .upcoming ? "待完成已经清空" : "还没有完成记录")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visiblePlanItems) { item in
                        planRow(item)
                    }
                }
            }
        }
    }

    private func hydrateQuickFormIfNeeded() {
        guard !didHydrateQuickForm else { return }
        didHydrateQuickForm = true
        quickTitle = model.timerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTask = model.task.trimmingCharacters(in: .whitespacesAndNewlines)
        quickTask = model.activePlanItem == nil ? trimmedTask : ""
        let seconds = model.phase == .focusPaused ? model.displayedSeconds : model.durationSeconds
        quickMinutes = max(1, min(180, Int((seconds / 60).rounded())))
    }

    private func tabButton(_ tab: PlanTab, count: Int) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text("\(tab == .completed ? "今日记录" : tab.title) \(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selectedTab == tab ? Color.fdPurple : Color.fdMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selectedTab == tab ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func emptyPlanState(_ title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: selectedTab == .upcoming ? "checklist" : "checkmark.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.fdPurple)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine.opacity(0.8), lineWidth: 1))
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.fdPurple)
                .frame(width: 26, height: 26)
                .background(Color.fdPurpleSoft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func planRow(_ item: DailyPlanItem) -> some View {
        let status = model.effectivePlanStatus(item)
        return HStack(spacing: 8) {
            Button {
                model.togglePlanItemCompleted(item.id)
            } label: {
                Image(systemName: status == .completed ? "checkmark.circle.fill" : status == .running ? "play.circle.fill" : "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status == .completed ? Color.fdGreen : status == .running ? Color.fdPurple : Color.fdMuted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.planDisplayTitle(item))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status == .completed ? Color.fdMuted : Color.fdInk)
                    .strikethrough(status == .completed)
                    .lineLimit(1)
                if status == .running {
                    Text(model.isRest ? "休息中" : model.timeText)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdCoral)
                } else if status != .completed {
                    Text("专注 \(item.focusMinutes) 分钟")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.fdMuted)
                }
            }

            Spacer(minLength: 6)

            if status == .running {
                planButton(model.primaryActionTitle) {
                    model.performPrimaryAction()
                }
                planButton("完成", prominent: true) {
                    model.togglePlanItemCompleted(item.id)
                }
            } else if status != .completed {
                planButton("开始") {
                    model.startPlanItem(item)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: status == .running ? 54 : 48)
        .background(status == .running ? Color.fdPurpleSoft.opacity(0.72) : Color.fdPanel.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.fdLine, lineWidth: 1)
        )
    }

    private func planButton(
        _ title: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.fdPurple)
            .frame(minWidth: 54)
            .frame(height: 30)
            .background(prominent ? Color.fdPurple : Color.fdPurpleSoft)
            .clipShape(Capsule())
    }
}
