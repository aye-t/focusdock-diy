"use client";

import { useMemo, useState } from "react";

/* ───────────────────────────────────────────────
   吐息猫 · 每日专注（按时段/小时）

   不是"每天一个大方块"，而是：
   一天 24 小时，每个小时一个小胶囊柱体，
   高矮 = 那个小时专注了多少分钟。
   像猫咪走过留下的一串小脚印 🐾
────────────────────────────────────────────── */

type HourFocusPoint = {
  hour: number;         // 0-23
  label: string;        // "06:00"
  minutes: number;      // 该小时专注了多少分钟
  sessions: number;     // 该小时完成了几轮
};

type DailyFocusChartProps = {
  /** 当天按小时聚合的专注数据，长度 24 */
  data: HourFocusPoint[];
  /** 当前高亮的小时（可选，用于标记"现在"） */
  currentHour?: number;
};

export default function DailyFocusChart({ data, currentHour }: DailyFocusChartProps) {
  const [hover, setHover] = useState<HourFocusPoint | null>(null);
  const [tooltipPos, setTooltipPos] = useState({ x: 0, y: 0 });

  const maxMinutes = useMemo(() => Math.max(10, ...data.map((d) => d.minutes)), [data]);
  const totalMinutes = useMemo(() => data.reduce((s, d) => s + d.minutes, 0), [data]);
  const activeHours = useMemo(() => data.filter((d) => d.minutes > 0).length, [data]);

  /* ── 布局参数 ── */
  const cellWidth = 32;        // 每个小时格子宽度
  const gap = 4;               // 格子间距
  const maxBarHeight = 100;     // 柱子最大高度
  const barMaxWidth = 18;       // 胶囊最大宽度（有数据时）
  const barMinWidth = 8;        // 胶囊最小宽度（无数据时）
  const plotWidth = data.length * (cellWidth + gap) - gap;
  const chartHeight = 170;
  const baselineY = chartHeight - 28;

  return (
    <section className="daily-focus panel">
      {/* 标题栏 */}
      <div className="panel-header">
        <h2>每日专注</h2>
        <div className="dropdown">
          <button className="dropdown-trigger">
            今日
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="6 9 12 15 18 9" />
            </svg>
          </button>
        </div>
      </div>

      {/* 汇总行 */}
      <div className="hourly-summary">
        <span className="summary-item">
          <strong>{totalMinutes}</strong> 分钟
        </span>
        <span className="summary-divider">·</span>
        <span className="summary-item">
          覆盖 <strong>{activeHours}</strong> 个时段
        </span>
        <span className="summary-divider">·</span>
        <span className="summary-item muted">
          最高单时 <strong>{maxMinutes}</strong> 分
        </span>
      </div>

      {/* 图表区域 */}
      <div className="chart-wrap hourly-chart-wrap" style={{ height: chartHeight }}>
        <svg
          viewBox={`0 0 ${plotWidth} ${chartHeight}`}
          preserveAspectRatio="xMinYMid meet"
          style={{ width: "100%", overflow: "visible" }}
        >
          <defs>
            {/* 有数据时的暖色渐变 */}
            <linearGradient id="catPawGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#f5c6b6" />
              <stop offset="60%" stopColor="#e8a89a" />
              <stop offset="100%" stopColor="#d9898e" />
            </linearGradient>
            {/* hover 加深 */}
            <linearGradient id="catPawHover" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#eeb4a3" />
              <stop offset="60%" stopColor="#dc9082" />
              <stop offset="100%" stopColor="#cc7077" />
            </linearGradient>
            {/* 当前小时的发光版 */}
            <linearGradient id="catPawActive" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#f9d9cc" />
              <stop offset="50%" stopColor="#f0b8a5" />
              <stop offset="100%" stopColor="#e09590" />
            </linearGradient>
            {/* 空闲时段的淡色 */}
            <linearGradient id="catPawEmpty" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#f2edef" />
              <stop offset="100%" stopColor="#e8e4e0" />
            </linearGradient>
            {/* 投影 */}
            <filter id="pawShadow" x="-80%" y="-30%" width="260%" height="180%">
              <feDropShadow dx="0" dy="1.5" stdDeviation="2.5" flood-color="#d9898e" floodOpacity="0.2" />
            </filter>
            <filter id="activeGlow" x="-80%" y="-30%" width="260%" height="180%">
              <feDropShadow dx="0" dy="1.5" stdDeviation="3" flood-color="#e09590" floodOpacity="0.35" />
            </filter>
          </defs>

          {/* 基准线 */}
          <line
            x1={0}
            y1={baselineY}
            x2={plotWidth}
            y2={baselineY}
            stroke="#ede9e4"
            strokeWidth="1"
          />

          {/* 每个小时的胶囊柱 */}
          {data.map((point, i) => {
            const cx = i * (cellWidth + gap) + cellWidth / 2;
            const isCurrent = currentHour === point.hour;
            const isHover = hover?.hour === point.hour;
            const hasData = point.minutes > 0;

            // 高度按比例：0 → 极小，maxMinutes → maxBarHeight
            const ratio = hasData ? point.minutes / maxMinutes : 0;
            const barH = hasData
              ? Math.max(8, ratio * maxBarHeight)
              : 6;
            // 宽度也随数据变化
            const barW = hasData
              ? barMinWidth + (barMaxWidth - barMinWidth) * Math.min(1, ratio * 1.2)
              : barMinWidth;
            const r = barW / 2;
            const y = baselineY - barH;

            let fillUrl: string;
            if (isCurrent && hasData) fillUrl = "url(#catPawActive)";
            else if (isHover) fillUrl = "url(#catPawHover)";
            else if (hasData) fillUrl = "url(#catPawGradient)";
            else fillUrl = "url(#catPawEmpty)";

            return (
              <g key={point.hour}>
                {/* 小时标签 */}
                <text
                  x={cx}
                  y={chartHeight - 8}
                  textAnchor="middle"
                  fontSize="8"
                  fill={isCurrent ? "#c07a7e" : "#c0bcc5"}
                  fontWeight={isCurrent ? 700 : 400}
                >
                  {point.label}
                </text>

                {/* 胶囊柱体 */}
                <rect
                  x={cx - barW / 2}
                  y={y}
                  width={barW}
                  height={barH}
                  rx={r}
                  ry={r}
                  fill={fillUrl}
                  opacity={
                    !hasData ? 0.5 :
                    isCurrent ? 1 :
                    isHover ? 1 : 0.78
                  }
                  filter={(isCurrent || isHover) && hasData
                    ? (isCurrent ? "url(#activeGlow)" : "url(#pawShadow)")
                    : undefined
                  }
                  className="paw-pill"
                  style={{
                    transition: "all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)",
                    transform: (isHover || isCurrent) ? `scaleY(1.04)` : "scaleY(1)",
                    transformOrigin: `${cx}px ${baselineY}px`,
                  }}
                  onMouseEnter={(e) => {
                    setHover(point);
                    setTooltipPos({ x: e.clientX, y: e.clientY });
                  }}
                  onMouseMove={(e) => setTooltipPos({ x: e.clientX, y: e.clientY })}
                  onMouseLeave={() => setHover(null)}
                />

                {/* 当前小时顶部小三角指示器 */}
                {isCurrent && (
                  <polygon
                    points={`${cx},${y - 8} ${cx - 4},${y - 2} ${cx + 4},${y - 2}`}
                    fill="#e09590"
                    opacity="0.7"
                  />
                )}

                {/* 数值标签（hover 或当前小时显示） */}
                {(isHover || isCurrent) && hasData && (
                  <text
                    x={cx}
                    y={y - (isCurrent ? 12 : 6)}
                    textAnchor="middle"
                    fontSize="9"
                    fill="#c07a7e"
                    fontWeight="600"
                  >
                    {point.minutes}
                  </text>
                )}
              </g>
            );
          })}
        </svg>

        {/* Tooltip */}
        {hover && (
          <div
            className="chart-tooltip cat-tooltip"
            style={{ left: tooltipPos.x, top: tooltipPos.y - 90 }}
          >
            <div className="tooltip-date">{hover.label} 时段</div>
            <div className="tooltip-value">
              {hover.minutes} <span>分钟</span>
            </div>
            <div className="tooltip-extra">{hover.sessions} 轮专注</div>
            {!hover.sessions && (
              <div className="tooltip-extra" style={{ color: "#a8989c", fontSize: "9px", marginTop: "2px" }}>
                这个时段还没有记录
              </div>
            )}
            <svg className="cat-ears" width="18" height="10" viewBox="0 0 18 10">
              <path d="M0 10 Q2 0 5 6 Q9 1 13 6 Q16 0 18 10 Z" fill="#f5c6b6" opacity="0.45" />
            </svg>
          </div>
        )}
      </div>
    </section>
  );
}

/* ── 辅助函数：从 session 列表计算每小时聚合数据 ── */
export function computeHourlyFocus(
  sessions: { startedAt: number; endedAt: number; minutes: number }[],
  targetDate?: Date,
): HourFocusPoint[] {
  const date = targetDate ?? new Date();
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const dayStart = d.getTime();
  const dayEnd = dayStart + 86_400_000;

  // 初始化 24 小时
  const hours: HourFocusPoint[] = Array.from({ length: 24 }, (_, h) => ({
    hour: h,
    label: `${String(h).padStart(2, "0")}:00`,
    minutes: 0,
    sessions: 0,
  }));

  for (const s of sessions) {
    if (s.startedAt < dayStart || s.startedAt >= dayEnd) continue;
    const h = new Date(s.startedAt).getHours();
    hours[h].minutes += s.minutes;
    hours[h].sessions += 1;
  }

  return hours;
}
