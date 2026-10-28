"""
Мой дневник — десктопное приложение для чтения и анализа записей.

Читает папку с txt-файлами, экспортированными с телефона
(имена файлов в формате ГГГГ-ММ-ДД.txt), раскладывает их по датам,
показывает календарь, поиск, статистику и просмотр записи.

Запуск:  python desktop/diary_desktop.py
Зависимости: только стандартная библиотека Python (tkinter уже входит в Python).
"""

import os
import re
import sys
import json
import datetime
from pathlib import Path

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, font as tkfont


# ─────────────────────────── ПАЛИТРА (тёмная, как в мобильном) ───────────────────────────
class C:
    BG = "#1b1d21"
    SURFACE = "#24272c"
    SURFACE_HIGH = "#2e3238"
    SURFACE_LOW = "#17191c"
    ACCENT = "#d9a566"
    ACCENT_SOFT = "#b08954"
    TEXT = "#e8e6e1"
    TEXT_SEC = "#a7a9ae"
    TEXT_FAINT = "#6e7178"
    DIVIDER = "#34383f"
    DANGER = "#d9766b"
    SUCCESS = "#7fb686"


MONTHS_GEN = [
    "января", "февраля", "марта", "апреля", "мая", "июня",
    "июля", "августа", "сентября", "октября", "ноября", "декабря",
]
MONTHS_NOM = [
    "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
    "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь",
]
WEEKDAYS_SHORT = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
WEEKDAYS_FULL = [
    "Понедельник", "Вторник", "Среда", "Четверг",
    "Пятница", "Суббота", "Воскресенье",
]

DATE_RE = re.compile(r"(\d{4})-(\d{2})-(\d{2})")


# ─────────────────────────── МОДЕЛЬ ДНЕВНИКА ───────────────────────────
class DayEntry:
    """Одна запись (один день)."""

    def __init__(self, date: datetime.date, text: str, path: Path):
        self.date = date
        self.text = text
        self.path = path

    @property
    def word_count(self) -> int:
        t = self.text.strip()
        return len(re.split(r"\s+", t)) if t else 0

    @property
    def title(self) -> str:
        """Первый непустой осмысленный заголовок из текста."""
        lines = [ln.strip() for ln in self.text.splitlines()]
        for ln in lines:
            # служебные строки "=== дата ===" и разделители пропускаем
            if not ln or ln.startswith("===") or set(ln) <= {"·", " "}:
                continue
            if ln.startswith("—") and ln.endswith("—"):
                return ln.strip("— ").strip()
            return ln[:80]
        return "(пустая запись)"

    @property
    def preview(self) -> str:
        t = " ".join(self.text.split())
        return t[:120] + "…" if len(t) > 120 else t


class DiaryStore:
    """Загружает записи из папки с txt-файлами."""

    def __init__(self):
        self.entries: list[DayEntry] = []
        self.folder: Path | None = None

    def load_folder(self, folder: str) -> int:
        self.entries = []
        self.folder = Path(folder)
        if not self.folder.exists():
            return 0
        for f in self.folder.iterdir():
            if not f.is_file() or f.suffix.lower() != ".txt":
                continue
            m = DATE_RE.search(f.name)
            if not m:
                continue
            try:
                d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            except ValueError:
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue
            self.entries.append(DayEntry(d, text, f))
        self.entries.sort(key=lambda e: e.date, reverse=True)
        return len(self.entries)

    @property
    def dates(self) -> set[datetime.date]:
        return {e.date for e in self.entries}

    def by_date(self, d: datetime.date) -> list[DayEntry]:
        return [e for e in self.entries if e.date == d]

    def search(self, query: str) -> list[DayEntry]:
        q = query.strip().lower()
        if not q:
            return []
        return [e for e in self.entries if q in e.text.lower() or q in e.title.lower()]

    # Статистика
    def total_words(self) -> int:
        return sum(e.word_count for e in self.entries)

    def stats(self) -> dict:
        if not self.entries:
            return {"count": 0, "words": 0, "avg": 0, "streak": 0,
                    "first": None, "last": None, "best": None}
        words = self.total_words()
        dates_sorted = sorted(self.dates, reverse=True)
        return {
            "count": len(self.entries),
            "words": words,
            "avg": round(words / len(self.entries)),
            "streak": self._current_streak(),
            "first": min(dates_sorted),
            "last": max(dates_sorted),
            "best": max(self.entries, key=lambda e: e.word_count),
        }

    def _current_streak(self) -> int:
        if not self.dates:
            return 0
        today = datetime.date.today()
        # серия считается от последней даты, идущей подряд до сегодня/вчера
        dates = self.dates
        start = today if today in dates else today - datetime.timedelta(days=1)
        if start not in dates:
            return 0
        n = 0
        d = start
        while d in dates:
            n += 1
            d -= datetime.timedelta(days=1)
        return n

    def months_histogram(self, year: int) -> list[int]:
        counts = [0] * 12
        for e in self.entries:
            if e.date.year == year:
                counts[e.date.month - 1] += 1
        return counts

    def years(self) -> list[int]:
        return sorted({e.date.year for e in self.entries}, reverse=True)


# ─────────────────────────── УТИЛИТЫ ДАТ ───────────────────────────
def pretty_date(d: datetime.date) -> str:
    return f"{d.day} {MONTHS_GEN[d.month - 1]} {d.year}"


def pretty_weekday(d: datetime.date) -> str:
    return f"{pretty_date(d)}, {WEEKDAYS_FULL[d.weekday()].lower()}"


def relative(d: datetime.date) -> str:
    today = datetime.date.today()
    diff = (today - d).days
    if diff == 0:
        return "Сегодня"
    if diff == 1:
        return "Вчера"
    if diff == 2:
        return "Позавчера"
    return pretty_date(d)


# ─────────────────────────── КАЛЕНДАРЬ-ВИДЖЕТ ───────────────────────────
class CalendarWidget(tk.Frame):
    """Компактный календарь на tkinter с отметками дней с записями."""

    def __init__(self, master, on_select, get_dated_dates):
        super().__init__(master, bg=C.SURFACE)
        self.on_select = on_select                    # callback(date)
        self.get_dated = get_dated_dates             # -> set[date]
        self.view = datetime.date.today().replace(day=1)
        self.selected = datetime.date.today()

        self.header = tk.Frame(self, bg=C.SURFACE)
        self.header.pack(fill="x", padx=10, pady=(10, 6))
        self.btn_prev = self._nav_button(self.header, "‹", self._prev_month)
        self.btn_prev.pack(side="left")
        self.lbl_month = tk.Label(
            self.header, text="", bg=C.SURFACE, fg=C.TEXT,
            font=("Segoe UI", 12, "bold"),
        )
        self.lbl_month.pack(side="left", expand=True)
        self.btn_next = self._nav_button(self.header, "›", self._next_month)
        self.btn_next.pack(side="right")

        self.grid_frame = tk.Frame(self, bg=C.SURFACE)
        self.grid_frame.pack(padx=8, pady=(0, 10))
        self._build_grid()

    def _nav_button(self, parent, text, cmd):
        return tk.Button(
            parent, text=text, command=cmd, bg=C.SURFACE, fg=C.ACCENT,
            activebackground=C.SURFACE_HIGH, activeforeground=C.ACCENT,
            relief="flat", bd=0, font=("Segoe UI", 16, "bold"),
            width=2, cursor="hand2",
        )

    def _build_grid(self):
        for w in self.grid_frame.winfo_children():
            w.destroy()
        for i, wd in enumerate(WEEKDAYS_SHORT):
            tk.Label(
                self.grid_frame, text=wd, bg=C.SURFACE, fg=C.TEXT_FAINT,
                font=("Segoe UI", 8),
            ).grid(row=0, column=i, padx=1, pady=(0, 4))

        import calendar as cal
        cal.setfirstweekday(cal.MONDAY)
        weeks = cal.Calendar(firstweekday=0).monthdayscalendar(
            self.view.year, self.view.month
        )
        dated = self.get_dated()
        today = datetime.date.today()

        for r, week in enumerate(weeks, start=1):
            for c, day in enumerate(week):
                if day == 0:
                    tk.Label(self.grid_frame, text="", bg=C.SURFACE,
                             width=3).grid(row=r, column=c)
                    continue
                d = datetime.date(self.view.year, self.view.month, day)
                has_entry = d in dated
                is_sel = d == self.selected
                is_today = d == today

                if is_sel:
                    bg, fg = C.ACCENT, "#241b0e"
                elif is_today:
                    bg, fg = C.SURFACE_HIGH, C.ACCENT
                else:
                    bg, fg = C.SURFACE, C.TEXT

                lbl = tk.Label(
                    self.grid_frame, text=str(day), bg=bg, fg=fg,
                    width=3, height=1, font=("Segoe UI", 9),
                    cursor="hand2",
                    highlightthickness=1,
                    highlightbackground=C.ACCENT_SOFT if is_today and not is_sel else bg,
                )
                lbl.grid(row=r, column=c, padx=1, pady=1)
                lbl.bind("<Button-1>", lambda e, dd=d: self._select(dd))

                # точка-маркер под числом при наличии записи
                if has_entry and not is_sel:
                    tk.Label(
                        self.grid_frame, text="•", bg=bg, fg=C.ACCENT_SOFT,
                        font=("Segoe UI", 7),
                    ).grid(row=r, column=c, sticky="s")
                    # перекрываем кликом основной label поверх маркера
                lbl.lift()

    def _select(self, d):
        self.selected = d
        self.view = d.replace(day=1)
        self._build_grid()
        self.on_select(d)

    def _prev_month(self):
        y, m = self.view.year, self.view.month - 1
        if m == 0:
            y, m = y - 1, 12
        self.view = datetime.date(y, m, 1)
        self._update()

    def _next_month(self):
        y, m = self.view.year, self.view.month + 1
        if m == 13:
            y, m = y + 1, 1
        self.view = datetime.date(y, m, 1)
        self._update()

    def _update(self):
        self._build_grid()

    def refresh(self):
        self._build_grid()

    def set_selected(self, d: datetime.date):
        self.selected = d
        self.view = d.replace(day=1)
        self._build_grid()


# ─────────────────────────── ГЛАВНОЕ ОКНО ───────────────────────────
class DiaryApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Мой дневник — анализ записей")
        self.geometry("1120x720")
        self.minsize(900, 600)
        self.configure(bg=C.BG)

        self.store = DiaryStore()
        self.current_date = datetime.date.today()
        self.filtered: list[DayEntry] | None = None  # результат поиска

        self._setup_fonts()
        self._setup_style()
        self._build_ui()
        self._auto_load_last_folder()

    # ---------- оформление ----------
    def _setup_fonts(self):
        for name in ("TkDefaultFont", "TkTextFont", "TkMenuFont"):
            try:
                tkfont.nametofont(name).configure(family="Segoe UI", size=10)
            except tk.TclError:
                pass

    def _setup_style(self):
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure(".", background=C.BG, foreground=C.TEXT,
                        fieldbackground=C.SURFACE)
        style.configure("TFrame", background=C.BG)
        style.configure("Card.TFrame", background=C.SURFACE)
        style.configure("TLabel", background=C.BG, foreground=C.TEXT)
        style.configure("Card.TLabel", background=C.SURFACE, foreground=C.TEXT)
        style.configure("Muted.TLabel", background=C.SURFACE,
                        foreground=C.TEXT_SEC)
        style.configure("Accent.TLabel", background=C.SURFACE,
                        foreground=C.ACCENT, font=("Segoe UI", 10, "bold"))
        style.configure("TButton", background=C.SURFACE_HIGH,
                        foreground=C.TEXT, borderwidth=0, focuscolor=C.SURFACE_HIGH)
        style.map("TButton",
                  background=[("active", C.ACCENT_SOFT)],
                  foreground=[("active", "#241b0e")])
        style.configure("Accent.TButton", background=C.ACCENT,
                        foreground="#241b0e", font=("Segoe UI", 10, "bold"))
        style.map("Accent.TButton", background=[("active", C.ACCENT_SOFT)])
        style.configure("TEntry", fieldbackground=C.SURFACE,
                        foreground=C.TEXT, insertcolor=C.TEXT,
                        borderwidth=0)
        style.configure("Vertical.TScrollbar", background=C.SURFACE_HIGH,
                        troughcolor=C.BG, borderwidth=0,
                        arrowcolor=C.TEXT_SEC)

    # ---------- интерфейс ----------
    def _build_ui(self):
        # Верхняя панель
        top = tk.Frame(self, bg=C.BG)
        top.pack(fill="x", padx=18, pady=(14, 8))

        title_box = tk.Frame(top, bg=C.BG)
        title_box.pack(side="left")
        tk.Label(title_box, text="Мой дневник", bg=C.BG, fg=C.TEXT,
                 font=("Segoe UI", 18, "bold")).pack(anchor="w")
        self.lbl_sub = tk.Label(title_box, text="Папка не выбрана", bg=C.BG,
                                fg=C.TEXT_SEC, font=("Segoe UI", 9))
        self.lbl_sub.pack(anchor="w")

        btn_frame = tk.Frame(top, bg=C.BG)
        btn_frame.pack(side="right")
        ttk.Button(btn_frame, text="⬇  Импорт с телефона",
                   command=self.import_from_phone).pack(side="left", padx=4)
        ttk.Button(btn_frame, text="📁  Открыть папку с записями",
                   command=self.choose_folder).pack(side="left", padx=4)
        ttk.Button(btn_frame, text="⟳  Обновить",
                   command=self.reload).pack(side="left", padx=4)

        # Тело: слева календарь + статистика, справа список и просмотр
        body = tk.Frame(self, bg=C.BG)
        body.pack(fill="both", expand=True, padx=18, pady=8)

        # ---- левая колонка ----
        left = tk.Frame(body, bg=C.BG, width=300)
        left.pack(side="left", fill="y", padx=(0, 14))
        left.pack_propagate(False)

        card = tk.Frame(left, bg=C.SURFACE, highlightthickness=1,
                        highlightbackground=C.DIVIDER)
        card.pack(fill="x")
        self.calendar = CalendarWidget(
            card, on_select=self.on_day_selected,
            get_dated_dates=lambda: self.store.dates,
        )
        self.calendar.pack(fill="x")

        # Статистика
        self.stats_card = tk.Frame(left, bg=C.SURFACE, highlightthickness=1,
                                   highlightbackground=C.DIVIDER)
        self.stats_card.pack(fill="x", pady=(14, 0))
        self._build_stats(self.stats_card)

        # ---- правая колонка ----
        right = tk.Frame(body, bg=C.BG)
        right.pack(side="left", fill="both", expand=True)

        # Поиск
        search_bar = tk.Frame(right, bg=C.BG)
        search_bar.pack(fill="x", pady=(0, 10))
        tk.Label(search_bar, text="🔍", bg=C.BG, fg=C.TEXT_SEC,
                 font=("Segoe UI", 12)).pack(side="left", padx=(0, 6))
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self.on_search())
        entry = ttk.Entry(search_bar, textvariable=self.search_var)
        entry.pack(side="left", fill="x", expand=True, ipady=6)
        tk.Button(search_bar, text="✕", command=self.clear_search,
                  bg=C.SURFACE, fg=C.TEXT_SEC, relief="flat", bd=0,
                  activebackground=C.SURFACE_HIGH, cursor="hand2",
                  font=("Segoe UI", 11)).pack(side="left", padx=6)

        # Разделитель-список/просмотр через PanedWindow
        paned = tk.Frame(right, bg=C.BG)
        paned.pack(fill="both", expand=True)

        # Список записей
        list_card = tk.Frame(paned, bg=C.SURFACE, highlightthickness=1,
                             highlightbackground=C.DIVIDER)
        list_card.pack(side="left", fill="both", expand=True, padx=(0, 10))
        tk.Label(list_card, text="Записи", bg=C.SURFACE, fg=C.TEXT,
                 font=("Segoe UI", 11, "bold")).pack(anchor="w", padx=12, pady=(10, 4))
        list_wrap = tk.Frame(list_card, bg=C.SURFACE)
        list_wrap.pack(fill="both", expand=True, padx=6, pady=(0, 8))

        self.listbox = tk.Listbox(
            list_wrap, bg=C.SURFACE, fg=C.TEXT, selectbackground=C.ACCENT,
            selectforeground="#241b0e", borderwidth=0, highlightthickness=0,
            font=("Segoe UI", 10), activestyle="none", exportselection=False,
        )
        self.listbox.pack(side="left", fill="both", expand=True)
        sb = ttk.Scrollbar(list_wrap, orient="vertical",
                           command=self.listbox.yview)
        sb.pack(side="right", fill="y")
        self.listbox.config(yscrollcommand=sb.set)
        self.listbox.bind("<<ListboxSelect>>", self.on_list_select)

        # Просмотр записи
        view_card = tk.Frame(paned, bg=C.SURFACE, highlightthickness=1,
                             highlightbackground=C.DIVIDER)
        view_card.pack(side="left", fill="both", expand=True)
        self.view_title = tk.Label(
            view_card, text="Выберите запись", bg=C.SURFACE, fg=C.ACCENT,
            font=("Segoe UI", 13, "bold"), anchor="w",
        )
        self.view_title.pack(fill="x", padx=16, pady=(12, 2))
        self.view_meta = tk.Label(
            view_card, text="", bg=C.SURFACE, fg=C.TEXT_FAINT,
            font=("Segoe UI", 9), anchor="w",
        )
        self.view_meta.pack(fill="x", padx=16, pady=(0, 8))

        text_wrap = tk.Frame(view_card, bg=C.SURFACE)
        text_wrap.pack(fill="both", expand=True, padx=12, pady=(0, 12))
        self.view_text = tk.Text(
            text_wrap, bg=C.SURFACE, fg=C.TEXT, wrap="word",
            borderwidth=0, highlightthickness=0, font=("Segoe UI", 11),
            spacing1=2, spacing3=4, padx=6, pady=4, cursor="arrow",
        )
        self.view_text.pack(side="left", fill="both", expand=True)
        vsb = ttk.Scrollbar(text_wrap, orient="vertical",
                            command=self.view_text.yview)
        vsb.pack(side="right", fill="y")
        self.view_text.config(yscrollcommand=vsb.set, state="disabled")

        # Нижняя строка статуса
        self.status = tk.Label(
            self, text="Готово", bg=C.SURFACE_LOW, fg=C.TEXT_SEC,
            anchor="w", padx=16, pady=6, font=("Segoe UI", 9),
        )
        self.status.pack(fill="x", side="bottom")

    def _build_stats(self, parent):
        tk.Label(parent, text="Статистика", bg=C.SURFACE, fg=C.TEXT,
                 font=("Segoe UI", 11, "bold")).pack(anchor="w", padx=14, pady=(10, 6))
        self.stats_frame = tk.Frame(parent, bg=C.SURFACE)
        self.stats_frame.pack(fill="x", padx=14, pady=(0, 12))
        self._stat_rows = {}
        for key, label in [
            ("count", "Всего записей"),
            ("words", "Всего слов"),
            ("avg", "Слов в записи (в среднем)"),
            ("streak", "Серия подряд (дней)"),
        ]:
            row = tk.Frame(self.stats_frame, bg=C.SURFACE)
            row.pack(fill="x", pady=2)
            tk.Label(row, text=label, bg=C.SURFACE, fg=C.TEXT_SEC,
                     font=("Segoe UI", 9), anchor="w").pack(side="left")
            val = tk.Label(row, text="—", bg=C.SURFACE, fg=C.ACCENT,
                           font=("Segoe UI", 10, "bold"), anchor="e")
            val.pack(side="right")
            self._stat_rows[key] = val

        self.lbl_range = tk.Label(
            parent, text="", bg=C.SURFACE, fg=C.TEXT_FAINT,
            font=("Segoe UI", 8), anchor="w", justify="left", wraplength=250,
        )
        self.lbl_range.pack(fill="x", padx=14, pady=(0, 12))

    # ---------- логика ----------
    def _auto_load_last_folder(self):
        """Пытаемся загрузить последнюю папку из конфига рядом со скриптом."""
        cfg = Path(__file__).parent / ".last_folder.json"
        if cfg.exists():
            try:
                data = json.loads(cfg.read_text(encoding="utf-8"))
                folder = data.get("folder")
                if folder and Path(folder).exists():
                    self.load_folder(folder, silent=True)
                    return
            except Exception:
                pass
        self._update_stats()
        self._refresh_list()
        self._set_status("Откройте папку с txt-записями (например, DiaryExport с телефона).")

    def _save_last_folder(self):
        if self.store.folder:
            cfg = Path(__file__).parent / ".last_folder.json"
            try:
                cfg.write_text(
                    json.dumps({"folder": str(self.store.folder)}, ensure_ascii=False),
                    encoding="utf-8",
                )
            except Exception:
                pass

    def choose_folder(self):
        folder = filedialog.askdirectory(title="Выберите папку с txt-записями")
        if folder:
            self.load_folder(folder)

    # Типичные места, где может лежать папка DiaryExport, скинутая с телефона.
    def _candidate_dirs(self):
        home = Path.home()
        names = ["DiaryExport", "diary", "Дневник", "diary_export"]
        bases = [
            home / "Downloads",
            home / "Загрузки",
            home / "Desktop",
            home / "Рабочий стол",
            home / "OneDrive" / "Documents",
            home / "Documents",
            home / "OneDrive" / "Рабочий стол",
        ]
        found = []
        for base in bases:
            if not base.exists():
                continue
            # 1) сама папка называется DiaryExport
            for nm in names:
                cand = base / nm
                if cand.is_dir():
                    found.append(cand)
            # 2) подпапка DiaryExport внутри других папок (глубина 2)
            try:
                for sub in base.iterdir():
                    if not sub.is_dir():
                        continue
                    for nm in names:
                        cand = sub / nm
                        if cand.is_dir():
                            found.append(cand)
            except OSError:
                continue
        # убрать дубликаты, сохранив порядок
        seen, uniq = set(), []
        for p in found:
            rp = str(p.resolve()).lower()
            if rp not in seen:
                seen.add(rp)
                uniq.append(p)
        return uniq

    def import_from_phone(self):
        """Ищет папку с записями в типичных местах и загружает её."""
        candidates = self._candidate_dirs()
        # оставляем только папки, где реально есть txt с датами
        real = []
        for c in candidates:
            try:
                has_txt = any(
                    DATE_RE.search(f.name) for f in c.iterdir()
                    if f.is_file() and f.suffix.lower() == ".txt"
                )
            except OSError:
                has_txt = False
            real.append((c, has_txt))

        if not real:
            if messagebox.askyesno(
                "Папка не найдена",
                "Не удалось автоматически найти папку с записями "
                "(DiaryExport) в Загрузках/Документах/Рабочем столе.\n\n"
                "Выбрать папку вручную?",
            ):
                self.choose_folder()
            return

        with_data = [c for c, has in real if has]

        # Если ровно одна папка с записями — сразу грузим её.
        if len(with_data) == 1:
            self.load_folder(str(with_data[0]))
            return
        if not with_data:
            with_data = [c for c, _ in real]

        # Если несколько — показываем список для выбора.
        choice = _choose_from_list(
            self,
            "Выберите папку с записями",
            [str(p) for p in with_data],
        )
        if choice:
            self.load_folder(choice)

    def load_folder(self, folder, silent=False):
        n = self.store.load_folder(folder)
        self._save_last_folder()
        self.lbl_sub.config(text=f"{self.store.folder}")
        self.calendar.set_selected(datetime.date.today())
        self._update_stats()
        self.filtered = None
        self._refresh_list()
        self._set_status(f"Загружено записей: {n}")
        if n == 0 and not silent:
            messagebox.showinfo(
                "Нет записей",
                "В выбранной папке не найдено txt-файлов вида ГГГГ-ММ-ДД.txt.",
            )

    def reload(self):
        if self.store.folder:
            self.load_folder(str(self.store.folder))
        else:
            self.choose_folder()

    def _update_stats(self):
        s = self.store.stats()
        self._stat_rows["count"].config(text=str(s["count"]))
        self._stat_rows["words"].config(text=f'{s["words"]:,}'.replace(",", " "))
        self._stat_rows["avg"].config(text=str(s["avg"]))
        self._stat_rows["streak"].config(text=str(s["streak"]))
        if s["first"]:
            self.lbl_range.config(
                text=f'Период: {pretty_date(s["first"])} — {pretty_date(s["last"])}\n'
                     f'Самая длинная запись: {pretty_date(s["best"].date)} '
                     f'({s["best"].word_count} слов)'
            )
        else:
            self.lbl_range.config(text="")

    def _refresh_list(self):
        self.listbox.delete(0, "end")
        if self.filtered is not None:
            items = self.filtered
            items = items[:500]
        else:
            items = self.store.entries
        if not items:
            self._show_empty_view()
            return
        for e in items:
            marker = "● " if e.date in self.store.dates else ""
            label = f"{marker}{e.date.strftime('%d.%m.%Y')}  {relative(e.date)}  ·  {e.title}"
            self.listbox.insert("end", label)
        # Автовыбор первой записи
        if self.listbox.size():
            self.listbox.selection_set(0)
            self.on_list_select()

    def on_day_selected(self, d: datetime.date):
        self.current_date = d
        # отфильтровать список по этому дню
        day_entries = self.store.by_date(d)
        self.filtered = None
        self.search_var.set("")
        self._refresh_list()
        if day_entries:
            # выбрать первую запись этого дня
            for i, e in enumerate(self.store.entries):
                if e.date == d:
                    self.listbox.selection_clear(0, "end")
                    self.listbox.selection_set(i)
                    self.listbox.see(i)
                    self.on_list_select()
                    break
        else:
            self.view_title.config(text=pretty_weekday(d))
            self.view_meta.config(text="За этот день записей нет")
            self._set_view_text("")
        self._set_status(f"Выбран день: {pretty_weekday(d)}")

    def on_list_select(self, _event=None):
        sel = self.listbox.curselection()
        if not sel:
            return
        idx = sel[0]
        items = self.filtered if self.filtered is not None else self.store.entries
        if idx >= len(items):
            return
        e = items[idx]
        self._show_entry(e)

    def _show_entry(self, e: DayEntry):
        self.view_title.config(text=e.title)
        self.view_meta.config(
            text=f"{pretty_weekday(e.date)}   ·   {e.word_count} слов"
        )
        # убрать служебную строку "=== дата ===" в начале
        body = re.sub(r"^===\s*.*?\s*===\s*\n?", "", e.text, count=1)
        self._set_view_text(body.strip())
        self.view_text.yview_moveto(0)

    def _show_empty_view(self):
        self.view_title.config(text="Нет записей")
        self.view_meta.config(text="")
        self._set_view_text("")

    def _set_view_text(self, s: str):
        self.view_text.config(state="normal")
        self.view_text.delete("1.0", "end")
        self.view_text.insert("1.0", s)
        self.view_text.config(state="disabled")

    def on_search(self):
        q = self.search_var.get().strip()
        if not q:
            self.filtered = None
            self._refresh_list()
            return
        self.filtered = self.store.search(q)
        self._refresh_list()
        self._set_status(
            f'Найдено записей по запросу «{q}»: {len(self.filtered)}'
        )

    def clear_search(self):
        self.search_var.set("")

    def _set_status(self, msg):
        self.status.config(text=msg)


def _choose_from_list(parent, title, items):
    """Диалог выбора одного элемента из списка (строк). Возвращает выбор или None."""
    top = tk.Toplevel(parent)
    top.title(title)
    top.configure(bg=C.BG)
    top.geometry("560x360")
    top.transient(parent)
    top.grab_set()

    tk.Label(top, text=title, bg=C.BG, fg=C.TEXT,
             font=("Segoe UI", 11, "bold")).pack(anchor="w", padx=14, pady=(12, 6))

    wrap = tk.Frame(top, bg=C.BG)
    wrap.pack(fill="both", expand=True, padx=12)
    lb = tk.Listbox(wrap, bg=C.SURFACE, fg=C.TEXT, selectbackground=C.ACCENT,
                    selectforeground="#241b0e", borderwidth=0,
                    highlightthickness=0, font=("Segoe UI", 10))
    lb.pack(side="left", fill="both", expand=True)
    sb = ttk.Scrollbar(wrap, orient="vertical", command=lb.yview)
    sb.pack(side="right", fill="y")
    lb.config(yscrollcommand=sb.set)
    for it in items:
        lb.insert("end", it)
    if items:
        lb.selection_set(0)

    result = {"value": None}

    def ok():
        sel = lb.curselection()
        if sel:
            result["value"] = items[sel[0]]
        top.destroy()

    def cancel():
        top.destroy()

    bar = tk.Frame(top, bg=C.BG)
    bar.pack(fill="x", padx=14, pady=12)
    ttk.Button(bar, text="Отмена", command=cancel).pack(side="right", padx=4)
    ttk.Button(bar, text="Открыть", style="Accent.TButton",
               command=ok).pack(side="right", padx=4)
    lb.bind("<Double-Button-1>", lambda e: ok())

    parent.wait_window(top)
    return result["value"]


def main():
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
    app = DiaryApp()
    app.mainloop()


if __name__ == "__main__":
    main()
