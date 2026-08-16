import AppKit
import Combine
import SwiftUI

// MARK: - 宠物情态（由计时状态映射）

enum PetMood {
    case idle          // 待机（坐姿）
    case focus         // 专注中（工作态）
    case paused        // 暂停
    case rest          // 休息中
    case celebrate     // 完成/庆祝
    // 场景化提醒
    case drink         // 喝水
    case eye           // 护眼远眺
    case stretch       // 起来活动/伸展
    case wave          // 挥手打招呼

    init(phase: TimerPhase) {
        switch phase {
        case .idle: self = .idle
        case .focusRunning: self = .focus
        case .focusPaused, .restPaused: self = .paused
        case .restRunning: self = .rest
        case .focusFinished, .restFinished: self = .celebrate
        }
    }
}

/// 两套素材共用的 19 个语义动作。图片文件名的猫/狗差异只在加载层处理。
enum PetPose: String, CaseIterable {
    case idle
    case idleStand
    case walk
    case question
    case think
    case partySit
    case sleep
    case wave
    case pillow
    case yarn
    case partyStand
    case clipboard
    case pen
    case folder
    case celebrate
    case painter
    case drink
    case eye
    case stretch
}

/// 慢节奏动作编排：根据番茄钟状态选择动作组，避免逐帧换图造成闪烁。
enum PetChoreography {
    static func sequence(for mood: PetMood) -> [PetPose] {
        switch mood {
        case .idle:
            // 陪伴待机覆盖生活化动作；坐姿穿插其中，让整体保持安静。
            return [.idle, .idleStand, .idle, .walk, .wave, .idle, .think, .yarn, .idle, .painter, .pillow]
        case .focus:
            return [.clipboard, .pen, .clipboard, .folder, .think, .painter]
        case .paused:
            return [.question, .idle, .think, .wave]
        case .rest:
            return [.pillow, .sleep, .sleep, .drink, .eye, .stretch, .idle]
        case .celebrate:
            return [.partySit, .partyStand, .celebrate, .wave, .celebrate]
        case .drink:
            return [.drink]
        case .eye:
            return [.eye]
        case .stretch:
            return [.stretch]
        case .wave:
            return [.wave]
        }
    }

    static func pose(for mood: PetMood, time: TimeInterval) -> PetPose {
        let poses = sequence(for: mood)
        let secondsPerPose: TimeInterval
        switch mood {
        case .focus: secondsPerPose = 8
        case .rest: secondsPerPose = 7
        case .celebrate: secondsPerPose = 2.4
        case .drink, .eye, .stretch, .wave: secondsPerPose = 4
        case .idle, .paused: secondsPerPose = 5
        }
        let index = Int(max(0, floor(time / secondsPerPose))) % poses.count
        return poses[index]
    }
}

// MARK: - 动画参数（由时间 + 情态驱动）

struct PetMotion {
    let breath: CGFloat      // 呼吸缩放
    let bob: CGFloat         // 上下浮动
    let jump: CGFloat       // 跳跃高度
    let tilt: Double        // 左右倾斜角度
    let waveAngle: Double   // 摇摆角度（挥手时）

    init(time t: TimeInterval, mood: PetMood, pose: PetPose) {
        let isSleeping = pose == .sleep || pose == .pillow
        let breathPeriod: Double = mood == .focus ? 1.8 : (isSleeping ? 4.2 : 3.0)
        let wave = sin(t * 2 * .pi / breathPeriod)
        breath = 1 + 0.03 * CGFloat(wave)
        bob = CGFloat(wave) * (isSleeping ? 1.5 : 3.0)

        if pose == .walk {
            jump = CGFloat(abs(sin(t * 2 * .pi / 0.62))) * 7
            tilt = sin(t * 2 * .pi / 0.62) * 4
        } else if mood == .celebrate || mood == .drink || mood == .stretch || mood == .eye {
            // 庆祝/场景提醒：跳跃感更强
            let jFreq = mood == .celebrate ? 0.62 : 0.9
            jump = CGFloat(abs(sin(t * 2 * .pi / jFreq))) * (mood == .celebrate ? 14 : 8)
            tilt = sin(t * 2 * .pi / jFreq) * (mood == .celebrate ? 6 : 3)
        } else if mood == .wave {
            jump = CGFloat(abs(sin(t * 2 * .pi / 1.2))) * 6
            tilt = sin(t * 2 * .pi / 1.2) * 4
        } else {
            jump = 0
            tilt = mood == .idle ? sin(t * 2 * .pi / 5.0) * 2 : 0
        }

        // 挥手摇摆（仅 wave 态）
        waveAngle = pose == .wave ? sin(t * 2 * .pi / 0.45) * 16 : 0
    }
}

// MARK: - 姿态 → 图片文件名映射

extension PetMood {
    /// 返回当前情态对应的姿态 key（用于查找 Resources/PetAssets/{species}/ 下的 PNG）
    var poseKey: String {
        switch self {
        case .idle:      "idle"
        case .focus:     "clipboard"     // 专注 = 拿写字板工作
        case .paused:    "question"      // 暂停 = 疑问表情
        case .rest:      "sleep"         // 休息 = 睡觉
        case .celebrate: "celebrate"     // 完成 = 举完成牌
        case .drink:     "drink"         // 喝水
        case .eye:       "eye"           // 护眼
        case .stretch:   "stretch"       // 活动/伸展
        case .wave:      "wave"          // 挥手
        }
    }

    /// 气泡文案
    var bubbleText: String {
        switch self {
        case .idle:      return "嗨，点开始我陪你专注"
        case .focus:     return "专注中"
        case .paused:    return "暂停中"
        case .rest:      return "休息一下吧 💤"
        case .celebrate: return "太棒了，完成啦！🎉"
        case .drink:     return "该喝水啦 💧"
        case .eye:       return "看远处 20 秒 👀"
        case .stretch:   return "起来活动一下 🚶"
        case .wave:      return "你好呀～ 👋"
        }
    }

    /// 由提醒名称映射到对应的场景情态（喝水 / 活动 / 护眼 / 默认挥手）
    static func reminderScene(named name: String) -> PetMood {
        if name.contains("喝水") { return .drink }
        if name.contains("活动") || name.contains("站") { return .stretch }
        if name.contains("远眺") || name.contains("眼") { return .eye }
        return .wave
    }
}

// MARK: - 悬浮窗内容（桌面宠物面板）

struct DesktopPetPanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var currentSceneMood: PetMood? = nil  // 场景提醒覆盖
    @State private var quickTitle = ""
    @State private var quickTask = ""
    @State private var quickMinutes = 25
    @State private var didHydrateQuickForm = false
    @State private var selectedPlanTab: PlanTab = .upcoming

    private var effectiveMood: PetMood {
        if model.completionFeedback != nil { return .celebrate }
        return currentSceneMood ?? PetMood(phase: model.phase)
    }

    private var petDisplaySize: CGFloat {
        PetVisualMetrics.clampedSettingSize(CGFloat(model.settings.petSize))
    }

    private var bubbleText: String { effectiveMood.bubbleText }

    private var pendingPlanItems: [DailyPlanItem] {
        model.todayPlanItems.filter { model.effectivePlanStatus($0) != .completed }
    }

    private var completedPlanItems: [DailyPlanItem] {
        model.todayPlanItems.filter { model.effectivePlanStatus($0) == .completed }
    }

    private var visiblePlanItems: [DailyPlanItem] {
        selectedPlanTab == .upcoming ? pendingPlanItems : completedPlanItems
    }

    /// AppKit 面板尺寸与 SwiftUI 内容必须共用同一个展开状态。
    /// 如果另存一份局部状态，提醒/完成回调只收起窗口时，
    /// 就会把展开内容塞进收起态的 248pt 面板里。
    private var isBubbleExpanded: Bool {
        model.petQuickControlsExpanded || model.completionFeedback != nil
    }

    var body: some View {
        VStack(spacing: PetVisualMetrics.panelContentSpacing) {
            Group {
                if isBubbleExpanded {
                    bubbleContent
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    PetTimerBubbleView {
                        showControls()
                    }
                    .environmentObject(model)
                }
            }
            .frame(
                    height: isBubbleExpanded
                        ? bubbleHeight
                        : 68,
                alignment: .bottom
            )

            petAvatar
        }
        // Keep animated paws, shadows and bounce motion away from the NSPanel edge.
        // Without this inset AppKit clips the raster exactly at the window boundary.
        .padding(.bottom, PetVisualMetrics.panelBottomSafetyInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onReceive(model.$petInteractionToken.dropFirst()) { _ in
            showControls()
        }
        .onReceive(model.$activePlanReminderID.dropFirst()) { id in
            if id != nil { showControls() }
        }
        .onReceive(model.$activeReminderIDs.dropFirst()) { ids in
            if !ids.isEmpty { showControls() }
        }
        .onReceive(model.$petReminderToken.dropFirst()) { _ in
            guard let scene = model.petReminderScene else { return }
            currentSceneMood = scene
            showControls()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [scene] in
                // 正式提醒保持到用户完成或稍后；只有场景演示才自动收起。
                guard currentSceneMood == scene, model.activeReminderIDs.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    currentSceneMood = nil
                    hideBubble()
                }
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if model.completionFeedback != nil {
            completionBubble
        } else if !model.activeReminderIDs.isEmpty || model.activePlanReminderID != nil {
            PetReminderBubbleView(onClose: hideBubble)
                .environmentObject(model)
        } else {
            MinimalFloatingFocusPanelView(onClose: hideBubble)
                .environmentObject(model)
        }
    }

    /// 专注完成庆祝气泡：展示本轮成果，并提供「查看记录」（打开计划页已完成 Tab）
    /// 与「撤销」（删除该次完成记录并回到空闲）两个动作。
    @ViewBuilder
    private var completionBubble: some View {
        if let feedback = model.completionFeedback {
            VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.fdGreen)
                Text("\(feedback.task)已完成")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
                Spacer()
                collapseBubbleButton {
                    model.dismissCompletionFeedback()
                    hideBubble()
                }
            }

            HStack(spacing: 6) {
                Text("\(feedback.minutes) 分钟")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fdGreen)
                Spacer()
                Text("今日第 \(model.todayCompletedSessionCount) 项 · 累计 \(model.todayCompletedSessionMinutes) 分钟")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fdMuted)
            }

            HStack(spacing: 7) {
                bubbleButton("查看记录", prominent: true) {
                    model.requestPlanDestination(.completed, date: feedback.endedAt)
                    WindowManager.shared.showMainWindow(section: .dailyPlan)
                    model.dismissCompletionFeedback()
                    hideBubble()
                }
                bubbleButton("撤销") {
                    model.undoCompletedSession(feedback.id)
                    model.selectedSection = .focus
                    hideBubble()
                }
            }
        }
        .padding(9)
        .frame(width: bubbleWidth)
        .background(Color.fdPanel.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.fdGreen.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
        }
    }

    private var controlTitle: String {
        if !model.activeReminderIDs.isEmpty {
            if model.activeReminderNames.count == 1, let name = model.activeReminderNames.first {
                return "\(name)提醒"
            }
            return "需要处理的 \(model.activeReminderIDs.count) 项提醒"
        }
        if model.activePlanReminderItem != nil { return "任务开始提醒" }
        switch model.phase {
        case .idle:
            return model.todayPlanItems.isEmpty
                ? "开始一轮专注"
                : "今天做什么"
        case .focusRunning: return "专注中 · \(model.timeText)"
        case .focusPaused: return "已暂停 · \(model.timeText)"
        case .restRunning: return "休息中 · \(model.timeText)"
        case .restPaused: return "休息已暂停 · \(model.timeText)"
        case .focusFinished: return "专注完成"
        case .restFinished: return "休息完成"
        }
    }

    private var planChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            floatingWorkbenchTimerStrip

            HStack(alignment: .top, spacing: 6) {
                planColumn(
                    title: "待完成",
                    items: pendingPlanItems,
                    emptyTitle: "待完成已经清空",
                    completedColumn: false
                )
                planColumn(
                    title: "已完成",
                    items: completedPlanItems,
                    emptyTitle: "还没有完成记录",
                    completedColumn: true
                )
            }
        }
        .onAppear(perform: hydrateQuickFormIfNeeded)
    }

    private var runningPlanWorkbench: some View {
        VStack(alignment: .leading, spacing: 6) {
            runningWorkbenchTimerStrip

            HStack(alignment: .top, spacing: 6) {
                planColumn(
                    title: "待完成",
                    items: pendingPlanItems,
                    emptyTitle: "待完成已经清空",
                    completedColumn: false
                )
                planColumn(
                    title: "已完成",
                    items: completedPlanItems,
                    emptyTitle: "还没有完成记录",
                    completedColumn: true
                )
            }
        }
    }

    private var floatingWorkbenchTimerStrip: some View {
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
                .frame(width: 46, height: 4)
            }
            .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("倒计时名称")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("上午专注", text: $quickTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 26)
                    .background(Color.fdPanel.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("任务")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                TextField("英语复习", text: $quickTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 26)
                    .background(Color.fdPanel.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
            }
            .frame(width: 56)

            VStack(spacing: 3) {
                quickMinuteButton("minus") { quickMinutes = max(1, quickMinutes - 5) }
                quickMinuteButton("plus") { quickMinutes = min(180, quickMinutes + 5) }
            }
            .frame(width: 20)

            Button {
                model.startFloatingTimer(title: quickTitle, task: quickTask, minutes: quickMinutes)
                hideBubble()
            } label: {
                Text("开始")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 26)
                    .background(Color.fdPurple)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color.fdPanel.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }

    private var runningWorkbenchTimerStrip: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.timeText)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fdLine)
                        Capsule().fill(Color.fdPurple).frame(width: max(8, proxy.size.width * model.progress))
                    }
                }
                .frame(width: 46, height: 4)
            }
            .frame(width: 54, alignment: .leading)

            Image(systemName: model.isRest ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdPurple)
                .frame(width: 22, height: 22)
                .background(Color.fdPurpleSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(model.isRest ? "休息" : model.floatingTimerTitle)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                    .lineLimit(1)
                Text(model.isRest ? "休息中" : model.floatingFocusTaskLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.fdInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                miniPlanButton(model.primaryActionTitle) { model.performPrimaryAction() }
            }
            if model.phase == .focusRunning || model.phase == .focusPaused {
                miniPlanButton("完成") {
                    model.finishEarly()
                    hideBubble()
                }
            }
            if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                miniPlanButton(model.isRest ? "跳过休息" : "跳过") {
                    model.skipCurrentPhase()
                    hideBubble()
                }
            }
        }
        .padding(6)
        .background(Color.fdPurpleSoft.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }

    private func planColumn(
        title: String,
        items: [DailyPlanItem],
        emptyTitle: String,
        completedColumn: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.fdInk)
                Rectangle()
                    .fill(Color.fdLine)
                    .frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 5) {
                    if items.isEmpty {
                        Text(emptyTitle)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color.fdMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Color.fdBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    ForEach(items) { item in
                        planWorkbenchRow(item, completedColumn: completedColumn)
                    }
                }
            }
            .frame(maxHeight: 52)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .top)
        .background(Color.fdPanel.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }

    private func planWorkbenchRow(_ item: DailyPlanItem, completedColumn: Bool) -> some View {
        let status = model.effectivePlanStatus(item)
        return HStack(spacing: 5) {
            Button { model.togglePlanItemCompleted(item.id) } label: {
                Image(systemName: status == .completed ? "checkmark.circle.fill" : status == .running ? "play.circle.fill" : "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status == .completed ? Color.fdGreen : status == .running ? Color.fdPurple : Color.fdMuted)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.planDisplayTitle(item))
                    .font(.system(size: 9, weight: .semibold))
                    .strikethrough(status == .completed)
                    .foregroundStyle(status == .completed ? Color.fdMuted : Color.fdInk)
                    .lineLimit(1)
                Text(status == .running ? model.timeText : "\(item.focusMinutes) 分钟")
                    .font(.system(size: 7.5, weight: .semibold, design: status == .running ? .monospaced : .default))
                    .foregroundStyle(status == .running ? Color.fdCoral : Color.fdMuted)
            }

            Spacer(minLength: 4)

            if status == .running {
                miniPlanButton(model.primaryActionTitle) { model.performPrimaryAction() }
            } else if completedColumn {
                miniPlanButton("撤销") { model.togglePlanItemCompleted(item.id) }
            } else {
                miniPlanButton("开始") { model.startPlanItem(item) }
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 28)
        .background(status == .running ? Color.fdPurpleSoft : Color.fdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdLine.opacity(0.9), lineWidth: 1))
    }

    private var timerControlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.isRest ? "cup.and.saucer.fill" : "timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdPurple)
                    .frame(width: 30, height: 30)
                    .background(Color.fdPurpleSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isRest ? "休息" : model.floatingTimerTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fdInk)
                        .lineLimit(1)
                    Text(model.isRest ? model.timeText : "\(model.floatingFocusTaskLabel) · \(model.timeText)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.fdInk)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 7) {
                if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                    bubbleButton(model.primaryActionTitle, prominent: true) {
                        model.performPrimaryAction()
                    }
                }
                if model.phase == .focusRunning || model.phase == .focusPaused {
                    bubbleButton("完成") {
                        model.finishEarly()
                        hideBubble()
                    }
                }
                if model.phase == .focusRunning || model.phase == .focusPaused || model.phase == .restRunning || model.phase == .restPaused {
                    bubbleButton(model.isRest ? "跳过休息" : "跳过") {
                        model.skipCurrentPhase()
                        hideBubble()
                    }
                } else {
                    bubbleButton("打开") {
                        WindowManager.shared.showMainWindow(section: .focus)
                        hideBubble()
                    }
                }
            }

            if !model.todayPlanItems.isEmpty {
                Button {
                    model.requestPlanDestination(.upcoming, date: Date())
                    WindowManager.shared.showMainWindow(section: .dailyPlan)
                    hideBubble()
                } label: {
                    Label("今日计划 \(model.todayCompletedPlanItems)/\(model.todayPlanItems.count)", systemImage: "calendar")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fdPurple)
                .padding(.vertical, 6)
                .background(Color.fdPurpleSoft.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("倒计时名称", text: $quickTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.fdBackground)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.fdLine, lineWidth: 1))

            TextField("任务", text: $quickTask)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.fdBackground)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.fdLine, lineWidth: 1))

            HStack(spacing: 7) {
                Text("倒计时")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.fdMuted)
                Spacer()
                quickMinuteButton("minus") { quickMinutes = max(1, quickMinutes - 5) }
                Text("\(quickMinutes) 分钟")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fdInk)
                    .frame(minWidth: 54)
                quickMinuteButton("plus") { quickMinutes = min(180, quickMinutes + 5) }
            }

            HStack(spacing: 7) {
                bubbleButton("开始专注", prominent: true) {
                    model.startFloatingTimer(title: quickTitle, task: quickTask, minutes: quickMinutes)
                    hideBubble()
                }
                bubbleButton("打开") {
                    model.configureFloatingTimer(title: quickTitle, task: quickTask, minutes: quickMinutes)
                    WindowManager.shared.showMainWindow(section: .focus)
                    hideBubble()
                }
            }
        }
        .onAppear(perform: hydrateQuickFormIfNeeded)
    }

    private var currentPlanItem: DailyPlanItem? {
        if let activePlanItemID = model.activePlanItemID,
           let active = model.todayPlanItems.first(where: { $0.id == activePlanItemID }) {
            return active
        }
        return model.todayPlanItems.first { model.effectivePlanStatus($0) != .completed }
    }

    private var isPlanChecklistContext: Bool {
        model.activeReminderIDs.isEmpty
            && model.activePlanReminderItem == nil
            && model.phase == .idle
            && !model.todayPlanItems.isEmpty
    }

    private var isRunningPlanWorkbenchContext: Bool {
        model.activeReminderIDs.isEmpty
            && model.activePlanReminderItem == nil
            && model.phase != .idle
            && !model.todayPlanItems.isEmpty
    }

    private var bubbleHeight: CGFloat {
        if model.completionFeedback != nil { return 140 }
        // MinimalFloatingFocusPanelView can switch in place to the Today Plan
        // page. Reserve that page's full height so its header is never clipped.
        return FloatingTodayPlanMetrics.height
    }

    private var bubbleWidth: CGFloat {
        if model.completionFeedback != nil { return 248 }
        return 270
    }

    private var showsCollapsedPlanBoard: Bool {
        isPlanChecklistContext && model.petPlanListCollapsed
    }

    private struct PetBoardContent {
        let title: String
        let timeText: String
    }

    private var petBoardContent: PetBoardContent? {
        // 运行或暂停时，实时计时永远高于计划预览。
        if let active = model.activeTimerPresentation {
            return PetBoardContent(title: active.title, timeText: active.timeText)
        }
        // 只有完全空闲时，才显示下一项计划的设定时长。
        guard model.phase == .idle,
              showsCollapsedPlanBoard,
              let item = currentPlanItem else { return nil }
        return PetBoardContent(
            title: model.planDisplayTitle(item),
            timeText: String(format: "%02d:00", item.focusMinutes)
        )
    }

    private var petAvatar: some View {
        return SpritePetAvatarView(
            species: model.settings.petSpecies,
            mood: effectiveMood,
            size: petDisplaySize,
            showBoard: false,
            boardText: model.timeText,
            boardTitle: nil,
            boardPrimaryTitle: nil,
            onBoardPrimary: nil,
            onBoardOpenList: nil
        )
    }

    private func miniPlanButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Color.fdPurple)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.fdPurpleSoft).clipShape(Capsule())
    }

    private func hydrateQuickFormIfNeeded() {
        guard !didHydrateQuickForm else { return }
        didHydrateQuickForm = true
        quickTitle = model.timerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        quickTask = model.task.trimmingCharacters(in: .whitespacesAndNewlines)
        quickMinutes = max(1, min(180, Int((model.durationSeconds / 60).rounded())))
    }

    private func quickMinuteButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.fdPurple)
                .frame(width: 24, height: 24)
                .background(Color.fdPurpleSoft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func petPlanTabButton(_ tab: PlanTab, count: Int) -> some View {
        Button {
            selectedPlanTab = tab
        } label: {
            Text("\(tab.title) \(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(selectedPlanTab == tab ? Color.fdPurple : Color.fdMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(selectedPlanTab == tab ? Color.fdPanel : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func estimatedFinish(for item: DailyPlanItem) -> String {
        Date().addingTimeInterval(TimeInterval(item.focusMinutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private func reminderSymbol(for name: String) -> String {
        switch PetMood.reminderScene(named: name) {
        case .drink: "drop.fill"
        case .eye: "eye.fill"
        case .stretch: "figure.stand"
        default: "bell.fill"
        }
    }

    private var canEditMinutes: Bool {
        model.mode == .countdown && (model.phase == .idle || model.phase == .focusPaused)
    }

    private var editableMinutes: Int {
        max(1, Int((model.phase == .focusPaused ? model.displayedSeconds : model.durationSeconds) / 60))
    }

    private func minuteButton(_ title: String, delta: Int) -> some View {
        Button(title) {
            let next = max(1, min(180, editableMinutes + delta))
            if model.phase == .focusPaused {
                model.replacePausedCountdownDuration(next)
            } else {
                model.selectDuration(next)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Color.fdPurple)
        .frame(width: 24, height: 24)
        .background(Color.fdPurpleSoft)
        .clipShape(Circle())
    }

    private func bubbleButton(
        _ title: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.fdPurple)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(prominent ? Color.fdPurple : Color.fdPurpleSoft)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .frame(maxWidth: .infinity)
    }

    private func collapseBubbleButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.fdMuted)
                .frame(width: 20, height: 20)
                .background(Color.fdBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("收起到宠物")
        .accessibilityLabel("收起到宠物")
    }

    private func hideBubble() {
        withAnimation(.easeOut(duration: 0.25)) {
            model.petQuickControlsExpanded = false
        }
        model.petPlanListCollapsed = true
    }

    private func closeScene() {
        currentSceneMood = nil
        hideBubble()
    }

    private func showControls() {
        if isPlanChecklistContext || isRunningPlanWorkbenchContext {
            model.petPlanListCollapsed = false
        }
        withAnimation(.spring(duration: 0.3)) {
            model.petQuickControlsExpanded = true
        }
    }

    private func triggerScene(_ mood: PetMood) {
        currentSceneMood = mood
        showControls()
        // 3 秒后恢复到正常状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.35)) {
                currentSceneMood = nil
                hideBubble()
            }
        }
    }
}

private struct PetReminderBubbleView: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fdCoral)
                    .frame(width: 28, height: 28)
                    .background(Color.fdCoral.opacity(0.12))
                    .clipShape(Circle())
                Text("提醒")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fdInk)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.fdMuted)
                        .frame(width: 24, height: 24)
                        .background(Color.fdBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(model.activeReminderNames, id: \.self) { name in
                    Label(name, systemImage: "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.fdInk)
                }
                if let item = model.activePlanReminderItem {
                    Label(item.title, systemImage: "calendar.badge.clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.fdInk)
                }
            }

            HStack(spacing: 6) {
                if model.activePlanReminderID != nil {
                    petReminderButton("10 分钟后") {
                        model.snoozePlanReminder()
                        onClose()
                    }
                    petReminderButton("跳过") {
                        model.dismissPlanReminder()
                        onClose()
                    }
                    petReminderButton("开始", prominent: true) {
                        model.startActivePlanReminder()
                        onClose()
                    }
                } else {
                    petReminderButton("10 分钟后") {
                        model.snoozeActiveReminders()
                        onClose()
                    }
                    petReminderButton("跳过") {
                        model.resolveActiveReminders(completed: false)
                        onClose()
                    }
                    petReminderButton("完成", prominent: true) {
                        model.resolveActiveReminders(completed: true)
                        onClose()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .background(Color.fdPanel.opacity(0.99))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.fdCoral.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private func petReminderButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.fdPurple)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(prominent ? Color.fdPurple : Color.fdPurpleSoft)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct PetTimerBubbleView: View {
    @EnvironmentObject private var model: AppModel
    let onOpen: () -> Void

    private var displayTime: String {
        model.phase == .idle ? String(format: "%02d:00", model.settings.focusMinutes) : model.timeText
    }

    private var displayName: String {
        if model.isRest { return "休息" }
        if !model.floatingFocusTaskLabel.isEmpty { return model.floatingFocusTaskLabel }
        return "专注"
    }

    private var accent: Color { model.isRest ? Color.fdGreen : Color.fdPurple }

    private var actionTitle: String {
        switch model.phase {
        case .idle, .restFinished: "开始"
        case .focusRunning, .restRunning: "暂停"
        case .focusPaused, .restPaused: "继续"
        case .focusFinished: "休息"
        }
    }

    private var actionIcon: String {
        switch model.phase {
        case .focusRunning, .restRunning: "pause.fill"
        case .focusFinished: "cup.and.saucer.fill"
        default: "play.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onOpen) {
                VStack(spacing: 1) {
                    Text(displayTime)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fdInk)
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.isRest ? Color.fdGreen : Color.fdMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 96)
                }
                .frame(width: 108, height: 54)
            }
            .buttonStyle(.plain)

            Button {
                model.performPrimaryAction()
            } label: {
                Label(actionTitle, systemImage: actionIcon)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(model.primaryActionTitle)
            .accessibilityLabel(model.primaryActionTitle)
        }
        .padding(.horizontal, 7)
        .frame(height: 68)
        .background(Color.fdPanel.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.28), lineWidth: 1.5))
        .shadow(color: accent.opacity(0.14), radius: 9, y: 4)
        .overlay(alignment: .bottom) {
            PetBubblePointer()
                .fill(Color.fdPanel.opacity(0.98))
                .frame(width: 14, height: 8)
                .offset(y: 7)
        }
        .help("展开专注控制面板")
    }
}

private struct PetBubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 7, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + 7, y: 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - 精灵贴纸宠物视图（核心：从 Bundle 加载 PNG）

enum PetVisualMetrics {
    static let minimumSettingSize: CGFloat = 88
    static let maximumSettingSize: CGFloat = 220
    static let panelContentSpacing: CGFloat = 5
    static let panelBottomSafetyInset: CGFloat = 28
    static let panelAnimationOverflow: CGFloat = 10

    static func clampedSettingSize(_ settingSize: CGFloat) -> CGFloat {
        min(maximumSettingSize, max(minimumSettingSize, settingSize))
    }

    static func petPanelVerticalSafetyArea() -> CGFloat {
        panelContentSpacing + panelBottomSafetyInset + panelAnimationOverflow
    }

    /// “宠物大小”表示最终可见主体的参考边长，而不是 PNG 原始画布尺寸。
    static func visibleSide(for settingSize: CGFloat) -> CGFloat {
        settingSize * 0.82
    }

    /// 所有姿态共用同一个固定画布。额外空间用于容纳跳跃、呼吸、旋转和阴影，
    /// 避免睡觉/站立等不同宽高的素材让悬浮窗在动画中改变布局。
    static func avatarCanvasHeight(for settingSize: CGFloat) -> CGFloat {
        settingSize + 44
    }

    /// 倒计时牌与宠物使用同一尺寸基准；主体每缩放 1 pt，牌子同步缩放。
    /// 牌子明显宽于宠物可见主体，并增加纵向留白，避免标题与数字显得拥挤。
    static func countdownBoardWidth(for settingSize: CGFloat) -> CGFloat {
        settingSize * 0.98
    }

    static func countdownBoardHeight(for settingSize: CGFloat) -> CGFloat {
        countdownBoardWidth(for: settingSize) * 0.286
    }

    /// 用 alpha 可见面积补偿不同姿态的视觉大小。
    /// 透明边界裁剪只能统一外接框；跑步、睡觉、举手和带道具姿态的
    /// 有效图形面积仍不同，因此需要以统一的“墨迹密度”进行二次缩放。
    static func perceivedPoseScale(
        opaquePixelCount: Int,
        croppedSize: CGSize
    ) -> CGFloat {
        let maxEdge = max(croppedSize.width, croppedSize.height)
        guard opaquePixelCount > 0, maxEdge > 0 else { return 1 }
        let density = CGFloat(opaquePixelCount) / (maxEdge * maxEdge)
        let targetDensity: CGFloat = 0.64
        return min(1.25, max(0.92, sqrt(targetDensity / density)))
    }

    static func visibleContentSize(
        imageSize: CGSize,
        settingSize: CGFloat,
        perceivedScale: CGFloat = 1
    ) -> CGSize {
        let side = visibleSide(for: settingSize) * perceivedScale
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: side, height: side)
        }
        let aspectRatio = imageSize.width / imageSize.height
        if aspectRatio >= 1 {
            return CGSize(width: side, height: side / aspectRatio)
        }
        return CGSize(width: side * aspectRatio, height: side)
    }

    /// 当前姿态经过面积补偿、呼吸缩放与旋转后的真实可见顶部。
    static func visibleTopExtent(
        imageSize: CGSize,
        settingSize: CGFloat,
        perceivedScale: CGFloat,
        horizontalScale: CGFloat,
        verticalScale: CGFloat,
        rotationDegrees: Double
    ) -> CGFloat {
        let side = visibleSide(for: settingSize)
        let fitted = visibleContentSize(
            imageSize: imageSize,
            settingSize: settingSize
        )
        let outerInset = (settingSize - side) / 2
        let centerY = (outerInset + perceivedScale * side / 2) * verticalScale
        let halfWidth = fitted.width * perceivedScale * horizontalScale / 2
        let halfHeight = fitted.height * perceivedScale * verticalScale / 2
        let radians = abs(rotationDegrees) * .pi / 180
        return centerY * cos(radians)
            + halfHeight * cos(radians)
            + halfWidth * sin(radians)
    }

    /// 牌子边框到宠物最高可见像素的净距离。
    static func countdownBoardGap(for settingSize: CGFloat) -> CGFloat {
        min(18, max(12, settingSize * 0.10))
    }

    static func countdownBoardOffset(
        for settingSize: CGFloat,
        visibleTopExtent: CGFloat
    ) -> CGFloat {
        // 宠物本体固定向上偏移 6 pt；牌子与跳跃、上下浮动同步。
        visibleTopExtent + 6 + countdownBoardGap(for: settingSize)
    }

    static func reminderCardWidth(for settingSize: CGFloat) -> CGFloat {
        min(248, max(208, settingSize * 1.12))
    }
}

struct SpritePetAvatarView: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat
    /// 专注/休息进行中，宠物头顶举起倒计时牌子显示 MM:SS
    var showBoard: Bool = false
    var boardText: String = ""
    var boardTitle: String? = nil
    var boardPrimaryTitle: String? = nil
    var onBoardPrimary: (() -> Void)? = nil
    var onBoardOpenList: (() -> Void)? = nil

    /// 从 Bundle 加载当前动作图片（SwiftPM 资源已 flatten，直接用文件名加载）。
    private func poseAsset(for pose: PetPose) -> PetRasterAsset? {
        let fname = fileNameForPose(pose.rawValue)
        if let asset = PetImageCache.asset(named: fname) { return asset }
        // fallback: 尝试加载 idle 姿态
        return PetImageCache.asset(named: fileNameForPose("idle"))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pose = PetChoreography.pose(for: mood, time: t)
            let motion = PetMotion(time: t, mood: mood, pose: pose)
            let asset = poseAsset(for: pose)
            let visibleContentSize = visibleContentSize(for: asset)
            let visibleTopExtent = asset.map {
                PetVisualMetrics.visibleTopExtent(
                    imageSize: $0.image.size,
                    settingSize: size,
                    perceivedScale: $0.perceivedScale,
                    horizontalScale: 2 - motion.breath,
                    verticalScale: motion.breath,
                    rotationDegrees: motion.tilt + motion.waveAngle * 0.12
                )
            } ?? PetVisualMetrics.visibleSide(for: size)
            let boardOffset = PetVisualMetrics.countdownBoardOffset(
                for: size,
                visibleTopExtent: visibleTopExtent
            )
            ZStack(alignment: .bottom) {
                shadow(motion: motion, visibleWidth: visibleContentSize.width)
                spriteBody(pose: pose, asset: asset)
                    .frame(width: size, height: size)
                    .scaleEffect(x: 2 - motion.breath, y: motion.breath, anchor: .bottom)
                    .rotationEffect(.degrees(motion.tilt + motion.waveAngle * 0.12), anchor: .bottom)
                    .offset(y: -motion.jump - motion.bob - 6)
                overlays(pose: pose, time: t)
                if showBoard {
                    CountdownBoardView(
                        text: boardText,
                        title: boardTitle,
                        primaryTitle: boardPrimaryTitle,
                        size: size,
                        onPrimary: onBoardPrimary,
                        onOpenList: onBoardOpenList
                    )
                        // 倒计时牌放在宠物头顶，避免遮住身体和动作素材。
                        .offset(
                            y: -motion.jump
                                - motion.bob
                                - boardOffset
                        )
                }
            }
            // 不带牌子时使用固定安全画布，姿态切换不再推动父窗口重新布局。
            .frame(
                width: size + 44,
                height: showBoard
                    ? boardOffset + PetVisualMetrics.countdownBoardHeight(for: size) + 12
                    : PetVisualMetrics.avatarCanvasHeight(for: size),
                alignment: .bottom
            )
            .animation(.easeInOut(duration: 0.35), value: pose)
        }
    }

    @ViewBuilder
    private func spriteBody(pose: PetPose, asset: PetRasterAsset?) -> some View {
        if let asset {
            Image(nsImage: asset.image)
                .resizable()
                .scaledToFit()
                .frame(
                    width: PetVisualMetrics.visibleSide(for: size),
                    height: PetVisualMetrics.visibleSide(for: size)
                )
                .scaleEffect(asset.perceivedScale, anchor: .bottom)
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 6)
                .id(pose)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            // 加载失败时的占位
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(Color.fdPurpleSoft)
                .frame(width: size * 0.86, height: size * 0.86)
                .overlay(
                    VStack(spacing: 5) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: size * 0.22, weight: .medium))
                        Text(species.title)
                            .font(.system(size: max(9, size * 0.1), weight: .medium))
                    }
                    .foregroundStyle(Color.fdPurple)
                )
        }
    }

    private func visibleContentSize(for asset: PetRasterAsset?) -> CGSize {
        guard let asset else {
            let side = PetVisualMetrics.visibleSide(for: size)
            return CGSize(width: side, height: side)
        }
        return PetVisualMetrics.visibleContentSize(
            imageSize: asset.image.size,
            settingSize: size,
            perceivedScale: asset.perceivedScale
        )
    }

    private func shadow(motion: PetMotion, visibleWidth: CGFloat) -> some View {
        Ellipse()
            .fill(Color.black.opacity(0.13))
            .frame(
                width: visibleWidth * 0.62 * (1 - motion.jump / 55),
                height: size * 0.1
            )
            .blur(radius: 1.5)
    }

    @ViewBuilder
    private func overlays(pose: PetPose, time t: TimeInterval) -> some View {
        if pose == .sleep || pose == .pillow {
            SleepZzzView(time: t, size: size)
                .offset(x: size * 0.46, y: -size * 0.66)
        }
        if pose == .celebrate || pose == .partySit || pose == .partyStand {
            SparklesView(time: t, size: size)
                .offset(y: -size * 0.9)
        }
    }

    /// 宠物举起的倒计时牌子（专注/休息进行中显示 MM:SS）
    private struct CountdownBoardView: View {
        let text: String
        let title: String?
        let primaryTitle: String?
        let size: CGFloat
        let onPrimary: (() -> Void)?
        let onOpenList: (() -> Void)?

        var body: some View {
            let boardWidth = PetVisualMetrics.countdownBoardWidth(for: size)
            let boardHeight = PetVisualMetrics.countdownBoardHeight(for: size)
            let boardScale = boardHeight / 39
            let boardCornerRadius = boardHeight * 0.32
            Group {
                if let title {
                    HStack(spacing: 7 * boardScale) {
                        Image(systemName: "timer")
                            .font(.system(size: 12 * boardScale, weight: .semibold))
                            .foregroundStyle(Color.fdPurple)
                            .frame(width: 21 * boardScale, height: 21 * boardScale)
                            .background(Color.fdPurpleSoft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1 * boardScale) {
                            Text(title)
                                .font(.system(size: 9 * boardScale, weight: .semibold))
                                .foregroundStyle(Color.fdInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(text)
                                .font(.system(size: 14 * boardScale, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.fdInk)
                        }
                    }
                    .padding(.horizontal, 10 * boardScale)
                    .frame(width: boardWidth, height: boardHeight)
                } else {
                    HStack(spacing: 7 * boardScale) {
                        Image(systemName: "timer")
                            .font(.system(size: 12 * boardScale, weight: .semibold))
                            .foregroundStyle(Color.fdPurple)
                        Text(text)
                            .font(.system(size: 15 * boardScale, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.fdInk)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(width: boardWidth, height: boardHeight)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous)
                    .fill(Color.fdPanel.opacity(0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous)
                    .stroke(
                        Color.fdPurple.opacity(0.65),
                        lineWidth: max(1.2, 1.5 * boardScale)
                    )
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: max(3, 4 * boardScale),
                y: max(1.5, 2 * boardScale)
            )
        }

    }

    /// 姿态 key → 完整文件名（带物种后缀，SwiftPM 资源已 flatten 到 bundle 根目录）
    /// 注意：猫/狗部分文件名前缀不同（cat 用 thinking_of_fish / completed_sign，dog 用 thinking / completed）
    private func fileNameForPose(_ poseKey: String) -> String {
        let catMap: [String: String] = [
            "idle": "12_sitting",
            "idleStand": "01_standing",
            "walk": "02_running",
            "question": "03_question",
            "think": "04_thinking_of_fish",
            "partySit": "05_party_hat_sitting",
            "sleep": "06_sleeping",
            "wave": "07_waving",
            "pillow": "08_pillow",
            "yarn": "09_yarn_ball",
            "partyStand": "10_party_hat_standing",
            "clipboard": "11_clipboard",
            "pen": "13_pen",
            "folder": "14_folder",
            "celebrate": "15_completed_sign",
            "painter": "16_painter",
            "drink": "17_drinking_water",
            "eye": "18_eye_relaxation",
            "stretch": "19_stretching",
        ]
        let dogMap: [String: String] = [
            "idle": "12_sitting",
            "idleStand": "01_standing",
            "walk": "02_running",
            "question": "03_question",
            "think": "04_thinking",
            "partySit": "05_party_hat_sitting",
            "sleep": "06_sleeping",
            "wave": "07_waving",
            "pillow": "08_pillow",
            "yarn": "09_yarn",
            "partyStand": "10_party_hat_standing",
            "clipboard": "11_clipboard",
            "pen": "13_pen",
            "folder": "14_folder",
            "celebrate": "15_completed",
            "painter": "16_painter",
            "drink": "17_drinking",
            "eye": "18_eye_relax",
            "stretch": "19_stretching",
        ]
        let base = (species == .cat ? catMap : dogMap)[poseKey] ?? "12_sitting"
        return base + "_\(species == .cat ? "cat" : "dog")"
    }
}

@MainActor
private enum PetImageCache {
    private static var assets: [String: PetRasterAsset] = [:]
    private static var missingNames: Set<String> = []
    private static let resourceBundle: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(
               url: resources.appendingPathComponent("FocusDockMac_FocusDockMac.bundle", isDirectory: true)
           ) {
            return bundle
        }
        return Bundle.module
    }()

    static func asset(named name: String) -> PetRasterAsset? {
        if let asset = assets[name] { return asset }
        guard !missingNames.contains(name),
              let url = resourceBundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            missingNames.insert(name)
            return nil
        }
        let normalized = image.normalizedPetRaster()
        assets[name] = normalized
        return normalized
    }
}

struct PetRasterAsset {
    let image: NSImage
    let perceivedScale: CGFloat
}

extension NSImage {
    /// 猫素材使用 768×512 横向画布，狗素材使用 512×512 方形画布。
    /// 先裁掉透明边距，再交给 `scaledToFit`，可让相同设置值对应相近的可见主体尺寸。
    func normalizedPetRaster(alphaThreshold: UInt8 = 64) -> PetRasterAsset {
        var proposedRect = CGRect(origin: .zero, size: size)
        guard let source = cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return PetRasterAsset(image: self, perceivedScale: 1)
        }

        let width = source.width
        let height = source.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return PetRasterAsset(image: self, perceivedScale: 1)
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return PetRasterAsset(image: self, perceivedScale: 1)
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var opaquePixelCount = 0

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let alpha = pixels[rowOffset + x * bytesPerPixel + 3]
                guard alpha > alphaThreshold else { continue }
                opaquePixelCount += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY, let rendered = context.makeImage() else {
            return PetRasterAsset(image: self, perceivedScale: 1)
        }

        let padding = max(2, Int(Double(max(width, height)) * 0.008))
        let cropMinX = max(0, minX - padding)
        let cropMinY = max(0, minY - padding)
        let cropMaxX = min(width - 1, maxX + padding)
        let cropMaxY = min(height - 1, maxY + padding)
        let cropRect = CGRect(
            x: cropMinX,
            y: cropMinY,
            width: cropMaxX - cropMinX + 1,
            height: cropMaxY - cropMinY + 1
        )

        guard let cropped = rendered.cropping(to: cropRect) else {
            return PetRasterAsset(image: self, perceivedScale: 1)
        }
        let normalizedImage = NSImage(
            cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height)
        )
        return PetRasterAsset(
            image: normalizedImage,
            perceivedScale: PetVisualMetrics.perceivedPoseScale(
                opaquePixelCount: opaquePixelCount,
                croppedSize: normalizedImage.size
            )
        )
    }
}

// MARK: - 设置页预览用宠物视图（兼容 SettingsView 中调用）

/// 兼容旧接口：设置页预览区仍可用 PetAvatarView 调用，内部委托给 SpritePetAvatarView
struct PetAvatarView: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat
    var emoji: String = ""
    var imagePath: String? = nil
    var tint: Color = .fdPurple

    var body: some View {
        SpritePetAvatarView(species: species, mood: mood, size: size)
    }
}

// MARK: - 情态装饰

private struct SleepZzzView: View {
    let time: TimeInterval
    let size: CGFloat

    var body: some View {
        ZStack {
            zzz(offsetPhase: 0)
            zzz(offsetPhase: 1.2)
        }
    }

    private func zzz(offsetPhase: Double) -> some View {
        let p = ((time + offsetPhase).truncatingRemainder(dividingBy: 2.4)) / 2.4
        return Text("z")
            .font(.system(size: size * 0.16 * (0.7 + p * 0.5), weight: .bold, design: .rounded))
            .foregroundStyle(Color.fdPurple.opacity(1 - p))
            .offset(x: p * size * 0.12, y: -p * size * 0.22)
    }
}

private struct SparklesView: View {
    let time: TimeInterval
    let size: CGFloat

    var body: some View {
        let amber = Color(red: 0.94, green: 0.68, blue: 0.25)
        ZStack {
            sparkle(color: amber, phase: 0, x: -size * 0.34, y: 0)
            sparkle(color: Color.fdCoral, phase: 0.5, x: 0, y: -size * 0.12)
            sparkle(color: amber, phase: 1.0, x: size * 0.34, y: 0)
        }
    }

    private func sparkle(color: Color, phase: Double, x: CGFloat, y: CGFloat) -> some View {
        let p = ((time + phase).truncatingRemainder(dividingBy: 1.5)) / 1.5
        return Image(systemName: "sparkle")
            .font(.system(size: size * 0.11))
            .foregroundStyle(color.opacity(p < 0.5 ? p * 2 : 2 - p * 2))
            .scaleEffect(0.6 + p * 0.6)
            .offset(x: x, y: y - p * size * 0.1)
    }
}
