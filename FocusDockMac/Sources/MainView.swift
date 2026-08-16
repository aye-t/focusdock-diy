import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.fdLine)
            Group {
                switch model.selectedSection {
                case .focus: FocusView()
                case .dailyPlan: DailyPlanView()
                case .todos: TodosView()
                case .reminders: RemindersView()
                case .review: ReviewView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fdBackground)
        }
        .background(Color.fdBackground)
        .foregroundStyle(Color.fdInk)
        .preferredColorScheme(model.settings.appearance.scheme)
        .onChange(of: model.settings.appearance) { _, _ in
            WindowManager.shared.applyAppearance(model.settings.appearance)
        }
        .sheet(isPresented: $model.isCompletionPresented) {
            CompletionSheet()
                .environmentObject(model)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.fdPurple)
                    Image(systemName: "timer").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                Text("FocusDock").font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 17)
            .padding(.top, 24)
            .padding(.bottom, 30)

            VStack(spacing: 6) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        model.selectedSection = section
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.symbol).frame(width: 19)
                            Text(section.title)
                            Spacer()
                            if section == .reminders && !model.queuedReminderIDs.isEmpty {
                                Text("\(model.queuedReminderIDs.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Color.fdCoral)
                                    .clipShape(Circle())
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(model.selectedSection == section ? Color.fdPurple : Color.fdMuted)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(model.selectedSection == section ? Color.fdPanel : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle().fill(model.isRunning ? Color.fdCoral : Color.fdMuted.opacity(0.55)).frame(width: 7, height: 7)
                    Text(model.phaseText).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.fdMuted)
                }
                Text(model.phase == .idle ? "未计时" : model.timeText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fdPanel.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(14)
        }
        .frame(width: 210)
        .background(Color.fdSidebar)
    }
}

struct CompletionSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var result: SessionResult = .done
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 33))
                .foregroundStyle(Color.fdGreen)
            VStack(alignment: .leading, spacing: 5) {
                Text("记录本轮进展").font(.system(size: 20, weight: .semibold))
                Text(model.task.isEmpty ? "未命名专注" : model.task).font(.system(size: 12)).foregroundStyle(Color.fdMuted)
            }
            Picker("结果", selection: $result) {
                ForEach([SessionResult.done, .progress, .interrupted]) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            TextField("备注（可选）", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
            HStack {
                Button("再专注 5 分钟") { model.extendFiveMinutes() }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("记录并结束") { model.saveProgress(result: result, note: note, startBreak: false) }.buttonStyle(SecondaryButtonStyle())
                Button("休息 \(model.settings.restMinutes) 分钟") { model.saveProgress(result: result, note: note, startBreak: true) }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 470)
    }
}
