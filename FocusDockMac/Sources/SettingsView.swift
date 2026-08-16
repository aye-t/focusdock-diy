import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置").font(.system(size: 22, weight: .semibold))
                Spacer()
            }
            ScrollView {
                VStack(spacing: 14) {
                    settingsGroup(title: "计时", symbol: "timer") {
                        SettingStepper(title: "默认专注时长", value: settingBinding(\.focusMinutes), range: 1...180, unit: "分钟")
                        Divider().overlay(Color.fdLine)
                        SettingStepper(title: "休息时长", value: settingBinding(\.restMinutes), range: 1...60, unit: "分钟")
                        Divider().overlay(Color.fdLine)
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.fdGreen)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("专注结束后自动休息").font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                        }
                    }
                    settingsGroup(title: "外观", symbol: "paintbrush") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("主题").font(.system(size: 12, weight: .medium))
                            HStack(spacing: 8) {
                                ForEach(AppAppearance.allCases) { option in
                                    Button {
                                        model.updateSettings { $0.appearance = option }
                                        WindowManager.shared.applyAppearance(option)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: option.symbol)
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(option.title)
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .foregroundStyle(model.settings.appearance == option ? .white : Color.fdMuted)
                                        .background(model.settings.appearance == option ? Color.fdPurple : Color.fdPanel)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(model.settings.appearance == option ? Color.clear : Color.fdLine, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    settingsGroup(title: "悬浮控件", symbol: "macwindow.on.rectangle") {
                        SettingToggle(title: "番茄钟悬浮图标", subtitle: nil, isOn: settingBinding(\.showTimerPanel))
                        Divider().overlay(Color.fdLine)
                        SettingToggle(
                            title: "直观提醒卡片",
                            subtitle: "集中查看多条提醒和剩余时间",
                            isOn: settingBinding(\.showReminderPanel)
                        )
                        Divider().overlay(Color.fdLine)
                        HStack {
                            Text("悬浮控件位置").font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("重置位置") { WindowManager.shared.resetPanelPositions() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Divider().overlay(Color.fdLine)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("悬浮布局").font(.system(size: 12, weight: .medium))
                            EqualSegmentedPicker(
                                selection: settingBinding(\.floatingLayout),
                                options: FloatingLayoutStyle.allCases
                            ) { style in
                                style.title
                            }
                            if model.settings.showTimerPanel && !model.settings.showReminderPanel {
                                Label("当前仅显示番茄钟，将自动使用无长条背景的独立图标。", systemImage: "timer")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.fdMuted)
                            }
                        }
                        Divider().overlay(Color.fdLine)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("番茄钟图标").font(.system(size: 12, weight: .medium))
                            HStack(spacing: 8) {
                                ForEach(TimerIconStyle.allCases) { style in
                                    FloatingIconChoice(
                                        title: style.title,
                                        systemImage: style.previewSymbol,
                                        selected: model.settings.timerIconStyle == style,
                                        tint: model.settings.floatingTint.color
                                    ) { model.updateSettings { $0.timerIconStyle = style }; WindowManager.shared.refreshPanelVisibility() }
                                }
                            }
                        }
                        Divider().overlay(Color.fdLine)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("提醒图标").font(.system(size: 12, weight: .medium))
                            HStack(spacing: 8) {
                                ForEach(ReminderIconStyle.allCases) { style in
                                    FloatingIconChoice(
                                        title: style.title,
                                        systemImage: style.previewSymbol,
                                        emoji: style == .customEmoji ? model.settings.customReminderEmoji : nil,
                                        selected: model.settings.reminderIconStyle == style,
                                        tint: model.settings.floatingTint.color
                                    ) { model.updateSettings { $0.reminderIconStyle = style }; WindowManager.shared.refreshPanelVisibility() }
                                }
                            }
                            if model.settings.reminderIconStyle == .customEmoji {
                                HStack(spacing: 10) {
                                    Text("自定义 Emoji").font(.system(size: 10)).foregroundStyle(Color.fdMuted)
                                    TextField("🌱", text: settingBinding(\.customReminderEmoji))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
                                        .onChange(of: model.settings.customReminderEmoji) { _, value in
                                            if value.count > 2 {
                                                model.updateSettings { $0.customReminderEmoji = String(value.prefix(2)) }
                                            }
                                        }
                                }
                            }
                        }
                        Divider().overlay(Color.fdLine)
                        HStack(spacing: 12) {
                            Text("主题颜色").font(.system(size: 12, weight: .medium))
                            ForEach(FloatingTint.allCases) { tint in
                                Button {
                                    model.updateSettings { $0.floatingTint = tint }
                                } label: {
                                    ZStack {
                                        Circle().fill(tint.color).frame(width: 24, height: 24)
                                        if model.settings.floatingTint == tint {
                                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("选择主题颜色")
                            }
                            Spacer()
                        }
                    }
                    settingsGroup(title: "桌面宠物", symbol: "pawprint") {
                        SettingToggle(
                            title: "宠物陪伴提醒",
                            subtitle: "用动作、气泡和快捷操作陪伴专注",
                            isOn: settingBinding(\.showPetPanel)
                        )
                        if model.settings.showPetPanel {
                            Divider().overlay(Color.fdLine)
                            HStack(alignment: .center, spacing: 16) {
                                // 预览区：用真实贴纸渲染
                                SpritePetAvatarView(
                                    species: model.settings.petSpecies,
                                    mood: PetMood(phase: model.phase),
                                    size: min(112, max(64, CGFloat(model.settings.petSize) * 0.58))
                                )
                                .frame(width: 116, height: 98)
                                .background(Color.fdBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("宠物形象").font(.system(size: 12, weight: .medium))
                                    HStack(spacing: 8) {
                                        ForEach(PetSpecies.allCases) { species in
                                            FloatingIconChoice(
                                                title: species.title,
                                                systemImage: species.previewSymbol,
                                                selected: model.settings.petSpecies == species,
                                                tint: model.settings.floatingTint.color
                                            ) { model.updateSettings { $0.petSpecies = species } }
                                        }
                                    }
                                }
                            }
                            Divider().overlay(Color.fdLine)
                            PetSizeControl(value: settingBinding(\.petSize))
                            Divider().overlay(Color.fdLine)
                            Text("💡 桌宠会随专注状态自然轮换动作；右键可切换形象和演示提醒")
                                .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                        }
                    }
                    settingsGroup(title: "通知", symbol: "bell") {
                        SettingToggle(
                            title: "声音提醒",
                            subtitle: "用于番茄钟结束、计划提醒和宠物提醒",
                            isOn: settingBinding(\.soundEnabled)
                        )
                        Divider().overlay(Color.fdLine)
                        SoundSelectionRow(
                            title: "番茄钟结束",
                            selection: settingBinding(\.timerAlertSound),
                            preview: { model.previewSound(model.settings.timerAlertSound) }
                        )
                        .disabled(!model.settings.soundEnabled)
                        Divider().overlay(Color.fdLine)
                        SoundSelectionRow(
                            title: "提醒",
                            selection: settingBinding(\.reminderAlertSound),
                            preview: { model.previewSound(model.settings.reminderAlertSound) }
                        )
                        .disabled(!model.settings.soundEnabled)
                        Divider().overlay(Color.fdLine)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("提醒动画").font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Picker("提醒动画", selection: settingBinding(\.reminderEmphasis)) {
                                ForEach(ReminderEmphasis.allCases) { item in Text(item.title).tag(item) }
                            }
                            .labelsHidden().frame(width: 130)
                        }
                        Divider().overlay(Color.fdLine)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("系统通知").font(.system(size: 12, weight: .medium))
                                Spacer()
                                Button("设置") {
                                    if model.settings.notificationsEnabled || model.notificationBlocked {
                                        model.openNotificationSettings()
                                    } else {
                                        model.requestNotificationPermission()
                                    }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            if let hint = model.notificationHint {
                                Text(hint).font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .onAppear { model.refreshNotificationAuthorization() }
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                            model.refreshNotificationAuthorization()
                        }
                    }
                    settingsGroup(title: "Obsidian 联动", symbol: "link") {
                        HStack(spacing: 12) {
                            Image(systemName: model.settings.obsidianVaultPath == nil ? "externaldrive.badge.questionmark" : "checkmark.circle.fill")
                                .foregroundStyle(model.settings.obsidianVaultPath == nil ? Color.fdMuted : Color.fdGreen)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.settings.obsidianVaultPath == nil ? "尚未连接仓库" : "已连接 Obsidian")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Button(model.settings.obsidianVaultPath == nil ? "选择仓库" : "更换仓库") { model.chooseObsidianVault() }
                                .buttonStyle(SecondaryButtonStyle())
                            if model.settings.obsidianVaultPath != nil {
                                Button("取消链接") { model.disconnectObsidian() }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                            Button("立即同步") { model.syncToObsidian() }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(model.settings.obsidianVaultPath == nil)
                        }
                        Divider().overlay(Color.fdLine)
                        SettingToggle(
                            title: "自动同步记录",
                            subtitle: nil,
                            isOn: settingBinding(\.obsidianAutoSync)
                        )
                        Text(model.obsidianSyncStatus).font(.system(size: 9)).foregroundStyle(Color.fdPurple)
                    }
                    HStack(spacing: 13) {
                        Image(systemName: "lock.fill").foregroundStyle(Color.fdGreen)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("本机数据").font(.system(size: 12, weight: .semibold))
                        }
                        Spacer()
                        Button("清空记录", role: .destructive) { model.clearAllData() }.buttonStyle(SecondaryButtonStyle())
                    }
                    .panel(padding: 17)
                }
            }
        }
        .padding(28)
    }

    private func settingBinding<T>(_ path: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: path] }, set: { newValue in
            model.updateSettings { $0[keyPath: path] = newValue }
            WindowManager.shared.refreshPanelVisibility()
        })
    }

    private func settingsGroup<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Color.fdPurple)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            content()
        }
        .panel()
    }
}

private struct EqualSegmentedPicker<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == option ? .white : Color.fdInk.opacity(0.82))
                .background(selection == option ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if index < options.count - 1 {
                    Rectangle()
                        .fill(Color.fdLine.opacity(0.65))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 5)
                }
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(Color.fdBackground.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let subtitle { Text(subtitle).font(.system(size: 9)).foregroundStyle(Color.fdMuted) }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Color.fdPurple)
        }
    }
}

private struct SettingStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            EditableStepper(value: $value, range: range, unit: unit)
        }
    }
}

private struct PetSizeControl: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("宠物大小").font(.system(size: 12, weight: .medium))
            Spacer()
            Image(systemName: "pawprint")
                .font(.system(size: 10))
                .foregroundStyle(Color.fdMuted)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: 88...220,
                step: 4
            )
            .frame(width: 150)
            Image(systemName: "pawprint.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.fdPurple)
            Text("\(value) pt")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.fdInk)
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("宠物大小")
        .accessibilityValue("\(value) pt")
    }
}

private struct SoundSelectionRow: View {
    let title: String
    @Binding var selection: AlertSound
    let preview: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(AlertSound.allCases) { sound in Text(sound.title).tag(sound) }
            }
            .labelsHidden().frame(width: 140)
            Button("试听", action: preview).buttonStyle(SecondaryButtonStyle())
        }
    }
}

private struct FloatingIconChoice: View {
    let title: String
    let systemImage: String
    var emoji: String? = nil
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 17)).frame(height: 21)
                } else {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold)).frame(height: 21)
                }
                Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(selected ? tint : Color.fdMuted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? tint.opacity(0.11) : Color.fdBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? tint.opacity(0.65) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
