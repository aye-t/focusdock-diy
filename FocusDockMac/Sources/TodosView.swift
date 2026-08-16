import SwiftUI
import UniformTypeIdentifiers

struct TodosView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddTask = false
    @State private var showAddSet = false
    @State private var editingTask: TodoItem?
    @State private var editingSet: TaskSet?
    @State private var query = ""
    @State private var category = "全部"

    private var categories: [String] {
        ["全部"] + Array(Set(model.todos.map(\.resolvedCategory))).filter { $0 != "全部" }.sorted()
    }

    private var filteredTasks: [TodoItem] {
        model.todos.filter { task in
            (category == "全部" || task.resolvedCategory == category)
                && (query.isEmpty || task.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("任务").font(.system(size: 22, weight: .semibold))
                    Text("管理常用任务与任务集，可随时编辑后加入计划")
                        .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
                }
                Spacer()
                Button { showAddSet = true } label: { Label("新建任务集", systemImage: "square.stack.3d.up") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { showAddTask = true } label: { Label("新建任务", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
            }

            HStack(spacing: 10) {
                TextField("搜索任务", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Picker("分类", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 130)
                Spacer()
                Text("\(filteredTasks.count) 个任务")
                    .font(.system(size: 10)).foregroundStyle(Color.fdMuted)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.taskSets.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("任务集", detail: "\(model.taskSets.count) 组")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                                ForEach(model.taskSets) { set in
                                    TaskSetCard(
                                        set: set,
                                        onEdit: { editingSet = set },
                                        onAdd: {
                                            model.addTaskSetToToday(set)
                                            model.selectedSection = .dailyPlan
                                        }
                                    )
                                }
                            }
                        }
                    }

                    sectionHeader("单个任务", detail: "\(filteredTasks.count) 项")
                    if model.todos.isEmpty {
                        emptyState
                            .frame(minHeight: 260)
                    } else if filteredTasks.isEmpty {
                        Text("没有符合条件的任务")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.fdMuted)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(filteredTasks) { task in
                                TaskCard(task: task, onEdit: { editingTask = task })
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(28)
        .sheet(isPresented: $showAddTask) {
            AddTaskTemplateSheet().environmentObject(model)
        }
        .sheet(isPresented: $showAddSet) {
            TaskSetEditorSheet().environmentObject(model)
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task).environmentObject(model)
        }
        .sheet(item: $editingSet) { set in
            TaskSetEditorSheet(set: set).environmentObject(model)
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 9)).foregroundStyle(Color.fdMuted)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2").font(.system(size: 34)).foregroundStyle(Color.fdPurple)
            Text("还没有任务").font(.system(size: 14, weight: .semibold))
            Text("先建立一个常用任务，再加入计划")
                .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
            Button("新建任务") { showAddTask = true }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }
}

private struct TaskSetEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIDs: Set<UUID> = []
    private let existingSet: TaskSet?

    init(set: TaskSet? = nil) {
        existingSet = set
        _name = State(initialValue: set?.name ?? "")
        _selectedIDs = State(initialValue: Set(set?.templateIDs ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(existingSet == nil ? "新建任务集" : "查看与编辑任务集")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                if let existingSet {
                    Button("删除", role: .destructive) {
                        model.deleteTaskSet(existingSet.id)
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.fdCoral)
                }
            }
            TextField("任务集名称", text: $name).textFieldStyle(.roundedBorder)
            Text("选择可组合执行的任务").font(.system(size: 10)).foregroundStyle(Color.fdMuted)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(model.todos) { task in
                        Button {
                            if selectedIDs.contains(task.id) {
                                selectedIDs.remove(task.id)
                            } else {
                                selectedIDs.insert(task.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(task.id) ? Color.fdPurple : Color.fdMuted)
                                Text(task.title).font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(task.focusMinutes) 分钟")
                                    .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                            }
                            .padding(10)
                            .background(Color.fdPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 220)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("保存") {
                    let ordered = model.todos.map(\.id).filter(selectedIDs.contains)
                    if var set = existingSet {
                        set.name = name
                        set.templateIDs = ordered
                        model.updateTaskSet(set)
                    } else {
                        model.addTaskSet(name: name, templateIDs: ordered)
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedIDs.isEmpty)
            }
        }
        .padding(26)
        .frame(width: 450)
    }
}

private struct TaskSetCard: View {
    @EnvironmentObject private var model: AppModel
    let set: TaskSet
    let onEdit: () -> Void
    let onAdd: () -> Void

    private var taskNames: String {
        let names = set.templateIDs.compactMap { id in model.todos.first(where: { $0.id == id })?.title }
        return names.isEmpty ? "尚未选择任务" : names.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(Color.fdPurple)
                    .frame(width: 30, height: 30)
                    .background(Color.fdPurpleSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name).font(.system(size: 13, weight: .semibold))
                    Text("\(set.templateIDs.count) 个任务")
                        .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fdPurple)
                .help("查看与编辑")
            }
            Text(taskNames)
                .font(.system(size: 9))
                .foregroundStyle(Color.fdMuted)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button("查看与编辑", action: onEdit)
                    .buttonStyle(CompactActionButtonStyle())
                Button("加入计划", action: onAdd)
                    .buttonStyle(CompactActionButtonStyle(prominent: true))
            }
        }
        .panel(padding: 14)
    }
}

private struct TaskCard: View {
    @EnvironmentObject private var model: AppModel
    let task: TodoItem
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: task.resolvedSymbol)
                    .foregroundStyle(Color.fdPurple)
                    .frame(width: 34, height: 34)
                    .background(Color.fdPurple.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
                Menu {
                    Button("编辑任务", action: onEdit)
                    Button("立即开始") { model.startTodo(task) }
                    Button("加入计划") { model.addToDailyPlan(template: task) }
                    Divider()
                    Button("删除", role: .destructive) { model.deleteTodo(task.id) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(task.resolvedCategory)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.fdPurple)
            }

            HStack(spacing: 12) {
                Label("\(task.focusMinutes) 分钟", systemImage: "timer")
                Label("休息 \(task.resolvedRestMinutes) 分钟", systemImage: "cup.and.saucer")
            }
            .font(.system(size: 9)).foregroundStyle(Color.fdMuted)

            Text("累计执行 \(task.completedFocusCount) 次")
                .font(.system(size: 9)).foregroundStyle(Color.fdMuted)

            HStack(spacing: 8) {
                Button("开始") { model.startTodo(task) }
                    .buttonStyle(CompactActionButtonStyle(prominent: true))
                Button("编辑", action: onEdit)
                    .buttonStyle(CompactActionButtonStyle())
                Button("加入计划") { model.addToDailyPlan(template: task) }
                    .buttonStyle(CompactActionButtonStyle())
            }
        }
        .panel(padding: 17)
    }
}

private struct CompactActionButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.fdPurple)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                prominent
                    ? Color.fdPurple.opacity(configuration.isPressed ? 0.78 : 1)
                    : Color.fdPurpleSoft.opacity(configuration.isPressed ? 0.72 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EditTaskSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var focusText: String
    @State private var restText: String

    init(task: TodoItem) {
        _draft = State(initialValue: task)
        _focusText = State(initialValue: String(task.focusMinutes))
        _restText = State(initialValue: String(task.resolvedRestMinutes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑任务").font(.system(size: 20, weight: .semibold))
            TextField("任务名称", text: $draft.title).textFieldStyle(.roundedBorder)
            TextField("分类（可留空）", text: Binding(
                get: { draft.category ?? "" },
                set: { draft.category = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                MinuteInput(title: "专注时间", placeholder: "25", text: $focusText)
                MinuteInput(title: "休息时间", placeholder: "5", text: $restText)
            }
            Text("可直接输入分钟数；暂时留空也不会打断编辑。")
                .font(.system(size: 9))
                .foregroundStyle(Color.fdMuted)
            HStack {
                Button("删除任务", role: .destructive) {
                    model.deleteTodo(draft.id)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fdCoral)
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("保存") {
                    draft.focusMinutes = clampedMinutes(focusText, fallback: draft.focusMinutes, range: 1...180)
                    draft.restMinutes = clampedMinutes(restText, fallback: draft.resolvedRestMinutes, range: 1...60)
                    model.updateTodo(draft)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct DailyPlanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDate = Date()
    @State private var showAddPlan = false
    @State private var showTaskSets = false
    @State private var editingItem: DailyPlanItem?
    @State private var draggingID: UUID?
    @State private var planTab: PlanTab = .upcoming
    @State private var renamingSessionID: UUID?
    @State private var renameText = ""
    @State private var notingSessionID: UUID?
    @State private var noteText = ""
    @State private var sessionToDelete: FocusSession?

    private var dayItems: [DailyPlanItem] {
        model.dailyPlanItems
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.order < $1.order }
    }

    private var upcomingItems: [DailyPlanItem] {
        dayItems.filter { model.effectivePlanStatus($0) != .completed }
    }

    private var completionRecords: [CompletionRecord] {
        model.completionRecords(on: selectedDate)
    }

    private var completedCount: Int { dayItems.filter { $0.status == .completed }.count }
    private var totalFocus: Int { dayItems.reduce(0) { $0 + $1.focusMinutes } }
    private var totalRest: Int { dayItems.reduce(0) { $0 + $1.restMinutes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("计划").font(.system(size: 22, weight: .semibold))
                    Text("安排任务顺序，每项都可独立开始，提醒时间为可选")
                        .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
                }
                Spacer()
                PlanDateNavigator(date: $selectedDate)
                Button { showAddPlan = true } label: { Label("添加任务", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { showTaskSets = true } label: { Label("加入任务集", systemImage: "square.stack.3d.up") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 2) {
                ForEach(PlanTab.allCases, id: \.self) { tab in
                    let count = tab == .upcoming ? upcomingItems.count : completionRecords.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) { planTab = tab }
                    } label: {
                        Text("\(tab.title) \(count)")
                            .font(.system(size: 11, weight: planTab == tab ? .semibold : .regular))
                            .foregroundStyle(planTab == tab ? Color.fdPurple : Color.fdMuted)
                            .frame(maxWidth: .infinity, minHeight: 27)
                            .background(planTab == tab ? Color.fdPanel : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(width: 250)
            .background(Color.fdBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.fdLine, lineWidth: 1)
            )

            if planTab == .upcoming {
                if upcomingItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(upcomingItems.enumerated()), id: \.element.id) { index, item in
                                DailyPlanRow(
                                    item: item,
                                    displayTitle: model.planDisplayTitle(item),
                                    position: index + 1,
                                    total: upcomingItems.count,
                                    onEdit: { editingItem = item }
                                )
                                .opacity(draggingID == item.id ? 0.48 : 1)
                                .scaleEffect(draggingID == item.id ? 0.985 : 1)
                                .onDrag {
                                    draggingID = item.id
                                    return NSItemProvider(object: item.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: DailyPlanDropDelegate(
                                        targetID: item.id,
                                        draggingID: $draggingID,
                                        model: model
                                    )
                                )
                            }
                        }
                        .animation(.easeInOut(duration: 0.14), value: upcomingItems.map(\.id))
                    }
                }
            } else {
                CompletedRecordsList(
                    date: selectedDate,
                    renamingSessionID: $renamingSessionID,
                    renameText: $renameText,
                    notingSessionID: $notingSessionID,
                    noteText: $noteText,
                    sessionToDelete: $sessionToDelete
                )
                .environmentObject(model)
            }

            if planTab == .upcoming {
                HStack(spacing: 30) {
                    summaryMetric("计划任务", "\(dayItems.count) 项")
                    summaryMetric("已完成", "\(completedCount) 项")
                    summaryMetric("计划专注", "\(totalFocus) 分钟")
                    summaryMetric("计划休息", "\(totalRest) 分钟")
                    Spacer()
                    if !dayItems.isEmpty {
                        ProgressView(value: Double(completedCount), total: Double(dayItems.count))
                            .tint(Color.fdPurple).frame(width: 145)
                        Text("\(completedCount)/\(dayItems.count)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.fdPurple)
                    }
                }
                .panel(padding: 14)
            }
        }
        .padding(28)
        .onAppear { applyRequestedDestination() }
        .onChange(of: model.requestedPlanTab) { _, tab in
            if tab != nil { applyRequestedDestination() }
        }
        .sheet(isPresented: $showAddPlan) {
            AddDailyPlanSheet(date: selectedDate).environmentObject(model)
        }
        .sheet(isPresented: $showTaskSets) {
            TaskSetPickerSheet(date: selectedDate).environmentObject(model)
        }
        .popover(item: $editingItem, arrowEdge: .trailing) { item in
            EditDailyPlanPopover(item: item).environmentObject(model)
        }
        .alert("删除这条专注记录？", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let session = sessionToDelete { model.deleteSession(session.id) }
                sessionToDelete = nil
            }
            Button("取消", role: .cancel) { sessionToDelete = nil }
        } message: {
            if let s = sessionToDelete { Text("「\(s.task) · \(s.minutes)分钟」将被移除，不可恢复。") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: dayItems.isEmpty ? "list.number" : "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(dayItems.isEmpty ? Color.fdPurple : Color.fdGreen)
            Text(dayItems.isEmpty ? "今天还没有任务" : "今天的计划已完成")
                .font(.system(size: 14, weight: .semibold))
            Text(dayItems.isEmpty ? "添加任务或任务集，拖动左侧把手即可调整顺序" : "完成记录已经归档到“已完成”")
                .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
            if dayItems.isEmpty {
                Button("添加任务") { showAddPlan = true }.buttonStyle(PrimaryButtonStyle())
            } else {
                Button("查看已完成") { planTab = .completed }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    private func summaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            Text(value).font(.system(size: 13, weight: .semibold))
        }
    }

    private func applyRequestedDestination() {
        guard let tab = model.requestedPlanTab else { return }
        if let date = model.requestedPlanDate { selectedDate = date }
        planTab = tab
        model.requestedPlanTab = nil
        model.requestedPlanDate = nil
    }
}

// MARK: - 已完成记录列表
private struct CompletedRecordsList: View {
    @EnvironmentObject private var model: AppModel
    let date: Date
    @Binding var renamingSessionID: UUID?
    @Binding var renameText: String
    @Binding var notingSessionID: UUID?
    @Binding var noteText: String
    @Binding var sessionToDelete: FocusSession?

    private var records: [CompletionRecord] { model.completionRecords(on: date) }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(Color.fdGreen)
                    Text("还没有完成的专注").font(.system(size: 14, weight: .semibold))
                    Text("随手点开始专注，完成后会自动出现在这里")
                        .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panel()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(dateLabel) · 已完成")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fdInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)

                    Divider().overlay(Color.fdLine)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                CompletedRecordRow(
                                    record: record,
                                    isRenaming: record.sessionID == renamingSessionID,
                                    renameText: $renameText,
                                    isNoting: record.sessionID == notingSessionID,
                                    noteText: $noteText,
                                    onStartRename: {
                                        guard let sessionID = record.sessionID else { return }
                                        renamingSessionID = sessionID
                                        renameText = record.title
                                        notingSessionID = nil
                                    },
                                    onCommitRename: {
                                        guard let sessionID = record.sessionID else { return }
                                        model.renameSession(sessionID, to: renameText)
                                        renamingSessionID = nil
                                    },
                                    onCancelRename: { renamingSessionID = nil },
                                    onStartNote: {
                                        guard let sessionID = record.sessionID else { return }
                                        notingSessionID = sessionID
                                        noteText = record.note
                                        renamingSessionID = nil
                                    },
                                    onCommitNote: {
                                        guard let sessionID = record.sessionID else { return }
                                        model.updateSessionNote(sessionID, note: noteText)
                                        notingSessionID = nil
                                    },
                                    onCancelNote: { notingSessionID = nil },
                                    onCopy: {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(record.title, forType: .string)
                                    },
                                    onDelete: {
                                        guard let sessionID = record.sessionID else { return }
                                        sessionToDelete = model.sessions.first { $0.id == sessionID }
                                    },
                                    onReopenPlan: {
                                        guard let planItemID = record.planItemID else { return }
                                        model.setPlanItemStatus(planItemID, status: .pending)
                                    }
                                )
                                if index < records.count - 1 {
                                    Divider().overlay(Color.fdLine).padding(.leading, 54)
                                }
                            }
                        }
                        .animation(.easeInOut(duration: 0.14), value: records.map(\.id))
                    }

                    Divider().overlay(Color.fdLine)
                    HStack {
                        Text("今日完成 \(records.count) 项")
                        Text("·").foregroundStyle(Color.fdMuted)
                        Text("专注 \(records.compactMap(\.minutes).reduce(0, +)) 分钟")
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.fdMuted)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                }
                .panel(padding: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompletedRecordRow: View {
    let record: CompletionRecord
    let isRenaming: Bool
    let renameText: Binding<String>
    let isNoting: Bool
    let noteText: Binding<String>
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onStartNote: () -> Void
    let onCommitNote: () -> Void
    let onCancelNote: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onReopenPlan: () -> Void

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: record.completedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.fdGreen)

                HStack(spacing: 9) {
                    Text(record.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.fdInk)
                        .lineLimit(1)
                    sourceTag
                    if !record.note.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.fdMuted)
                    }
                }
                Spacer(minLength: 18)

                if let minutes = record.minutes {
                    Label("\(minutes) 分钟", systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fdMuted)
                        .frame(minWidth: 76, alignment: .leading)
                } else {
                    Text("手动完成")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.fdMuted)
                        .frame(minWidth: 76, alignment: .leading)
                }

                Text("\(timeLabel) 完成")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.fdMuted)
                    .frame(width: 78, alignment: .leading)

                Menu {
                    if record.sessionID != nil {
                        Button("修改名称", action: onStartRename)
                        Button(record.note.isEmpty ? "添加备注" : "修改备注", action: onStartNote)
                    }
                    Button("复制任务名", action: onCopy)
                    Divider()
                    if record.sessionID != nil {
                        Button("删除记录", role: .destructive, action: onDelete)
                    } else {
                        Button("撤销完成", action: onReopenPlan)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 62)

            if isRenaming {
                HStack(spacing: 8) {
                    TextField("任务名", text: renameText)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") { onCommitRename() }.buttonStyle(SecondaryButtonStyle())
                    Button("取消") { onCancelRename() }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            } else if isNoting {
                HStack(spacing: 8) {
                    TextField("备注（可选）", text: noteText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    Button("保存") { onCommitNote() }.buttonStyle(SecondaryButtonStyle())
                    Button("取消") { onCancelNote() }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    private var sourceTag: some View {
        Text(record.origin.title)
            .font(.system(size: 10))
            .foregroundStyle(record.origin == .plan ? Color.fdGreen : Color.fdPurple)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background((record.origin == .plan ? Color.fdGreen : Color.fdPurple).opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct PlanDateNavigator: View {
    @Binding var date: Date
    @State private var showCalendar = false

    var body: some View {
        HStack(spacing: 4) {
            dayButton("chevron.left", offset: -1)
            Button {
                showCalendar.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.fdPurple)
                    VStack(spacing: 1) {
                        Text(date.formatted(.dateTime.month().day()))
                            .font(.system(size: 11, weight: .semibold))
                        Text(date.formatted(.dateTime.year().weekday(.abbreviated)))
                            .font(.system(size: 8))
                            .foregroundStyle(Color.fdMuted)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.fdMuted)
                }
                .frame(minWidth: 92)
            }
            .buttonStyle(.plain)
            .help("选择日期筛选计划")
            .popover(isPresented: $showCalendar, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择计划日期")
                        .font(.system(size: 13, weight: .semibold))
                    DatePicker(
                        "计划日期",
                        selection: $date,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        Button("今天") {
                            date = Date()
                            showCalendar = false
                        }
                        .buttonStyle(CompactActionButtonStyle())
                        Spacer()
                        Button("完成") { showCalendar = false }
                            .buttonStyle(CompactActionButtonStyle(prominent: true))
                    }
                }
                .padding(14)
                .frame(width: 190)
            }
            dayButton("chevron.right", offset: 1)
            if !Calendar.current.isDateInToday(date) {
                Button("今天") { date = Date() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.fdPurple)
                    .padding(.horizontal, 7)
            }
        }
        .padding(5)
        .background(Color.fdPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fdLine))
    }

    private func dayButton(_ symbol: String, offset: Int) -> some View {
        Button {
            date = Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.fdPurple)
        .background(Color.fdPurpleSoft)
        .clipShape(Circle())
    }
}

private struct TaskSetPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("加入任务集").font(.system(size: 20, weight: .semibold))
            if model.taskSets.isEmpty {
                Text("还没有任务集，可以先在任务页面创建。")
                    .font(.system(size: 11)).foregroundStyle(Color.fdMuted)
                Button("打开任务") {
                    dismiss()
                    model.selectedSection = .todos
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                ForEach(model.taskSets) { set in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(set.name).font(.system(size: 13, weight: .semibold))
                            Text("\(set.templateIDs.count) 个任务")
                                .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                        }
                        Spacer()
                        Button("加入计划") {
                            model.addTaskSetToToday(set, date: date)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .panel(padding: 12)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(24).frame(width: 420, height: 320)
    }
}

private struct DailyPlanRow: View {
    @EnvironmentObject private var model: AppModel
    let item: DailyPlanItem
    let displayTitle: String
    let position: Int
    let total: Int
    let onEdit: () -> Void

    private var status: DailyPlanStatus { model.effectivePlanStatus(item) }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fdMuted)
                .frame(width: 18)
                .help("拖动调整顺序")
            Text("\(position)")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.fdMuted)
                .frame(width: 20)
            Button { model.togglePlanItemCompleted(item.id) } label: {
                Image(systemName: status == .completed ? "checkmark.circle.fill" : status == .running ? "play.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(status == .completed ? Color.fdGreen : status == .running ? Color.fdPurple : Color.fdMuted.opacity(0.55))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(status == .completed)
                    .foregroundStyle(status == .completed ? Color.fdMuted : Color.fdInk)
                Button(action: onEdit) {
                    HStack(spacing: 7) {
                        metaChip("\(item.focusMinutes) 分钟", symbol: "timer")
                        metaChip("休息 \(item.restMinutes)", symbol: "cup.and.saucer")
                        if let time = item.reminderTimeText {
                            metaChip("\(time) 提醒", symbol: "bell", emphasized: true)
                        } else {
                            metaChip("自由安排", symbol: "calendar.badge.minus")
                        }
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.fdPurple)
                    }
                }
                .buttonStyle(.plain)
                .help("查看与修改专注、休息和提醒时间")
            }
            Spacer()

            if status == .completed {
                Text("已完成").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.fdGreen)
                Button("撤销") { model.togglePlanItemCompleted(item.id) }.buttonStyle(SecondaryButtonStyle())
            } else if status == .running {
                Text(model.timeText).font(.system(size: 13, weight: .semibold, design: .monospaced))
                Button("继续") { model.selectedSection = .focus }.buttonStyle(PrimaryButtonStyle())
                Button("完成") { model.togglePlanItemCompleted(item.id) }.buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    model.startPlanItem(item)
                } label: {
                    Label("开始", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fdPurple)
                    .frame(width: 28, height: 28)
                    .background(Color.fdPurpleSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("查看与编辑时间")

            Menu {
                Button("编辑计划任务", action: onEdit)
                Button("从这里开始") { model.startPlanItem(item) }.disabled(status == .completed)
                Button("上移") { model.movePlanItem(item.id, offset: -1) }.disabled(position == 1)
                Button("下移") { model.movePlanItem(item.id, offset: 1) }.disabled(position == total)
                Button(status == .completed ? "撤销完成" : "标记完成") { model.togglePlanItemCompleted(item.id) }
                Divider()
                Button("删除", role: .destructive) { model.deletePlanItem(item.id) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        }
        .panel(padding: 15)
    }

    private func metaChip(_ text: String, symbol: String, emphasized: Bool = false) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(emphasized ? Color.fdPurple : Color.fdMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(emphasized ? Color.fdPurpleSoft : Color.fdBackground)
            .clipShape(Capsule())
    }
}

private struct DailyPlanDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            model.reorderPlanItemPreview(draggingID, relativeTo: targetID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        model.commitPlanOrder()
        draggingID = nil
        return true
    }
}

private struct EditDailyPlanPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DailyPlanItem
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var focusText: String
    @State private var restText: String

    init(item: DailyPlanItem) {
        _draft = State(initialValue: item)
        _reminderEnabled = State(initialValue: item.reminderStartMinute != nil)
        _focusText = State(initialValue: String(item.focusMinutes))
        _restText = State(initialValue: String(item.restMinutes))
        let minute = item.reminderStartMinute ?? 14 * 60
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 3) {
                Text("查看与编辑计划时间").font(.system(size: 16, weight: .semibold))
                Text("修改后只影响这一项计划")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fdMuted)
            }
            TextField("任务名称", text: $draft.title).textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                MinuteInput(title: "专注时间", placeholder: "25", text: $focusText)
                MinuteInput(title: "休息时间", placeholder: "5", text: $restText)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始提醒").font(.system(size: 11, weight: .medium))
                    Text(reminderEnabled ? "到点提醒是否开始任务" : "自由安排，不设置固定时间")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.fdMuted)
                }
                Spacer()
                Toggle("", isOn: $reminderEnabled).labelsHidden()
            }
            if reminderEnabled {
                HStack {
                    Label("提醒时间", systemImage: "bell")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.fdPurple)
                    Spacer()
                    DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.fdPurpleSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text("时间只用于提醒，不影响任务顺序")
                .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("保存") {
                    if reminderEnabled {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                        draft.reminderStartMinute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                    } else {
                        draft.reminderStartMinute = nil
                    }
                    draft.focusMinutes = clampedMinutes(focusText, fallback: draft.focusMinutes, range: 1...180)
                    draft.restMinutes = clampedMinutes(restText, fallback: draft.restMinutes, range: 1...60)
                    draft.reminderLastTriggeredAt = nil
                    draft.reminderSnoozedUntil = nil
                    model.updatePlanItem(draft)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20).frame(width: 330)
    }
}

private struct AddTaskTemplateSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var focusText = ""
    @State private var restText = ""
    @State private var category = "工作"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建任务").font(.system(size: 20, weight: .semibold))
            TextField("任务名称", text: $title).textFieldStyle(.roundedBorder)
            TextField("分类（如工作、学习、生活）", text: $category).textFieldStyle(.roundedBorder)
            HStack {
                MinuteInput(title: "专注时间", placeholder: "25", text: $focusText)
                MinuteInput(title: "休息时间", placeholder: "5", text: $restText)
            }
            Text("时间可直接输入；留空时分别使用 25 分钟和 5 分钟。")
                .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("保存") {
                    model.addTaskTemplate(
                        title: title,
                        focusMinutes: clampedMinutes(focusText, fallback: 25, range: 1...180),
                        restMinutes: clampedMinutes(restText, fallback: 5, range: 1...60),
                        category: category
                    )
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 450)
    }

}

private struct MinuteInput: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.fdMuted)
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .onChange(of: text) { _, value in
                        text = String(value.filter(\.isNumber).prefix(3))
                    }
                Text("分钟").font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Color.fdBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.fdLine))
        }
        .frame(maxWidth: .infinity)
    }
}

private func clampedMinutes(
    _ text: String,
    fallback: Int,
    range: ClosedRange<Int>
) -> Int {
    let value = Int(text) ?? fallback
    return max(range.lowerBound, min(range.upperBound, value))
}

private struct AddDailyPlanSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var selectedTemplateID: UUID?
    @State private var customTitle = ""
    @State private var plannedTime = Date()
    @State private var focusText = ""
    @State private var restText = ""
    @State private var reminderEnabled = false
    @State private var repetitions = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加到计划").font(.system(size: 20, weight: .semibold))
            if !model.todos.isEmpty {
                Picker("从任务选择", selection: $selectedTemplateID) {
                    Text("自定义任务").tag(nil as UUID?)
                    ForEach(model.todos) { Text($0.title).tag(Optional($0.id)) }
                }
                .onChange(of: selectedTemplateID) { _, id in
                    guard let id, let task = model.todos.first(where: { $0.id == id }) else { return }
                    customTitle = task.title
                    focusText = String(task.focusMinutes)
                    restText = String(task.resolvedRestMinutes)
                }
            }
            TextField("任务名称", text: $customTitle).textFieldStyle(.roundedBorder)
            Stepper("添加 \(repetitions) 次", value: $repetitions, in: 1...10)
            HStack(spacing: 10) {
                MinuteInput(title: "专注时间", placeholder: "25", text: $focusText)
                MinuteInput(title: "休息时间", placeholder: "5", text: $restText)
            }
            Toggle("提醒我开始", isOn: $reminderEnabled)
            if reminderEnabled {
                DatePicker("提醒时间", selection: $plannedTime, displayedComponents: .hourAndMinute)
            }
            Text("时间只用于提醒，不影响任务顺序")
                .font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("加入队列") {
                    let focusMinutes = clampedMinutes(focusText, fallback: 25, range: 1...180)
                    let restMinutes = clampedMinutes(restText, fallback: 5, range: 1...60)
                    let components = Calendar.current.dateComponents([.hour, .minute], from: plannedTime)
                    let minute = reminderEnabled ? (components.hour ?? 0) * 60 + (components.minute ?? 0) : nil
                    for _ in 0..<repetitions {
                        if let id = selectedTemplateID,
                           let task = model.todos.first(where: { $0.id == id }) {
                            var configured = task
                            configured.focusMinutes = focusMinutes
                            configured.restMinutes = restMinutes
                            model.addToDailyPlan(template: configured, date: date, reminderStartMinute: minute)
                        } else {
                            model.addDailyPlanItem(
                                title: customTitle,
                                date: date,
                                reminderStartMinute: minute,
                                focusMinutes: focusMinutes,
                                restMinutes: restMinutes
                            )
                        }
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 460)
        .onAppear {
            let rounded = Calendar.current.date(bySetting: .second, value: 0, of: Date()) ?? Date()
            plannedTime = rounded
        }
    }
}
