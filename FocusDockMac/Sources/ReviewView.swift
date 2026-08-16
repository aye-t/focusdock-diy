import Charts
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period: ReviewPeriod = .day
    @State private var anchorDate = Date()
    @State private var showCalendar = false
    @State private var reminderFilter: ReminderFilter = .all
    @State private var hoveredDay: DailyFocus?
    @State private var hoveredLocation: CGPoint?
    @State private var showAllDetails = false
    @State private var chartGranularity: ChartGranularity = .day
    @State private var hoveredHour: HourlyFocus?

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var previousInterval: DateInterval {
        let shifted: Date
        switch period {
        case .day: shifted = calendar.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate
        case .week: shifted = calendar.date(byAdding: .day, value: -7, to: anchorDate) ?? anchorDate
        case .month: shifted = calendar.date(byAdding: .month, value: -1, to: anchorDate) ?? anchorDate
        }
        return interval(containing: shifted)
    }

    private var previousSessionsCount: Int {
        model.sessions.filter { previousInterval.contains($0.startedAt) }.count
    }

    private var dailyAverage: Int {
        let days = max(1, periodData.filter { $0.minutes > 0 }.count)
        return periodFocusMinutes / days
    }

    private var periodInterval: DateInterval { interval(containing: anchorDate) }
    private var currentPeriodInterval: DateInterval { interval(containing: Date()) }
    private var isCurrentPeriod: Bool { calendar.isDate(periodInterval.start, inSameDayAs: currentPeriodInterval.start) }
    private var canMoveForward: Bool { periodInterval.start < currentPeriodInterval.start }

    private func interval(containing date: Date) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        switch period {
        case .day:
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return DateInterval(start: day, end: end)
        case .week:
            let weekday = calendar.component(.weekday, from: day)
            let daysAfterMonday = (weekday + 5) % 7
            let start = calendar.date(byAdding: .day, value: -daysAfterMonday, to: day) ?? day
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? day
            return DateInterval(start: start, end: end)
        case .month:
            return calendar.dateInterval(of: .month, for: day) ?? DateInterval(start: day, duration: 31 * 86_400)
        }
    }

    /// 所有统计先归入每天，再由每日数据向上汇总到周/月。
    /// 这样任务重命名后，三个周期始终读取同一条最新会话记录。
    private var dailySessionBuckets: [Date: [FocusSession]] {
        Dictionary(
            grouping: model.sessions.filter { periodInterval.contains($0.startedAt) },
            by: { calendar.startOfDay(for: $0.startedAt) }
        )
    }

    private var periodData: [DailyFocus] {
        let buckets = dailySessionBuckets
        var date = periodInterval.start
        var result: [DailyFocus] = []
        while date < periodInterval.end {
            let day = calendar.startOfDay(for: date)
            let minutes = buckets[day, default: []].reduce(0) { $0 + $1.minutes }
            result.append(DailyFocus(date: date, minutes: minutes))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private var weeklyData: [WeeklyFocus] {
        // 按自然月分周：每周从周一开始到周日结束（标准周）
        // 首周从本月1号开始（可能不是周一），末周到本月最后一天（可能不是周日）
        guard !periodData.isEmpty else { return [] }
        let monthStart = periodData.first!.date // 本月1号

        // 找到包含本月1号的那个"自然周"的周一
        let wd = calendar.component(.weekday, from: monthStart) // 1=Sun ... 7=Sat
        let daysAfterMonday = (wd + 5) % 7                    // Mon→0, Tue→1, ..., Sun→6
        guard let firstWeekMonday = calendar.date(byAdding: .day, value: -daysAfterMonday, to: monthStart) else { return [] }

        // 本月最后一天（用于判断是否超出范围）
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart),
              let monthLastDay = calendar.date(byAdding: .day, value: -1, to: monthEnd) else { return [] }

        var result: [WeeklyFocus] = []
        var currentMonday = firstWeekMonday
        var weekIndex = 1

        while true {
            // 本周自然范围：周一 ~ 周日
            guard let weekSunday = calendar.date(byAdding: .day, value: 6, to: currentMonday) else { break }

            // 截断到本月范围内
            let effectiveStart = max(currentMonday, monthStart)
            let effectiveEnd   = min(weekSunday, monthLastDay)

            // 聚合本周数据（未来周自然为 0，显示淡紫占位）
            let weekMinutes = periodData.filter { d in
                d.date >= effectiveStart && d.date <= effectiveEnd
            }.reduce(0) { $0 + $1.minutes }

            result.append(WeeklyFocus(
                startDate: effectiveStart,
                endDate: effectiveEnd,
                minutes: weekMinutes,
                index: weekIndex
            ))

            weekIndex += 1
            guard let nextMonday = calendar.date(byAdding: .weekOfYear, value: 1, to: currentMonday) else { break }
            currentMonday = nextMonday

            // 下周一已经超出本月 → 停止
            if currentMonday > monthEnd { break }
        }

        return result
    }

    // ── 按日模式：24 小时时段数据 ──
    private var hourlyData: [HourlyFocus] {
        guard period == .day else { return [] }
        var hours: [HourlyFocus] = (0..<24).map { h in
            HourlyFocus(hour: h, label: "\(String(format: "%02d", h)):00", minutes: 0)
        }
        for session in periodSessions {
            let h = calendar.component(.hour, from: session.startedAt)
            if h >= 0 && h < 24 {
                hours[h].minutes += session.minutes
            }
        }
        return hours
    }

    private var yMax: Int {
        let maxMinutes = hourlyData.map(\.minutes).max() ?? 0
        let rounded = max(30, ((maxMinutes + 9) / 10) * 10)
        return rounded
    }

    private var periodSessions: [FocusSession] {
        dailySessionBuckets.values
            .flatMap { $0 }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var periodReminderEvents: [ReminderEvent] {
        model.reminderEvents
            .filter { periodInterval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var pendingReminderEvents: [ReminderEvent] { periodReminderEvents.filter { !$0.completed } }
    private var periodFocusMinutes: Int { periodSessions.reduce(0) { $0 + $1.minutes } }
    private var periodCompletedSessions: Int { periodSessions.filter { $0.result == .done }.count }
    private var periodReminderHandledCount: Int { periodReminderEvents.filter(\.completed).count }
    private var periodPlanItems: [DailyPlanItem] {
        model.dailyPlanItems.filter { periodInterval.contains($0.date) }
    }
    private var periodCompletedPlanItems: Int {
        periodPlanItems.filter { $0.status == .completed }.count
    }

    private var taskDistribution: [TaskFocus] {
        let groups = Dictionary(grouping: periodSessions, by: { normalizedTask($0.task) })
        return groups.map { TaskFocus(task: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted {
                if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
                return $0.task.localizedStandardCompare($1.task) == .orderedAscending
            }
    }

    /// 任务名或时长变化时重建图表；使用完整内容签名，避免异或哈希抵消。
    private var sessionsRevision: String {
        periodSessions.map {
            "\($0.id.uuidString):\($0.task):\($0.minutes)"
        }.joined(separator: "|")
    }

    private var reviewTitle: String {
        switch period {
        case .day: "今日统计"
        case .week: "本周统计"
        case .month: "本月统计"
        }
    }

    private var periodSubtitle: String {
        switch period {
        case .day:
            return periodInterval.start.formatted(.dateTime.year().month().day().weekday(.wide))
        case .week:
            let end = calendar.date(byAdding: .day, value: -1, to: periodInterval.end) ?? periodInterval.end
            return "\(periodInterval.start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day())) · 周一至周日"
        case .month:
            return periodInterval.start.formatted(.dateTime.year().month(.wide))
        }
    }

    private var axisDates: [Date] {
        if period != .month { return periodData.map(\.date) }
        return periodData.enumerated().compactMap { index, item in
            let day = index + 1
            return day == 1 || (day % 5 == 0 && day <= 25) || day == periodData.count ? item.date : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    metricsRow
                    HStack(spacing: 14) {
                        focusChart
                        taskDistributionPanel
                    }
                    .frame(height: 340)
                    HStack(alignment: .top, spacing: 14) {
                        dailyOrSessionBreakdown
                        reminderPanel
                    }
                    .frame(minHeight: 300)
                }
                .padding(.bottom, 150)
            }
        }
        .padding(28)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(reviewTitle).font(.system(size: 22, weight: .semibold))
                Text(periodSubtitle).font(.system(size: 10)).foregroundStyle(Color.fdMuted)
            }
            Spacer()
            HStack(spacing: 10) {
                Picker("统计范围", selection: $period) {
                    ForEach(ReviewPeriod.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)

                datePill

                Button { movePeriod(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(ReviewNavButtonStyle())

                Button { movePeriod(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(ReviewNavButtonStyle())
                    .disabled(!canMoveForward)

                if !isCurrentPeriod {
                    Button(resetTitle) { anchorDate = Date() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var datePill: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { showCalendar.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fdPurple)
                Text(periodSubtitle)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.fdMuted)
            }
            .foregroundStyle(Color.fdInk)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Color.fdPanel)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.fdLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            CalendarPopover(selection: $anchorDate, onPick: { showCalendar = false })
                .environmentObject(model)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "专注时间",
                value: fmtFocus(periodFocusMinutes),
                unit: "",
                color: .fdPurple,
                symbol: "timer",
                timeComponents: (hours: periodFocusMinutes / 60, minutes: periodFocusMinutes % 60)
            )
            MetricCard(
                title: "专注记录",
                value: "\(periodSessions.count)",
                unit: "轮",
                color: .fdCoral,
                symbol: "chart.bar.doc.horizontal"
            )
            MetricCard(
                title: "完成专注",
                value: "\(periodCompletedSessions)",
                unit: "轮",
                color: .fdGreen,
                symbol: "checkmark.circle"
            )
            MetricCard(
                title: "提醒处理",
                value: "\(periodReminderHandledCount)/\(periodReminderEvents.count)",
                unit: "次",
                color: .fdBlue,
                symbol: "bell"
            )
            MetricCard(
                title: "计划完成",
                value: "\(periodCompletedPlanItems)/\(periodPlanItems.count)",
                unit: "项",
                color: .fdPurple,
                symbol: "calendar.badge.checkmark"
            )
        }
    }

    private var completionRate: Int {
        guard periodSessions.count > 0 else { return 0 }
        return Int((Double(periodCompletedSessions) / Double(periodSessions.count) * 100).rounded())
    }

    private var focusTimeValue: String { fmtFocus(periodFocusMinutes) }
    private var focusTimeUnit: String { "" }

    private var dailyAverageValue: String { fmtFocus(dailyAverage) }
    private var dailyAverageUnit: String { "" }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            return "\(h)"
        } else {
            return "\(minutes)"
        }
    }

    /// 剩余不足1小时的分钟数（仅当总时长≥60分钟时有值）
    private func remainderMinutes(_ total: Int) -> Int? {
        guard total >= 60 else { return nil }
        let r = total % 60
        return r > 0 ? r : nil
    }

    private var reminderRate: Int {
        guard periodReminderEvents.count > 0 else { return 0 }
        return Int((Double(periodReminderHandledCount) / Double(periodReminderEvents.count) * 100).rounded())
    }

    private var focusChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── 标题栏 + 上下文感知的下拉菜单 ──
            HStack {
                Text(chartTitle).font(.system(size: 14, weight: .semibold))
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.fdMuted)
                Spacer()
                chartDropdown
            }

            // ── 图表内容（根据 period + granularity 切换） ──
            ZStack(alignment: .topLeading) {
                switch period {
                case .day:
                    // 日模式：24 小时时段柱状图
                    hourlyChartView
                case .week:
                    // 周模式：固定按天显示
                    weeklyDailyChartView
                case .month:
                    // 月模式：按日 / 按周 可切换
                    if chartGranularity == .day {
                        dailyBarChartView
                    } else {
                        weeklyBarChartView
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panel()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 标题

    private var chartTitle: String {
        switch period {
        case .day: return "今日时段分布"
        case .week: return "本周每日分布"
        case .month: return chartGranularity == .day ? "本月每日分布" : "本月每周分布"
        }
    }

    // MARK: - 下拉菜单（上下文感知）

    @ViewBuilder
    private var chartDropdown: some View {
        switch period {
        case .day:
            // 日模式：仅显示"时间段"标签，无需下拉
            HStack(spacing: 4) {
                Text("0–24h").font(.system(size: 11, weight: .medium))
                Image(systemName: "clock").font(.system(size: 9))
            }
            .foregroundStyle(Color.fdPurple)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.fdPurple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.fdPurple.opacity(0.25), lineWidth: 1))

        case .week:
            // 周模式：固定显示按天，无需下拉
            HStack(spacing: 4) {
                Text("按天").font(.system(size: 11, weight: .medium))
                Image(systemName: "calendar.day").font(.system(size: 9))
            }
            .foregroundStyle(Color.fdPurple)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.fdPurple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.fdPurple.opacity(0.25), lineWidth: 1))

        case .month:
            // 月模式：按日 / 按周 子选项
            Menu {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { chartGranularity = .day }
                } label: { Label("按日", systemImage: chartGranularity == .day ? "checkmark" : "") }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { chartGranularity = .week }
                } label: { Label("按周", systemImage: chartGranularity == .week ? "checkmark" : "") }
            } label: {
                dropdownLabel(chartGranularity == .day ? "按日" : "按周")
            }
        }
    }

    private func dropdownLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 11, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Color.fdMuted)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.fdPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }

    // MARK: - 日模式：24 小时时段图

    private var hourlyChartView: some View {
        Chart(hourlyData) { item in
            BarMark(
                x: .value("时段", Double(item.hour) + 0.5),
                y: .value("分钟", item.minutes),
                width: .fixed(12)
            )
            .foregroundStyle(Color.fdPurple.gradient.opacity(item.minutes > 0 ? 1 : 0.2))
            .cornerRadius(3)
            .annotation(position: .top) {
                if item.minutes > 0 {
                    Text("\(item.minutes)").font(.system(size: 8)).foregroundStyle(Color.fdMuted)
                }
            }
        }
        .chartXScale(domain: 0 ... 24)
        .chartYScale(domain: 0 ... Double(yMax))
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 24, by: 2)).map(Double.init)) { value in
                AxisValueLabel(anchor: .topLeading) {
                    if let h = value.as(Double.self) {
                        Text("\(String(format: "%02d", Int(h)))")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.fdMuted)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(Color.fdLine.opacity(0.4))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text("\(m)").foregroundStyle(Color.fdMuted)
                    }
                }
                AxisGridLine().foregroundStyle(Color.fdLine.opacity(0.7))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotFrame!]
                ZStack {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let x = location.x - plotFrame.origin.x
                                if let posX: Double = proxy.value(atX: x) {
                                    let h = max(0, min(23, Int(floor(posX - 0.5))))
                                    hoveredHour = hourlyData.first(where: { $0.hour == h })
                                    hoveredLocation = location
                                }
                            case .ended:
                                hoveredHour = nil
                                hoveredLocation = nil
                            }
                        }
                    if let h = hoveredHour, let loc = hoveredLocation {
                        HourlyTooltip(hour: h)
                            .position(x: min(max(loc.x, 55), geo.size.width - 55), y: max(loc.y - 52, 42))
                    }
                }
            }
        }
    }

    // MARK: - 按日视图：每天一根紫色柱（排满所有天）

    private var dailyBarChartView: some View {
        Chart(periodData) { item in
            BarMark(
                x: .value("日期", item.date, unit: .day),
                y: .value("分钟", max(item.minutes, 0))
            )
            .foregroundStyle(Color.fdPurple.gradient.opacity(item.minutes > 0 ? 1 : 0.18))
            .cornerRadius(3)
            .annotation(position: .top) {
                if item.minutes > 0 {
                    Text("\(item.minutes)").font(.system(size: 8)).foregroundStyle(Color.fdMuted)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: periodData.map(\.date)) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        let day = calendar.component(.day, from: date)
                        Text("\(day)")
                            .font(.system(size: 9))
                            .foregroundStyle(day % 5 == 1 || day == 1 ? Color.fdMuted : Color.fdMuted.opacity(0.45))
                    }
                }
                AxisGridLine()
                    .foregroundStyle(Color.fdLine.opacity(0.35))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text("\(minutes)").foregroundStyle(Color.fdMuted)
                    }
                }
                AxisGridLine().foregroundStyle(Color.fdLine.opacity(0.7))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotFrame!]
                ZStack {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let x = location.x - plotFrame.origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    let day = calendar.startOfDay(for: date)
                                    hoveredDay = periodData.first { calendar.isDate($0.date, inSameDayAs: day) }
                                    hoveredLocation = location
                                }
                            case .ended:
                                hoveredDay = nil
                                hoveredLocation = nil
                            }
                        }
                    if let day = hoveredDay, let loc = hoveredLocation {
                        FocusTooltip(day: day, sessions: sessionsCount(for: day.date))
                            .position(x: min(max(loc.x, 75), geo.size.width - 75), y: max(loc.y - 58, 42))
                    }
                }
            }
        }
    }

    // MARK: - 周模式：本周每日分布（周一～周日 + 日期）

    private var weeklyDailyChartView: some View {
        let weekDays = generateWeekDays()
        return Chart(weekDays) { item in
            BarMark(
                x: .value("星期", Double(item.weekdayIndex) + 0.5),
                y: .value("分钟", item.minutes),
                width: .fixed(28)
            )
            .foregroundStyle(Color.fdPurple.gradient.opacity(item.minutes > 0 ? 1 : 0.18))
            .cornerRadius(4)
            .annotation(position: .top) {
                if item.minutes > 0 {
                    Text("\(item.minutes)").font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.fdMuted)
                }
            }
        }
        .chartXScale(domain: 0 ... 7)
        .chartYScale(domain: 0 ... Double(weekYMax))
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0.5, through: 6.5, by: 1))) { value in
                AxisValueLabel(anchor: .top) {
                    if let idx = value.as(Double.self), let dayIdx = Int(exactly: idx - 0.5),
                       dayIdx >= 0 && dayIdx < weekDays.count {
                        let d = weekDays[dayIdx]
                        VStack(spacing: 1) {
                            Text(d.weekdayName)
                                .font(.system(size: 10, weight: .medium))
                            Text(d.dateString)
                                .font(.system(size: 8))
                                .foregroundStyle(Color.fdMuted)
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text("\(m)").foregroundStyle(Color.fdMuted)
                    }
                }
                AxisGridLine().foregroundStyle(Color.fdLine.opacity(0.7))
            }
        }
    }

    private struct WeekDayItem: Identifiable {
        let weekdayIndex: Int // 0=周一, 6=周日
        let weekdayName: String
        let dateString: String
        let minutes: Int
        var id: Int { weekdayIndex }
    }

    private func generateWeekDays() -> [WeekDayItem] {
        let symbols = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchorDate)) else { return [] }
        return (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: i, to: startOfWeek)!
            let minutes = periodData.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.minutes ?? 0
            return WeekDayItem(
                weekdayIndex: i,
                weekdayName: symbols[i],
                dateString: date.formatted(.dateTime.month(.abbreviated).day()),
                minutes: minutes
            )
        }
    }

    private var weekYMax: Int {
        let days = generateWeekDays()
        let maxMinutes = days.map(\.minutes).max() ?? 0
        return max(30, ((maxMinutes + 19) / 20) * 20)
    }

    // MARK: - 按周视图：本月每周分布（第N周 + 日期范围）

    private var weeklyBarChartView: some View {
        Chart(weeklyData) { item in
            BarMark(
                x: .value("周", Double(item.index) - 0.5),
                y: .value("分钟", max(item.minutes, item.minutes > 0 ? 1 : 2)),
                width: .fixed(32)
            )
            .foregroundStyle(Color.fdPurple.gradient.opacity(item.minutes > 0 ? 1 : 0.18))
            .cornerRadius(4)
            .annotation(position: .top) {
                if item.minutes > 0 {
                    Text("\(item.minutes)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.fdMuted)
                }
            }
        }
        .chartXScale(domain: 0 ... Double(weeklyData.count))
        .chartYScale(domain: 0 ... Double(monthWeekYMax))
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0.5, through: Double(weeklyData.count) - 0.5, by: 1))) { value in
                AxisValueLabel(anchor: .top) {
                    if let idx = value.as(Double.self), let weekIdx = Int(exactly: idx - 0.5),
                       weekIdx >= 0 && weekIdx < weeklyData.count {
                        let w = weeklyData[weekIdx]
                        VStack(spacing: 2) {
                            Text("第\(w.index)周")
                                .font(.system(size: 10, weight: .medium))
                            Text("\(weekDateRange(w))")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.fdMuted)
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text("\(m)").foregroundStyle(Color.fdMuted)
                    }
                }
                AxisGridLine().foregroundStyle(Color.fdLine.opacity(0.7))
            }
        }
    }

    private func weekDateRange(_ week: WeeklyFocus) -> String {
        let startFmt = week.startDate.formatted(.dateTime.month(.abbreviated).day())
        let endFmt = week.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(startFmt)–\(endFmt)"
    }

    private var monthWeekYMax: Int {
        let maxMinutes = weeklyData.map(\.minutes).max() ?? 0
        return max(30, ((maxMinutes + 49) / 50) * 50)
    }

    private func sessionsCount(for date: Date) -> Int {
        periodSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.count
    }

    private var taskDistributionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 5) {
                    Text("专注时长分布").font(.system(size: 14, weight: .semibold))
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fdMuted)
                }
                Spacer()
                Text(rangeLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.fdMuted)
            }

            if taskDistribution.isEmpty {
                EmptyState(text: "完成专注后显示占比", minHeight: 180)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 18) {
                    VStack(spacing: 12) {
                        TaskDonutChart(
                            items: taskDistribution,
                            totalMinutes: periodFocusMinutes,
                            color: taskColor
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        summaryBar
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    distributionList
                        .frame(width: 178)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panel()
        .animation(nil, value: chartGranularity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 当会话任务名被编辑时，强制刷新分布图（确保日/周/月视图同步）
        .id(sessionsRevision)
    }

    private var distributionList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("任务").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.fdMuted)
                Spacer()
                Text("时长").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.fdMuted).frame(width: 48, alignment: .trailing)
                Text("占比").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.fdMuted).frame(width: 36, alignment: .trailing)
            }
            .padding(.bottom, 2)

            ForEach(Array(taskDistribution.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Circle().fill(taskColor(index)).frame(width: 8, height: 8)
                    Text(item.task)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 2) {
                        if item.minutes >= 60 {
                            Text("\(item.minutes / 60)h")
                            Text(item.minutes % 60 > 0 ? "\(item.minutes % 60)min" : "").font(.system(size: 8))
                        } else {
                            Text("\(item.minutes)min")
                        }
                    }
                        .font(.system(size: 9))
                        .foregroundStyle(Color.fdMuted)
                        .frame(width: 48, alignment: .trailing)
                    Text("\(percent(item.minutes, of: periodFocusMinutes))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .frame(width: 36, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fdPurple)
            Text("总计 \(fmtFocus(periodFocusMinutes))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdPurple)
            Circle().fill(Color.fdPurple.opacity(0.4)).frame(width: 3, height: 3)
            Text("日均 \(fmtFocus(dailyAverage))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdPurple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.fdPurple.opacity(0.10))
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var rangeLabel: String {
        let start = periodInterval.start.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let endDate = calendar.date(byAdding: .day, value: -1, to: periodInterval.end) ?? periodInterval.end
        let end = min(endDate, Date())
        return "\(start) ～ \(end.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))"
    }

    private var dailyOrSessionBreakdown: some View {
        ReviewDetailPanel(
            title: period == .day ? "当天记录" : (period == .month ? "每周明细" : "每日明细"),
            trailing: period == .day
                ? "\(periodSessions.count) 条"
                : (period == .month
                    ? "\(weeklyData.filter { $0.minutes > 0 }.count) 周有记录"
                    : "\(periodData.filter { $0.minutes > 0 }.count) 天有记录")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if period == .day {
                    if periodSessions.isEmpty {
                        EmptyState(text: "当天还没有专注记录", minHeight: 210)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(periodSessions) { session in
                                SessionShareRow(session: session, percent: percent(session.minutes, of: periodFocusMinutes))
                                Divider().overlay(Color.fdLine)
                            }
                        }
                    }
                } else if period == .month {
                    let activeWeeks = weeklyData.filter { $0.minutes > 0 }
                    if activeWeeks.isEmpty {
                        EmptyState(text: "本月还没有专注记录", minHeight: 210)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(activeWeeks) { week in
                                WeekShareRow(label: weekBreakdownLabel(for: week), minutes: week.minutes, percent: percent(week.minutes, of: periodFocusMinutes))
                                Divider().overlay(Color.fdLine)
                            }
                        }
                    }
                } else {
                    let activeDays = periodData.filter { $0.minutes > 0 }
                    if activeDays.isEmpty {
                        EmptyState(text: "本周还没有专注记录", minHeight: 210)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(activeDays) { item in
                                DayShareRow(label: dayBreakdownLabel(for: item.date), minutes: item.minutes, percent: percent(item.minutes, of: periodFocusMinutes))
                                Divider().overlay(Color.fdLine)
                            }
                        }
                    }
                }

                if period != .day {
                    Button {
                        showAllDetails = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看全部明细")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.fdPurple)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
        }
        .sheet(isPresented: $showAllDetails) {
            (period == .month
                ? AllDetailsSheet(
                    title: "每周明细",
                    items: weeklyData.filter { $0.minutes > 0 }
                        .map { DetailItem(label: weekBreakdownLabel(for: $0), minutes: $0.minutes) },
                    totalMinutes: periodFocusMinutes
                )
                : AllDetailsSheet(
                    title: "每日明细",
                    items: periodData.filter { $0.minutes > 0 }
                        .map { DetailItem(label: $0.date.formatted(.dateTime.month().day().weekday(.wide)), minutes: $0.minutes) },
                    totalMinutes: periodFocusMinutes
                ))
                .environmentObject(model)
        }
    }

    private var reminderPanel: some View {
        ReviewDetailPanel(
            title: "提醒记录",
            trailing: "\(periodReminderHandledCount)/\(periodReminderEvents.count)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(ReminderFilter.allCases) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { reminderFilter = filter }
                        } label: {
                            Text(filter.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(reminderFilter == filter ? .white : Color.fdMuted)
                                .padding(.horizontal, 14)
                                .frame(height: 28)
                                .background(reminderFilter == filter ? Color.fdPurple : Color.fdPanel)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(reminderFilter == filter ? Color.clear : Color.fdLine, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }

                if periodReminderEvents.isEmpty {
                    EmptyState(text: "暂无提醒记录", minHeight: 180)
                } else if reminderFilter == .pending {
                    pendingColumn
                } else if reminderFilter == .done {
                    doneColumn
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        pendingColumn
                        Divider().overlay(Color.fdLine)
                        doneColumn
                    }
                }
            }
        }
    }

    private var pendingColumn: some View {
        let events = pendingReminderEvents
        return VStack(alignment: .leading, spacing: 10) {
            Text("未处理 (\(events.count))").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.fdCoral)
            if events.isEmpty {
                Text("暂无未处理提醒").font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            } else {
                ForEach(events.prefix(6)) { event in ReminderEventRow(event: event) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneColumn: some View {
        let events = periodReminderEvents.filter(\.completed)
        return VStack(alignment: .leading, spacing: 10) {
            Text("最近处理 (\(events.count))").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.fdMuted)
            if events.isEmpty {
                Text("暂无已处理提醒").font(.system(size: 9)).foregroundStyle(Color.fdMuted)
            } else {
                ForEach(events.prefix(6)) { event in ReminderEventRow(event: event) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previousTitle: String {
        switch period {
        case .day: "前一天"
        case .week: "上一周"
        case .month: "上个月"
        }
    }

    private var nextTitle: String {
        switch period {
        case .day: "后一天"
        case .week: "下一周"
        case .month: "下个月"
        }
    }

    private var resetTitle: String {
        switch period {
        case .day: "回到今天"
        case .week: "回到本周"
        case .month: "回到本月"
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch period {
        case .day:
            return date.formatted(.dateTime.month().day())
        case .week:
            return weekdayLabel(for: date)
        case .month:
            return "\(calendar.component(.day, from: date))"
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 2: "一"
        case 3: "二"
        case 4: "三"
        case 5: "四"
        case 6: "五"
        case 7: "六"
        default: "日"
        }
    }

    private func dayBreakdownLabel(for date: Date) -> String {
        "\(date.formatted(.dateTime.month().day())) · 周\(weekdayLabel(for: date))"
    }

    private func weekBreakdownLabel(for week: WeeklyFocus) -> String {
        "\(week.startDate.formatted(.dateTime.month().day()))–\(week.endDate.formatted(.dateTime.month().day())) · 第\(week.index)周"
    }

    private func normalizedTask(_ task: String) -> String {
        let value = task.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未命名专注" : value
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }

    private func taskColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.10, green: 0.58, blue: 0.92),
            Color(red: 0.18, green: 0.78, blue: 0.34),
            Color(red: 0.98, green: 0.54, blue: 0.18),
            Color(red: 0.62, green: 0.47, blue: 0.90),
            Color(red: 0.92, green: 0.35, blue: 0.55),
            Color(red: 0.20, green: 0.72, blue: 0.80)
        ]
        return palette[index % palette.count]
    }

    private func movePeriod(_ direction: Int) {
        guard direction < 0 || canMoveForward else { return }
        let next: Date?
        switch period {
        case .day:
            next = calendar.date(byAdding: .day, value: direction, to: anchorDate)
        case .week:
            next = calendar.date(byAdding: .day, value: direction * 7, to: anchorDate)
        case .month:
            next = calendar.date(byAdding: .month, value: direction, to: anchorDate)
        }
        if let next { anchorDate = min(next, Date()) }
    }
}

private enum ReviewPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }
}

private enum ChartGranularity: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }
}

private enum ReminderFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case done

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .pending: "未处理"
        case .done: "已处理"
        }
    }
}

private struct ReviewNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.fdMuted)
            .frame(width: 32, height: 32)
            .background(configuration.isPressed ? Color.fdLine : Color.fdPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
    }
}

private struct DailyFocus: Identifiable {
    let date: Date
    let minutes: Int
    var id: Date { date }
}

private struct WeeklyFocus: Identifiable {
    let startDate: Date
    let endDate: Date
    let minutes: Int
    let index: Int
    var id: Date { startDate }
}

private struct HourlyFocus: Identifiable {
    let hour: Int
    let label: String
    var minutes: Int
    var id: Int { hour }
}

private struct DetailItem: Identifiable {
    let id = UUID()
    let label: String
    let minutes: Int
}

private struct TaskFocus: Identifiable {
    let task: String
    let minutes: Int
    var id: String { task }
}

private struct TaskDonutChart: View {
    let items: [TaskFocus]
    let totalMinutes: Int
    let color: (Int) -> Color

    private struct Slice: Identifiable {
        let id: String
        let title: String
        let minutes: Int
        let percent: Int
        let start: Double
        let end: Double
        let index: Int

        var mid: Double { (start + end) / 2 }
    }

    private var displayItems: [TaskFocus] {
        guard items.count > 6 else { return items }
        let leading = Array(items.prefix(5))
        let otherMinutes = items.dropFirst(5).reduce(0) { $0 + $1.minutes }
        return leading + [TaskFocus(task: "其他", minutes: otherMinutes)]
    }

    private var slices: [Slice] {
        guard totalMinutes > 0 else { return [] }
        var cursor = -90.0
        return displayItems.enumerated().map { index, item in
            let span = Double(item.minutes) / Double(totalMinutes) * 360
            let start = cursor
            let end = cursor + span
            cursor = end
            return Slice(
                id: item.task,
                title: item.task,
                minutes: item.minutes,
                percent: Int((Double(item.minutes) / Double(totalMinutes) * 100).rounded()),
                start: start,
                end: end,
                index: index
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height + 18)
            let center = CGPoint(x: proxy.size.width * 0.50, y: proxy.size.height * 0.56)
            let outerRadius = min(130, side * 0.42)
            let innerRadius = outerRadius * 0.55
            let labelRadius = outerRadius * 0.78
            let s = max(0.72, outerRadius / 100)
            let showLabels = outerRadius >= 90
            let compact = outerRadius < 80

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.fdPurple.opacity(0.13), Color.fdPurple.opacity(0.03), .clear],
                            center: .center,
                            startRadius: 18,
                            endRadius: outerRadius + 26
                        )
                    )
                    .frame(width: (outerRadius + 26) * 2, height: (outerRadius + 26) * 2)
                    .position(center)

                ForEach(slices) { slice in
                    let gap = min(1.2, max(0.12, (slice.end - slice.start) * 0.16))
                    DonutSliceShape(
                        startAngle: .degrees(slice.start + gap),
                        endAngle: .degrees(slice.end - gap),
                        innerRadiusRatio: innerRadius / outerRadius
                    )
                    .fill(color(slice.index))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .position(center)
                    .shadow(color: color(slice.index).opacity(0.18), radius: 7, y: 3)
                }

                Circle()
                    .fill(Color.fdPanel.opacity(0.95))
                    .frame(width: innerRadius * 2 - 4, height: innerRadius * 2 - 4)
                    .overlay(Circle().stroke(Color.fdLine.opacity(0.78), lineWidth: 1))
                    .position(center)

                VStack(spacing: 2) {
                    if compact {
                        // 紧凑单行模式：8h 19min
                        Text(formatCompact(totalMinutes))
                            .font(.system(size: 16 * s, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.fdInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else if totalMinutes >= 60 {
                        HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                            Text("\(totalMinutes / 60)")
                                .font(.system(size: 24 * s, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.fdInk)
                            Text("小时")
                                .font(.system(size: 10 * s, weight: .semibold))
                                .foregroundStyle(Color.fdMuted)
                        }
                        if totalMinutes % 60 > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                                Text("\(totalMinutes % 60)")
                                    .font(.system(size: 18 * s, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.fdInk)
                                Text("分钟")
                                    .font(.system(size: 10 * s, weight: .semibold))
                                    .foregroundStyle(Color.fdMuted)
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                            Text("\(totalMinutes)")
                                .font(.system(size: 18 * s, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.fdInk)
                            Text("分钟")
                                .font(.system(size: 10 * s, weight: .semibold))
                                .foregroundStyle(Color.fdMuted)
                        }
                    }
                }
                .frame(width: max(0, innerRadius * 2 - 28), alignment: .center)
                .minimumScaleFactor(0.5)
                .position(center)

                ForEach(slices) { slice in
                    if showLabels && slice.percent >= 4 {
                        VStack(spacing: 1) {
                            if slice.percent >= 8 {
                                Text(shortTitle(slice.title))
                                    .font(.system(size: (slice.percent >= 10 ? 10 : 8) * s, weight: .bold))
                                    .lineLimit(1)
                            }
                            Text("\(slice.percent)%")
                                .font(.system(size: (slice.percent >= 10 ? 12 : 9) * s, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.34), radius: max(1, 2 * s))
                        .frame(width: (slice.percent >= 10 ? 68 : 42) * s)
                        .position(point(center: center, angle: slice.mid, radius: labelRadius))
                    }
                }
            }
        }
    }

    private func shortTitle(_ title: String) -> String {
        title.count > 4 ? String(title.prefix(4)) : title
    }

    private func formatCompact(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)min" }
        if h > 0 { return "\(h)h" }
        return "\(m)min"
    }

    private func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private func point(center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(radians(angle)) * radius,
            y: center.y + sin(radians(angle)) * radius
        )
    }
}

private struct DonutSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let symbol: String
    let timeComponents: (hours: Int, minutes: Int)?

    init(title: String, value: String, unit: String, color: Color, symbol: String, timeComponents: (hours: Int, minutes: Int)? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.color = color
        self.symbol = symbol
        self.timeComponents = timeComponents
    }

    private var valueSize: CGFloat { value.contains("/") ? 22 : 27 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.fdMuted)
                Spacer()
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let time = timeComponents {
                    timeValueContent(hours: time.hours, minutes: time.minutes)
                } else {
                    Text(value)
                        .font(.system(size: valueSize, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.fdInk)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Text(unit).font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(padding: 16)
    }

    private func timeValueContent(hours: Int, minutes: Int) -> some View {
        let unitSize: CGFloat = 11
        let gap: CGFloat = 6
        return HStack(alignment: .firstTextBaseline, spacing: 0.5) {
            if hours > 0 {
                Text("\(hours)")
                    .font(.system(size: valueSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.fdInk)
                Text("h")
                    .font(.system(size: unitSize, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
            }
            if hours > 0 && minutes > 0 {
                Spacer().frame(width: gap)
            }
            if minutes > 0 || hours == 0 {
                Text("\(minutes)")
                    .font(.system(size: valueSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.fdInk)
                Text("min")
                    .font(.system(size: unitSize, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
            }
        }
    }
}

private struct DonutLegendRow: View {
    let title: String
    let minutes: Int
    let percent: Int
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fdLine.opacity(0.65))
                        Capsule()
                            .fill(color.opacity(0.82))
                            .frame(width: max(4, proxy.size.width * CGFloat(percent) / 100))
                    }
                }
                .frame(height: 5)
                Text(fmtFocus(minutes))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

private struct DayShareRow: View {
    let label: String
    let minutes: Int
    let percent: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.fdInk)
                .frame(width: 90, alignment: .leading)
            VStack(spacing: 5) {
                HStack {
                    Text(fmtFocus(minutes)).font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("\(percent)%").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.fdMuted)
                }
                ProgressView(value: Double(percent), total: 100)
                    .tint(Color.fdPurple)
            }
        }
    }
}

private struct WeekShareRow: View {
    let label: String
    let minutes: Int
    let percent: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.fdInk)
                .frame(width: 118, alignment: .leading)
            VStack(spacing: 5) {
                HStack {
                    Text(fmtFocus(minutes)).font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("\(percent)%").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.fdMuted)
                }
                ProgressView(value: Double(percent), total: 100)
                    .tint(Color.fdPurple)
            }
        }
    }
}

private struct SessionShareRow: View {
    @EnvironmentObject private var model: AppModel
    let session: FocusSession
    let percent: Int
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isEditFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.fdMuted)
                .frame(width: 48, alignment: .leading)
            Circle().fill(session.result == .abandoned ? Color.fdMuted : (session.result == .interrupted ? Color.fdMuted : Color.fdCoral)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if isEditing {
                        TextField("任务名称", text: $editText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: 180)
                            .focused($isEditFocused)
                            .onSubmit { confirmEdit() }
                            .onAppear {
                                editText = session.task
                                DispatchQueue.main.async {
                                    isEditFocused = true
                                }
                            }
                            .onChange(of: isEditFocused) { _, focused in
                                if !focused && isEditing {
                                    confirmEdit()
                                }
                            }
                    } else {
                        Button {
                            editText = session.task
                            isEditing = true
                        } label: {
                            Text(session.task.isEmpty ? "未命名专注" : session.task)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(fmtFocus(session.minutes) + " · \(percent)%")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.fdMuted)
                }
                ProgressView(value: Double(percent), total: 100)
                    .tint(Color.fdPurple)
                // 放弃记录显示理由
                if session.result == .abandoned && !session.note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 8))
                        Text(session.note).font(.system(size: 9)).foregroundStyle(Color.fdMuted)
                    }
                }
            }
        }
        .onDisappear {
            // 切换日/周/月会直接销毁当前行；销毁前也必须写回正在编辑的名字。
            if isEditing {
                saveEditIfNeeded()
            }
        }
    }

    private func confirmEdit() {
        guard isEditing else { return }
        isEditing = false
        isEditFocused = false
        saveEditIfNeeded()
    }

    private func saveEditIfNeeded() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != session.task {
            model.updateSessionTask(id: session.id, newTask: trimmed)
        }
    }
}

private struct ReminderEventRow: View {
    let event: ReminderEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(event.completed ? Color.fdGreen : Color.fdCoral)
            Text(event.reminderName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.fdMuted)
        }
    }
}

private struct ReviewDetailPanel<Content: View>: View {
    let title: String
    let trailing: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(trailing)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.fdMuted)
            }
            .frame(height: 18)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)

            Spacer(minLength: 0)
        }
        .panel()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyState: View {
    let text: String
    var minHeight: CGFloat = 130

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 22))
                .foregroundStyle(Color.fdPurple)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(Color.fdMuted)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
    }
}

private struct FocusTooltip: View {
    let day: DailyFocus
    let sessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdInk)
            Text(fmtFocus(day.minutes))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.fdPurple)
            Text("\(sessions) 轮专注")
                .font(.system(size: 9))
                .foregroundStyle(Color.fdMuted)
        }
        .padding(10)
        .background(Color.fdPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

private struct WeekTooltip: View {
    let day: DailyFocus

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let weekday = calendar.component(.weekday, from: day.date)
            let daysAfterMonday = (weekday + 5) % 7
            let start = calendar.date(byAdding: .day, value: -daysAfterMonday,
                                      to: calendar.startOfDay(for: day.date)) ?? day.date
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start

            Text("\(start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdInk)
            Text(fmtFocus(day.minutes))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.fdPurple)
            if day.minutes > 0 {
                Text("本周专注合计")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fdMuted)
            } else {
                Text("暂无记录")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fdMuted.opacity(0.7))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.fdPanel)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdPurple.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.fdPurple.opacity(0.1), radius: 8, y: 3)
    }
}

private struct HourlyTooltip: View {
    let hour: HourlyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(String(format: "%02d", hour.hour)):00–\(String(format: "%02d", hour.hour + 1)):00")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.fdInk)
            Text(fmtFocus(hour.minutes))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.fdPurple)
            if hour.minutes > 0 {
                Text("专注记录")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fdMuted)
            } else {
                Text("暂无记录")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fdMuted.opacity(0.7))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.fdPanel)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.fdPurple.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.fdPurple.opacity(0.1), radius: 8, y: 3)
    }
}

private struct CalendarPopover: View {
    @Binding var selection: Date
    var onPick: () -> Void
    @EnvironmentObject private var model: AppModel

    @State private var displayMonth: Date = Date()

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    private var monthYearText: String {
        displayMonth.formatted(.dateTime.year().month(.wide))
    }

    private var days: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leadingDays)
        var date = monthInterval.start
        while date < monthInterval.end {
            result.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        while result.count % 7 != 0 {
            result.append(nil)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(monthYearText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.fdInk)
                Spacer()
                HStack(spacing: 6) {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(Color.fdMuted)
                    .frame(width: 24, height: 24)
                    .background(Color.fdPanel)
                    .clipShape(Circle())

                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(Color.fdMuted)
                    .frame(width: 24, height: 24)
                    .background(Color.fdPanel)
                    .clipShape(Circle())
                }
            }

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.fdMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible()), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        dayCell(date: date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }

            Button("完成") { onPick() }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { displayMonth = calendar.startOfDay(for: selection) }
    }

    private func dayCell(date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDate(date, inSameDayAs: Date())
        let isFuture = date > Date()

        return Button {
            selection = date
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(foregroundFor(isSelected: isSelected, isToday: isToday, isFuture: isFuture))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.fdPurple : (isToday ? Color.fdPurple.opacity(0.15) : Color.clear))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func foregroundFor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isSelected { return .white }
        if isFuture { return Color.fdMuted.opacity(0.4) }
        if isToday { return Color.fdPurple }
        return Color.fdInk
    }

    private func shiftMonth(_ direction: Int) {
        displayMonth = calendar.date(byAdding: .month, value: direction, to: displayMonth) ?? displayMonth
    }
}

private struct AllDetailsSheet: View {
    let title: String
    let items: [DetailItem]
    let totalMinutes: Int
    @Environment(\.dismiss) private var dismiss

    private func share(_ value: Int) -> Int {
        guard totalMinutes > 0 else { return 0 }
        return Int((Double(value) / Double(totalMinutes) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.fdMuted)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Text(item.label)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 150, alignment: .leading)
                            Text(fmtFocus(item.minutes))
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("\(share(item.minutes))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.fdMuted)
                        }
                        Divider().overlay(Color.fdLine)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440, height: 460)
    }
}

/// 统一的专注时长显示：≥60 分钟以小时计（如 1h30min），否则 Xmin
private func fmtFocus(_ minutes: Int) -> String {
    if minutes >= 60 {
        let h = minutes / 60
        let rm = minutes % 60
        return rm > 0 ? "\(h)h\(rm)min" : "\(h)h"
    }
    return "\(minutes)min"
}
