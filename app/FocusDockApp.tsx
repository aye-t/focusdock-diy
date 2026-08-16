"use client";

import { FormEvent, memo, useCallback, useEffect, useMemo, useRef, useState } from "react";

type Page = "focus" | "rhythm" | "review" | "settings";
type TimerPhase =
  | "idle"
  | "focus_running"
  | "focus_paused"
  | "focus_finished"
  | "rest_running"
  | "rest_paused"
  | "rest_finished";
type TimerMode = "countdown" | "countup";

type SessionRecord = {
  id: string;
  task: string;
  startedAt: number;
  endedAt: number;
  minutes: number;
  result: "done" | "progress" | "interrupted";
  note: string;
};

type ReminderRule = {
  id: string;
  icon: string;
  name: string;
  interval: number;
  enabled: boolean;
  policy: "defer" | "gentle";
  nextAt: number;
};

type ReminderEvent = {
  id: string;
  name: string;
  createdAt: number;
  status: "done" | "skipped";
};

type TimerSnapshot = {
  phase: TimerPhase;
  mode: TimerMode;
  task: string;
  duration: number;
  seconds: number;
  targetAt: number | null;
  startedAt: number | null;
};

type Settings = {
  focusMinutes: number;
  restMinutes: number;
  sound: boolean;
  notifications: boolean;
  showFloat: boolean;
};

const DEFAULT_SETTINGS: Settings = {
  focusMinutes: 45,
  restMinutes: 5,
  sound: true,
  notifications: false,
  showFloat: true,
};

const DEFAULT_REMINDERS: ReminderRule[] = [
  { id: "water", icon: "水", name: "喝水", interval: 40, enabled: true, policy: "defer", nextAt: 0 },
  { id: "stand", icon: "起", name: "站起来活动", interval: 60, enabled: true, policy: "defer", nextAt: 0 },
  { id: "eyes", icon: "眺", name: "远眺 20 秒", interval: 20, enabled: true, policy: "gentle", nextAt: 0 },
];

const DB_NAME = "focusdock-local";
const DB_VERSION = 1;

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("sessions")) db.createObjectStore("sessions", { keyPath: "id" });
      if (!db.objectStoreNames.contains("reminderEvents")) db.createObjectStore("reminderEvents", { keyPath: "id" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function readAll<T>(storeName: string): Promise<T[]> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const request = db.transaction(storeName, "readonly").objectStore(storeName).getAll();
    request.onsuccess = () => resolve(request.result as T[]);
    request.onerror = () => reject(request.error);
  });
}

async function putRecord<T>(storeName: string, value: T) {
  const db = await openDB();
  return new Promise<void>((resolve, reject) => {
    const request = db.transaction(storeName, "readwrite").objectStore(storeName).put(value);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

async function clearStore(storeName: string) {
  const db = await openDB();
  return new Promise<void>((resolve, reject) => {
    const request = db.transaction(storeName, "readwrite").objectStore(storeName).clear();
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

function formatSeconds(value: number) {
  const seconds = Math.max(0, Math.floor(value));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = seconds % 60;
  if (hours > 0) return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(rest).padStart(2, "0")}`;
  return `${String(minutes).padStart(2, "0")}:${String(rest).padStart(2, "0")}`;
}

function todayStart() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function loadLocal<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const value = window.localStorage.getItem(key);
    return value ? (JSON.parse(value) as T) : fallback;
  } catch {
    return fallback;
  }
}

function saveLocal(key: string, value: unknown) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // The timer still works when storage is unavailable.
  }
}

function playChime(kind: "focus" | "reminder", enabled: boolean) {
  if (!enabled) return;
  try {
    const AudioContextClass = window.AudioContext || (window as typeof window & { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    const context = new AudioContextClass();
    const gain = context.createGain();
    gain.gain.setValueAtTime(0.0001, context.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.12, context.currentTime + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.65);
    gain.connect(context.destination);
    [kind === "focus" ? 523.25 : 659.25, kind === "focus" ? 783.99 : 880].forEach((frequency, index) => {
      const oscillator = context.createOscillator();
      oscillator.type = "sine";
      oscillator.frequency.value = frequency;
      oscillator.connect(gain);
      oscillator.start(context.currentTime + index * 0.16);
      oscillator.stop(context.currentTime + 0.65);
    });
  } catch {
    // Audio is a progressive enhancement.
  }
}

const NAV: { id: Page; label: string; icon: string }[] = [
  { id: "focus", label: "专注", icon: "◴" },
  { id: "rhythm", label: "节律提醒", icon: "♧" },
  { id: "review", label: "今日回顾", icon: "⌁" },
  { id: "settings", label: "设置", icon: "◎" },
];

const TimerRing = memo(function TimerRing({ isRest, progress, phaseLabel, seconds, timerLabel }: {
  isRest: boolean;
  progress: number;
  phaseLabel: string;
  seconds: number;
  timerLabel: string;
}) {
  return (
    <div className={`timer-ring ${isRest ? "rest" : "focus"}`} style={{ "--progress": `${progress * 360}deg` } as React.CSSProperties}>
      <div className="timer-core">
        <span className="timer-phase"><i />{phaseLabel}</span>
        <strong>{formatSeconds(seconds)}</strong>
        <span className="timer-task">{timerLabel}</span>
      </div>
    </div>
  );
});

const FloatTimer = memo(function FloatTimer({ show, isRest, isRunning, timerLabel, seconds, progress, onToggle, onHide }: {
  show: boolean;
  isRest: boolean;
  isRunning: boolean;
  timerLabel: string;
  seconds: number;
  progress: number;
  onToggle: () => void;
  onHide: () => void;
}) {
  const [floatPosition, setFloatPosition] = useState<{ x: number; y: number }>(() => loadLocal("focusdock_float", { x: 0, y: 0 }));
  const dragRef = useRef<{ pointerX: number; pointerY: number; baseX: number; baseY: number } | null>(null);

  function clamp(x: number, y: number) {
    const w = 266;
    const h = 80;
    const MARGIN = 8;
    const minX = MARGIN + 34 + w - window.innerWidth;
    const maxX = 34 - MARGIN;
    const minY = MARGIN + 34 + h - window.innerHeight;
    const maxY = 34 - MARGIN;
    return { x: Math.min(maxX, Math.max(minX, x)), y: Math.min(maxY, Math.max(minY, y)) };
  }

  const setFloatRef = useCallback((node: HTMLDivElement | null) => {
    if (node) node.style.transform = `translate3d(${floatPosition.x}px, ${floatPosition.y}px, 0)`;
  }, [floatPosition]);

  useEffect(() => {
    saveLocal("focusdock_float", floatPosition);
  }, [floatPosition]);

  if (!show) return null;

  function pointerDown(event: React.PointerEvent<HTMLDivElement>) {
    if ((event.target as HTMLElement).closest("button")) return;
    dragRef.current = { pointerX: event.clientX, pointerY: event.clientY, baseX: floatPosition.x, baseY: floatPosition.y };
    event.currentTarget.setPointerCapture(event.pointerId);
    document.body.classList.add("is-dragging-float");
  }
  function pointerMove(event: React.PointerEvent<HTMLDivElement>) {
    if (!dragRef.current) return;
    const next = clamp(dragRef.current.baseX + (event.clientX - dragRef.current.pointerX), dragRef.current.baseY + (event.clientY - dragRef.current.pointerY));
    event.currentTarget.style.transform = `translate3d(${next.x}px, ${next.y}px, 0)`;
  }
  function endDrag(event: React.PointerEvent<HTMLDivElement>) {
    if (!dragRef.current) return;
    const next = clamp(dragRef.current.baseX + (event.clientX - dragRef.current.pointerX), dragRef.current.baseY + (event.clientY - dragRef.current.pointerY));
    dragRef.current = null;
    document.body.classList.remove("is-dragging-float");
    event.currentTarget.style.transform = `translate3d(${next.x}px, ${next.y}px, 0)`;
    setFloatPosition(next);
  }

  return (
    <div ref={setFloatRef} className="float-wrap" onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={endDrag} onPointerCancel={endDrag}>
      <div className="float-details"><small>{isRest ? "正在休息" : "当前专注"}</small><strong>{timerLabel}</strong><button onClick={onToggle}>{isRunning ? "暂停" : "继续"}</button><button onClick={onHide}>隐藏</button></div>
      <div className={`float-timer ${isRest ? "rest" : ""}`} style={{ "--progress": `${progress * 360}deg` } as React.CSSProperties}><div><strong>{formatSeconds(seconds)}</strong><i /></div></div>
    </div>
  );
});

export default function FocusDockApp() {
  const [page, setPage] = useState<Page>("focus");
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [phase, setPhase] = useState<TimerPhase>("idle");
  const [mode, setMode] = useState<TimerMode>("countdown");
  const [task, setTask] = useState("");
  const [duration, setDuration] = useState(DEFAULT_SETTINGS.focusMinutes * 60);
  const [seconds, setSeconds] = useState(DEFAULT_SETTINGS.focusMinutes * 60);
  const [targetAt, setTargetAt] = useState<number | null>(null);
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [customMinutes, setCustomMinutes] = useState("45");
  const [reminders, setReminders] = useState<ReminderRule[]>(DEFAULT_REMINDERS);
  const [sessions, setSessions] = useState<SessionRecord[]>([]);
  const [reminderEvents, setReminderEvents] = useState<ReminderEvent[]>([]);
  const [queuedReminderIds, setQueuedReminderIds] = useState<string[]>([]);
  const [activeReminderIds, setActiveReminderIds] = useState<string[]>([]);
  const [showFinish, setShowFinish] = useState(false);
  const [showAddReminder, setShowAddReminder] = useState(false);
  const [newReminderName, setNewReminderName] = useState("");
  const [newReminderMinutes, setNewReminderMinutes] = useState("45");
  const [result, setResult] = useState<SessionRecord["result"]>("done");
  const [note, setNote] = useState("");
  const [toast, setToast] = useState<string | null>(null);
  const [hydrated, setHydrated] = useState(false);
  const [activeSeconds, setActiveSeconds] = useState(0);

  const isFocus = phase.startsWith("focus") || phase === "idle";
  const isRunning = phase === "focus_running" || phase === "rest_running";
  const isPaused = phase === "focus_paused" || phase === "rest_paused";
  const isRest = phase.startsWith("rest");

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      const savedSettings = loadLocal("focusdock_settings", DEFAULT_SETTINGS);
      const savedRules = loadLocal<ReminderRule[]>("focusdock_reminders", DEFAULT_REMINDERS).map((rule) => ({
        ...rule,
        nextAt: rule.nextAt > Date.now() ? rule.nextAt : Date.now() + rule.interval * 60_000,
      }));
      const savedTimer = loadLocal<TimerSnapshot | null>("focusdock_timer", null);
      setSettings(savedSettings);
      setDuration(savedSettings.focusMinutes * 60);
      setSeconds(savedSettings.focusMinutes * 60);
      setCustomMinutes(String(savedSettings.focusMinutes));
      setReminders(savedRules);
      if (savedTimer && savedTimer.phase !== "idle") {
        setPhase(savedTimer.phase);
        setMode(savedTimer.mode);
        setTask(savedTimer.task);
        setDuration(savedTimer.duration);
        setTargetAt(savedTimer.targetAt);
        setStartedAt(savedTimer.startedAt);
        if (savedTimer.targetAt && savedTimer.phase.endsWith("running")) {
          setSeconds(Math.max(0, Math.ceil((savedTimer.targetAt - Date.now()) / 1000)));
        } else {
          setSeconds(savedTimer.seconds);
        }
      }
      Promise.all([readAll<SessionRecord>("sessions"), readAll<ReminderEvent>("reminderEvents")])
        .then(([savedSessions, savedEvents]) => {
          setSessions(savedSessions.sort((a, b) => b.startedAt - a.startedAt));
          setReminderEvents(savedEvents.sort((a, b) => b.createdAt - a.createdAt));
        })
        .catch(() => setToast("本机记录暂时无法读取"));
      if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => undefined);
      setHydrated(true);
    });
    return () => window.cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    saveLocal("focusdock_settings", settings);
  }, [hydrated, settings]);

  useEffect(() => {
    if (!hydrated) return;
    saveLocal("focusdock_reminders", reminders);
  }, [hydrated, reminders]);

  useEffect(() => {
    if (!hydrated) return;
    saveLocal("focusdock_timer", { phase, mode, task, duration, seconds, targetAt, startedAt } satisfies TimerSnapshot);
  }, [hydrated, phase, mode, task, duration, seconds, targetAt, startedAt]);


  const sendNotification = useCallback((title: string, body: string) => {
    if (settings.notifications && "Notification" in window && Notification.permission === "granted") {
      new Notification(title, { body });
    }
  }, [settings.notifications]);

  const finishTimer = useCallback((endedPhase: "focus" | "rest") => {
    setTargetAt(null);
    if (endedPhase === "focus") {
      setPhase("focus_finished");
      setSeconds(0);
      setShowFinish(true);
      playChime("focus", settings.sound);
      sendNotification("这一轮完成了", "休息一下，也看看有没有节律提醒。 ");
    } else {
      setPhase("rest_finished");
      setSeconds(0);
      playChime("focus", settings.sound);
      sendNotification("休息结束", "准备好时，开始下一轮。 ");
    }
  }, [sendNotification, settings.sound]);

  useEffect(() => {
    if (!isRunning) return;
    const update = () => {
      if (mode === "countup" && phase === "focus_running" && startedAt) {
        setSeconds(Math.floor((Date.now() - startedAt) / 1000));
        return;
      }
      if (!targetAt) return;
      const next = Math.max(0, Math.ceil((targetAt - Date.now()) / 1000));
      setSeconds(next);
      if (next <= 0) finishTimer(isRest ? "rest" : "focus");
    };
    update();
    const interval = window.setInterval(update, 250);
    return () => window.clearInterval(interval);
  }, [finishTimer, isRest, isRunning, mode, phase, startedAt, targetAt]);

  useEffect(() => {
    document.title = isRunning ? `${formatSeconds(seconds)} · ${isRest ? "休息" : task || "专注"}` : "FocusDock · 把时间放回手里";
  }, [isRest, isRunning, seconds, task]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      if (!document.hidden) setActiveSeconds((value) => value + 1);
    }, 1000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    const checkReminders = () => {
      const now = Date.now();
      const due = reminders.filter((rule) => rule.enabled && rule.nextAt <= now);
      if (!due.length) return;
      setReminders((rules) => rules.map((rule) => due.some((item) => item.id === rule.id)
        ? { ...rule, nextAt: now + rule.interval * 60_000 }
        : rule));
      const immediate = due.filter((rule) => !isRunning || rule.policy === "gentle");
      const deferred = due.filter((rule) => isRunning && rule.policy === "defer");
      if (deferred.length) setQueuedReminderIds((ids) => Array.from(new Set([...ids, ...deferred.map((item) => item.id)])));
      if (immediate.length) {
        setActiveReminderIds(immediate.map((item) => item.id));
        playChime("reminder", settings.sound);
        sendNotification("节律提醒", immediate.map((item) => item.name).join(" · "));
      }
    };
    checkReminders();
    const interval = window.setInterval(checkReminders, 15_000);
    return () => window.clearInterval(interval);
  }, [hydrated, isRunning, reminders, sendNotification, settings.sound]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.code !== "Space" || event.metaKey || event.ctrlKey || event.altKey) return;
      const target = event.target as HTMLElement;
      if (["INPUT", "TEXTAREA", "BUTTON", "SELECT"].includes(target.tagName)) return;
      event.preventDefault();
      toggleTimer();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const timerTotal = isRest ? settings.restMinutes * 60 : duration;
  const progress = mode === "countup" && isFocus
    ? Math.min(1, seconds / Math.max(duration, 1))
    : Math.min(1, Math.max(0, (timerTotal - seconds) / Math.max(timerTotal, 1)));

  function selectDuration(minutes: number) {
    if (phase !== "idle") return;
    setDuration(minutes * 60);
    setSeconds(minutes * 60);
    setCustomMinutes(String(minutes));
  }

  function switchMode(nextMode: TimerMode) {
    if (phase !== "idle") return;
    setMode(nextMode);
    setSeconds(nextMode === "countdown" ? duration : 0);
  }

  function startFocus() {
    const now = Date.now();
    setStartedAt(now);
    setPhase("focus_running");
    if (mode === "countdown") {
      setSeconds(duration);
      setTargetAt(now + duration * 1000);
    } else {
      setSeconds(0);
      setTargetAt(null);
    }
  }

  function toggleTimer() {
    if (phase === "idle" || phase === "rest_finished" || phase === "focus_finished") {
      if (phase === "rest_finished") startNextFocus();
      else if (phase === "focus_finished") startRest();
      else startFocus();
      return;
    }
    if (isRunning) {
      setPhase(isRest ? "rest_paused" : "focus_paused");
      setTargetAt(null);
      return;
    }
    if (isPaused) {
      setPhase(isRest ? "rest_running" : "focus_running");
      if (mode === "countdown" || isRest) setTargetAt(Date.now() + seconds * 1000);
      else setStartedAt(Date.now() - seconds * 1000);
    }
  }

  function resetTimer() {
    setPhase("idle");
    setSeconds(mode === "countdown" ? duration : 0);
    setTargetAt(null);
    setStartedAt(null);
    setShowFinish(false);
  }

  function startRest() {
    const restSeconds = settings.restMinutes * 60;
    if (queuedReminderIds.length) {
      setActiveReminderIds(queuedReminderIds);
      setQueuedReminderIds([]);
    }
    setShowFinish(false);
    setPhase("rest_running");
    setSeconds(restSeconds);
    setDuration(restSeconds);
    setTargetAt(Date.now() + restSeconds * 1000);
    setStartedAt(Date.now());
  }

  function startNextFocus() {
    const focusSeconds = settings.focusMinutes * 60;
    setMode("countdown");
    setDuration(focusSeconds);
    setSeconds(focusSeconds);
    setPhase("focus_running");
    setStartedAt(Date.now());
    setTargetAt(Date.now() + focusSeconds * 1000);
  }

  function extendFive() {
    const next = seconds + 300;
    setShowFinish(false);
    setPhase(isRest ? "rest_running" : "focus_running");
    setSeconds(next);
    setTargetAt(Date.now() + next * 1000);
  }

  async function saveSession(startBreak: boolean) {
    const endedAt = Date.now();
    const start = startedAt || endedAt - Math.max(1, duration - seconds) * 1000;
    const record: SessionRecord = {
      id: crypto.randomUUID(),
      task: task.trim() || "未命名专注",
      startedAt: start,
      endedAt,
      minutes: Math.max(1, Math.round((endedAt - start) / 60_000)),
      result,
      note: note.trim(),
    };
    await putRecord("sessions", record);
    setSessions((items) => [record, ...items]);
    setNote("");
    setToast("这轮进展已保存在本机");
    window.setTimeout(() => setToast(null), 2400);
    if (startBreak) startRest();
    else resetTimer();
  }

  async function resolveReminders(status: ReminderEvent["status"]) {
    const now = Date.now();
    const names = activeReminderIds.map((id) => reminders.find((item) => item.id === id)?.name).filter(Boolean) as string[];
    const events = names.map((name, index) => ({ id: `${now}-${index}`, name, createdAt: now, status }));
    await Promise.all(events.map((event) => putRecord("reminderEvents", event)));
    setReminderEvents((items) => [...events, ...items]);
    setActiveReminderIds([]);
  }

  function snoozeReminders() {
    const ids = activeReminderIds;
    setReminders((items) => items.map((item) => ids.includes(item.id) ? { ...item, nextAt: Date.now() + 10 * 60_000 } : item));
    setActiveReminderIds([]);
    setToast("好，10 分钟后再轻轻提醒你");
    window.setTimeout(() => setToast(null), 2400);
  }

  function addReminder(event: FormEvent) {
    event.preventDefault();
    const minutes = Math.max(1, Number(newReminderMinutes) || 45);
    const next: ReminderRule = {
      id: crypto.randomUUID(),
      icon: "自",
      name: newReminderName.trim() || "自定义提醒",
      interval: minutes,
      enabled: true,
      policy: "defer",
      nextAt: Date.now() + minutes * 60_000,
    };
    setReminders((items) => [...items, next]);
    setNewReminderName("");
    setNewReminderMinutes("45");
    setShowAddReminder(false);
  }

  async function requestNotifications() {
    if (!("Notification" in window)) {
      setToast("当前浏览器不支持系统通知");
      return;
    }
    const permission = await Notification.requestPermission();
    setSettings((value) => ({ ...value, notifications: permission === "granted" }));
    setToast(permission === "granted" ? "系统通知已开启" : "你可以继续使用页内提醒");
    window.setTimeout(() => setToast(null), 2400);
  }

  async function deleteTodayData() {
    await Promise.all([clearStore("sessions"), clearStore("reminderEvents")]);
    setSessions([]);
    setReminderEvents([]);
    setToast("本机记录已清空");
    window.setTimeout(() => setToast(null), 2400);
  }

  const todaySessions = useMemo(() => sessions.filter((item) => item.startedAt >= todayStart()), [sessions]);
  const todayEvents = useMemo(() => reminderEvents.filter((item) => item.createdAt >= todayStart()), [reminderEvents]);
  const focusedMinutes = todaySessions.reduce((sum, item) => sum + item.minutes, 0);
  const reminderDone = todayEvents.filter((item) => item.status === "done").length;
  const reminderRate = todayEvents.length ? Math.round((reminderDone / todayEvents.length) * 100) : 0;
  const nextReminder = reminders.filter((item) => item.enabled).sort((a, b) => a.nextAt - b.nextAt)[0];
  const activeReminderNames = activeReminderIds.map((id) => reminders.find((item) => item.id === id)?.name).filter(Boolean) as string[];
  const timerLabel = isRest ? "休息一下" : task.trim() || "准备开始";

  function phaseLabel() {
    if (phase === "idle") return "把注意力放在一件事上";
    if (isRest) return phase.endsWith("paused") ? "休息已暂停" : phase === "rest_finished" ? "休息完成" : "正在休息";
    if (phase === "focus_finished") return "这一轮完成了";
    return phase.endsWith("paused") ? "已暂停" : mode === "countup" ? "自由专注中" : "专注进行中";
  }

  function primaryLabel() {
    if (phase === "idle") return "开始专注";
    if (phase === "focus_finished") return "开始休息";
    if (phase === "rest_finished") return "下一轮";
    if (isRunning) return "暂停";
    return "继续";
  }

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="window-controls" aria-hidden="true"><i /><i /><i /></div>
        <button className="brand" onClick={() => setPage("focus")} aria-label="返回专注页">
          <span className="brand-mark">F</span>
          <span><strong>FocusDock</strong><small>把时间放回手里</small></span>
        </button>
        <nav className="nav" aria-label="主导航">
          {NAV.map((item) => (
            <button key={item.id} className={page === item.id ? "active" : ""} onClick={() => setPage(item.id)}>
              <span>{item.icon}</span>{item.label}
              {item.id === "rhythm" && queuedReminderIds.length > 0 && <b>{queuedReminderIds.length}</b>}
            </button>
          ))}
        </nav>
        <div className="sidebar-note">
          <span className="privacy-dot" />
          <strong>仅保存在这台设备</strong>
          <p>不需要账号，不记录网页内容。</p>
        </div>
        <div className="mini-status">
          <span className={isRunning ? "live-dot" : "idle-dot"} />
          <div><small>{isRunning ? (isRest ? "正在休息" : "专注进行中") : "当前状态"}</small><strong>{isRunning ? formatSeconds(seconds) : "随时可以开始"}</strong></div>
        </div>
      </aside>

      <section className="workspace">
        <header className="topbar">
          <div>
            <span className="eyebrow">{page === "focus" ? "FOCUS SPACE" : page === "rhythm" ? "RHYTHM CARE" : page === "review" ? "TODAY, GENTLY" : "PREFERENCES"}</span>
            <h1>{page === "focus" ? "专注一件事" : page === "rhythm" ? "照顾工作节律" : page === "review" ? "今天，时间去了哪里" : "按你的方式工作"}</h1>
          </div>
          <div className="top-actions">
            <span className="today-label">{new Intl.DateTimeFormat("zh-CN", { month: "long", day: "numeric", weekday: "short" }).format(new Date())}</span>
            <button className="icon-button" onClick={() => setSettings((value) => ({ ...value, showFloat: !value.showFloat }))} title="显示或隐藏迷你计时器">◫</button>
          </div>
        </header>

        {page === "focus" && (
          <div className="focus-page page-enter">
            <section className="timer-card panel">
              <div className="timer-card-head">
                <label className="task-field">
                  <span>这一轮，只做什么？</span>
                  <input maxLength={50} value={task} onChange={(event) => setTask(event.target.value)} placeholder="例如：完成产品首页的第一版" />
                </label>
                <div className="mode-switch" aria-label="计时模式">
                  <button className={mode === "countdown" ? "active" : ""} onClick={() => switchMode("countdown")}>倒计时</button>
                  <button className={mode === "countup" ? "active" : ""} onClick={() => switchMode("countup")}>自由计时</button>
                </div>
              </div>

              <TimerRing isRest={isRest} progress={progress} phaseLabel={phaseLabel()} seconds={seconds} timerLabel={timerLabel} />

              {phase === "idle" && mode === "countdown" && (
                <div className="presets" aria-label="专注时长">
                  {[10, 25, 45, 50].map((minutes) => <button key={minutes} className={duration === minutes * 60 ? "active" : ""} onClick={() => selectDuration(minutes)}>{minutes} 分钟</button>)}
                  <label className="custom-time"><input aria-label="自定义分钟" inputMode="numeric" value={customMinutes} onChange={(event) => setCustomMinutes(event.target.value)} onBlur={() => selectDuration(Math.max(1, Number(customMinutes) || 45))} /> 分</label>
                </div>
              )}
              {phase === "idle" && mode === "countup" && <p className="countup-hint">不设终点，先开始。完成时会记录实际专注时长。</p>}

              <div className="timer-actions">
                <button className="subtle-button" onClick={resetTimer} disabled={phase === "idle"}>重置</button>
                <button className="primary-button" onClick={toggleTimer}><span>{isRunning ? "Ⅱ" : "▶"}</span>{primaryLabel()}</button>
                <button className="subtle-button" onClick={() => setShowFinish(true)} disabled={phase === "idle" || isRest}>提前完成</button>
              </div>
              <p className="keyboard-tip">按空格键可暂停 / 继续</p>
            </section>

            <aside className="focus-side">
              <section className="next-card panel">
                <div className="section-heading"><span className="section-icon purple">♧</span><div><small>下一次节律</small><h2>{nextReminder ? nextReminder.name : "还没有启用提醒"}</h2></div></div>
                {nextReminder && <div className="next-time"><strong>{Math.max(1, Math.ceil((nextReminder.nextAt - Date.now()) / 60_000))}</strong><span>分钟后</span></div>}
                <div className="care-plan">
                  <span>专注时</span><strong>{queuedReminderIds.length ? `已有 ${queuedReminderIds.length} 项排到休息` : "需要离座的动作会自动延后"}</strong>
                </div>
                <button className="text-button" onClick={() => setPage("rhythm")}>管理节律提醒 <span>→</span></button>
              </section>

              <section className="today-card panel">
                <div className="section-heading"><span className="section-icon coral">⌁</span><div><small>今天</small><h2>已经为自己留出的时间</h2></div></div>
                <div className="today-number"><strong>{Math.floor(focusedMinutes / 60)}<small>时</small> {focusedMinutes % 60}<small>分</small></strong><span>专注时间</span></div>
                <div className="mini-metrics"><span><b>{todaySessions.length}</b> 完成轮次</span><span><b>{reminderRate}%</b> 提醒完成</span></div>
                <button className="text-button" onClick={() => setPage("review")}>查看今日回顾 <span>→</span></button>
              </section>
            </aside>
          </div>
        )}

        {page === "rhythm" && (
          <div className="rhythm-page page-enter">
            <section className="rhythm-intro">
              <div><span className="eyebrow">独立运行，也懂得避让</span><h2>提醒身体，不打断思路。</h2><p>轻动作可以在专注中安静出现；喝水、站立等动作会排到最近的休息开始时合并提醒。</p></div>
              <button className="primary-button compact" onClick={() => setShowAddReminder(true)}>＋ 新建提醒</button>
            </section>
            <div className="reminder-grid">
              {reminders.map((item) => (
                <article className={`reminder-card panel ${item.enabled ? "" : "disabled"}`} key={item.id}>
                  <div className="reminder-top"><span className="reminder-icon">{item.icon}</span><button className={`toggle ${item.enabled ? "on" : ""}`} onClick={() => setReminders((items) => items.map((rule) => rule.id === item.id ? { ...rule, enabled: !rule.enabled, nextAt: Date.now() + rule.interval * 60_000 } : rule))} aria-label={`${item.enabled ? "关闭" : "开启"}${item.name}`}><i /></button></div>
                  <h3>{item.name}</h3><p>每 {item.interval} 分钟</p>
                  <div className="reminder-policy"><span>{item.policy === "gentle" ? "轻提示" : "休息时提醒"}</span><b>{item.enabled ? `${Math.max(1, Math.ceil((item.nextAt - Date.now()) / 60_000))} 分钟后` : "已暂停"}</b></div>
                  <button className="policy-button" onClick={() => setReminders((items) => items.map((rule) => rule.id === item.id ? { ...rule, policy: rule.policy === "gentle" ? "defer" : "gentle" } : rule))}>切换为{item.policy === "gentle" ? "休息时提醒" : "轻提示"}</button>
                </article>
              ))}
            </div>
            <section className="rhythm-rule panel"><span className="rule-mark">↳</span><div><strong>专注优先规则正在生效</strong><p>5 分钟内到期的多个提醒会合并为一张卡片。你始终可以稍后、完成或跳过。</p></div><button onClick={() => { setActiveReminderIds(reminders.filter((item) => item.enabled).slice(0, 3).map((item) => item.id)); }}>预览提醒</button></section>
          </div>
        )}

        {page === "review" && (
          <div className="review-page page-enter">
            <div className="metric-grid">
              <article className="metric-card panel featured"><span>今日专注</span><strong>{focusedMinutes}<small> 分钟</small></strong><p>{todaySessions.length ? `${todaySessions.length} 轮专注已被记录` : "从第一轮开始，今天就有了形状"}</p></article>
              <article className="metric-card panel"><span>本页活跃</span><strong>{Math.floor(activeSeconds / 60)}<small> 分钟</small></strong><p>仅统计 FocusDock 页面可见时长</p></article>
              <article className="metric-card panel"><span>节律完成</span><strong>{reminderRate}<small>%</small></strong><p>{reminderDone} 次动作已完成</p></article>
            </div>
            <div className="review-grid">
              <section className="timeline-card panel">
                <div className="panel-title"><div><span className="eyebrow">TODAY TIMELINE</span><h2>今日时间线</h2></div><span>{todaySessions.length} 条记录</span></div>
                {todaySessions.length === 0 ? (
                  <div className="empty-state"><span>○</span><strong>今天还没有专注记录</strong><p>完成一轮后，它会安静地出现在这里。</p><button className="text-button" onClick={() => setPage("focus")}>开始第一轮 →</button></div>
                ) : (
                  <div className="timeline-list">{todaySessions.map((item) => <article key={item.id}><time>{new Date(item.startedAt).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })}</time><i /><div><strong>{item.task}</strong><p>{item.minutes} 分钟 · {item.result === "done" ? "已完成" : item.result === "progress" ? "有一些进展" : "被打断"}{item.note ? ` · ${item.note}` : ""}</p></div></article>)}</div>
                )}
              </section>
              <section className="care-summary panel">
                <div className="panel-title"><div><span className="eyebrow">BODY CARE</span><h2>身体也被照顾到了</h2></div></div>
                <div className="care-score"><div style={{ "--score": `${reminderRate * 3.6}deg` } as React.CSSProperties}><strong>{reminderRate}%</strong></div><p>提醒不是考核。<br />它只是帮你重新感知时间。</p></div>
                <ul>{reminders.slice(0, 3).map((item) => <li key={item.id}><span>{item.icon}</span><strong>{item.name}</strong><b>{todayEvents.filter((event) => event.name === item.name && event.status === "done").length} 次</b></li>)}</ul>
              </section>
            </div>
          </div>
        )}

        {page === "settings" && (
          <div className="settings-page page-enter">
            <section className="settings-section panel">
              <div className="settings-copy"><span className="section-icon purple">◴</span><div><h2>专注与休息</h2><p>设置每一轮的默认节奏。</p></div></div>
              <div className="setting-row"><label>默认专注时长</label><div className="number-control"><input type="number" min="1" max="180" value={settings.focusMinutes} onChange={(event) => setSettings((value) => ({ ...value, focusMinutes: Math.max(1, Number(event.target.value)) }))} /><span>分钟</span></div></div>
              <div className="setting-row"><label>短休息时长</label><div className="number-control"><input type="number" min="1" max="60" value={settings.restMinutes} onChange={(event) => setSettings((value) => ({ ...value, restMinutes: Math.max(1, Number(event.target.value)) }))} /><span>分钟</span></div></div>
            </section>
            <section className="settings-section panel">
              <div className="settings-copy"><span className="section-icon coral">♧</span><div><h2>提醒方式</h2><p>选择 FocusDock 如何找到你。</p></div></div>
              <div className="setting-row"><label><strong>柔和提示音</strong><small>到点时播放一声短提示</small></label><button className={`toggle ${settings.sound ? "on" : ""}`} onClick={() => setSettings((value) => ({ ...value, sound: !value.sound }))}><i /></button></div>
              <div className="setting-row"><label><strong>浏览器系统通知</strong><small>页面在后台时也能看到提醒</small></label><button className={`toggle ${settings.notifications ? "on" : ""}`} onClick={requestNotifications}><i /></button></div>
              <div className="setting-row"><label><strong>迷你计时器</strong><small>在页面右下角保持倒计时可见</small></label><button className={`toggle ${settings.showFloat ? "on" : ""}`} onClick={() => setSettings((value) => ({ ...value, showFloat: !value.showFloat }))}><i /></button></div>
            </section>
            <section className="privacy-card panel"><span className="privacy-shield">✓</span><div><h2>你的时间，只属于你</h2><p>FocusDock 的专注记录、节律提醒与设置仅保存在这个浏览器中。不会记录你访问的网页、输入内容或屏幕画面。</p></div><button className="danger-button" onClick={deleteTodayData}>清空本机记录</button></section>
          </div>
        )}
      </section>

      <FloatTimer
        show={settings.showFloat && phase !== "idle"}
        isRest={isRest}
        isRunning={isRunning}
        timerLabel={timerLabel}
        seconds={seconds}
        progress={progress}
        onToggle={toggleTimer}
        onHide={() => setSettings((value) => ({ ...value, showFloat: false }))}
      />

      {activeReminderNames.length > 0 && (
        <div className="reminder-popover" role="dialog" aria-modal="true" aria-label="节律提醒">
          <button className="close-popover" onClick={() => setActiveReminderIds([])}>×</button>
          <span className="reminder-kicker">休息一下</span><h2>{activeReminderNames.length > 1 ? "一起做几个小动作" : activeReminderNames[0]}</h2>
          <div className="reminder-actions-list">{activeReminderNames.map((name) => <span key={name}>✓ {name}</span>)}</div>
          <p>离开屏幕一会儿，时间不会跑掉。</p>
          <div className="popover-actions"><button onClick={snoozeReminders}>10 分钟后</button><button onClick={() => resolveReminders("skipped")}>跳过</button><button className="primary-button compact" onClick={() => resolveReminders("done")}>完成了</button></div>
        </div>
      )}

      {showFinish && (
        <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowFinish(false); }}>
          <section className="modal" role="dialog" aria-modal="true" aria-labelledby="finish-title">
            <button className="modal-close" onClick={() => setShowFinish(false)}>×</button><span className="modal-mark">✓</span><span className="eyebrow">这一轮，已经发生</span><h2 id="finish-title">留下这次进展</h2><p>记录事实就好，不必给自己打分。</p>
            <div className="result-options">{(["done", "progress", "interrupted"] as const).map((value) => <button key={value} className={result === value ? "active" : ""} onClick={() => setResult(value)}>{value === "done" ? "已完成" : value === "progress" ? "有一些进展" : "被打断了"}</button>)}</div>
            <textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="可选：记下刚才做到哪里…" />
            <div className="modal-actions"><button className="subtle-button" onClick={extendFive}>再专注 5 分钟</button><button className="primary-button" onClick={() => saveSession(true)}>记录并休息</button></div>
          </section>
        </div>
      )}

      {showAddReminder && (
        <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowAddReminder(false); }}>
          <form className="modal add-modal" onSubmit={addReminder}><button type="button" className="modal-close" onClick={() => setShowAddReminder(false)}>×</button><span className="eyebrow">NEW RHYTHM</span><h2>新建节律提醒</h2><label>提醒名称<input autoFocus value={newReminderName} onChange={(event) => setNewReminderName(event.target.value)} placeholder="例如：放松肩颈" /></label><label>重复间隔<div className="number-control"><input type="number" min="1" value={newReminderMinutes} onChange={(event) => setNewReminderMinutes(event.target.value)} /><span>分钟</span></div></label><button className="primary-button" type="submit">保存提醒</button></form>
        </div>
      )}

      {toast && <div className="toast" role="status">✓ {toast}</div>}
    </main>
  );
}
