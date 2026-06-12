"""tkinter 浮動 HUD：顯示模式 + 錄音狀態，點擊展開選單切換模式。"""
from __future__ import annotations

import logging
import subprocess
import sys
import threading

logger = logging.getLogger(__name__)


def _probe_tkinter() -> bool:
    """在子程序中測試 tkinter 是否能正常建立帶背景色的 Widget。
    macOS 26 上 Tk 9.0 在 TkpGetColor → GetRGBA 時呼叫已移除的
    [NSApplication macOSVersion]，導致 SIGABRT。
    此探測能在子程序中安全偵測這個崩潰，不影響主程序。
    """
    try:
        result = subprocess.run(
            [sys.executable, "-c",
             "import tkinter as tk;"
             "r=tk.Tk();"
             "f=tk.Frame(r,bg='#1c1c1e',padx=4,pady=4);"
             "tk.Label(f,text='HUD',fg='white',bg='#1c1c1e').pack();"
             "f.pack();"
             "r.update_idletasks();"
             "r.destroy();"
             "print('ok')"],
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0 and b"ok" in result.stdout
    except Exception:
        return False


class HUD:
    STATE_TEXT = {
        "idle":       ("⏸", "#888888"),
        "recording":  ("🔴", "#ff3b30"),
        "processing": ("🔄", "#ff9500"),
        "error":      ("⚠️", "#ff3b30"),
    }

    def __init__(self, mode_manager, ui_cfg: dict, on_quit):
        self.mm = mode_manager
        self.ui = ui_cfg
        self.on_quit = on_quit
        self._state = "idle"
        self._root = None
        self._main_label = None
        self._state_label = None
        self._menu_window = None
        self._ready = threading.Event()

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()
        self._ready.wait(timeout=3)
        self.mm.on_change(lambda mode: self._schedule(self._render))

    def _run(self):
        import tkinter as tk
        self._tk = tk
        self._root = tk.Tk()
        self._root.overrideredirect(True)
        self._root.attributes("-topmost", True)
        self._root.attributes("-alpha", self.ui.get("hud_opacity", 0.9))
        self._root.configure(bg="#1c1c1e")

        frame = tk.Frame(self._root, bg="#1c1c1e", padx=12, pady=6)
        frame.pack()

        font_size = self.ui.get("hud_font_size", 14)
        self._main_label = tk.Label(
            frame, text="", fg="white", bg="#1c1c1e",
            font=("Helvetica", font_size, "bold"), cursor="hand2",
        )
        self._main_label.pack(side="left", padx=(0, 8))
        self._main_label.bind("<Button-1>", lambda e: self._toggle_menu())

        self._state_label = tk.Label(
            frame, text="⏸", fg="#888888", bg="#1c1c1e",
            font=("Helvetica", font_size + 2),
        )
        self._state_label.pack(side="left")

        self._root.bind("<Button-3>", lambda e: self.on_quit())

        self._place_window()
        self._render()
        self._ready.set()
        self._root.mainloop()

    def _place_window(self):
        self._root.update_idletasks()
        w = self._root.winfo_reqwidth()
        h = self._root.winfo_reqheight()
        sw = self._root.winfo_screenwidth()
        sh = self._root.winfo_screenheight()
        pos = self.ui.get("hud_position", "bottom-right")
        ox = self.ui.get("hud_offset_x", 20)
        oy = self.ui.get("hud_offset_y", 20)
        if pos == "bottom-right":
            x, y = sw - w - ox, sh - h - oy - 30
        elif pos == "top-right":
            x, y = sw - w - ox, oy + 30
        elif pos == "top-left":
            x, y = ox, oy + 30
        else:
            x, y = ox, sh - h - oy - 30
        self._root.geometry(f"+{x}+{y}")

    def _render(self):
        if not self._main_label:
            return
        mode = self.mm.current
        self._main_label.config(text=mode.display)
        icon, color = self.STATE_TEXT.get(self._state, self.STATE_TEXT["idle"])
        self._state_label.config(text=icon, fg=color)
        self._place_window()

    def set_state(self, state: str):
        self._state = state
        self._schedule(self._render)

    def _schedule(self, fn):
        if self._root:
            self._root.after(0, fn)

    def _toggle_menu(self):
        if self._menu_window and self._menu_window.winfo_exists():
            self._close_menu()
        else:
            self._open_menu()

    def _open_menu(self):
        tk = self._tk
        self._menu_window = tk.Toplevel(self._root)
        self._menu_window.overrideredirect(True)
        self._menu_window.attributes("-topmost", True)
        self._menu_window.configure(bg="#2c2c2e")

        font_size = self.ui.get("hud_font_size", 14)
        current_id = self.mm.current.id
        for mode in self.mm.all:
            mark = " ✓" if mode.id == current_id else "  "
            label = tk.Label(
                self._menu_window,
                text=f"{mode.display}{mark}",
                fg="white", bg="#2c2c2e",
                font=("Helvetica", font_size),
                padx=14, pady=6, anchor="w", cursor="hand2",
            )
            label.pack(fill="x")
            label.bind("<Enter>", lambda e, w=label: w.config(bg="#3a3a3c"))
            label.bind("<Leave>", lambda e, w=label: w.config(bg="#2c2c2e"))
            label.bind("<Button-1>", lambda e, mid=mode.id: self._select_mode(mid))

        sep = tk.Frame(self._menu_window, height=1, bg="#48484a")
        sep.pack(fill="x", padx=8, pady=2)
        quit_label = tk.Label(
            self._menu_window, text="❌ 結束程式",
            fg="#ff453a", bg="#2c2c2e",
            font=("Helvetica", font_size),
            padx=14, pady=6, anchor="w", cursor="hand2",
        )
        quit_label.pack(fill="x")
        quit_label.bind("<Button-1>", lambda e: self.on_quit())

        self._root.update_idletasks()
        self._menu_window.update_idletasks()
        rx = self._root.winfo_rootx()
        ry = self._root.winfo_rooty()
        mh = self._menu_window.winfo_reqheight()
        self._menu_window.geometry(f"+{rx}+{ry - mh - 4}")

        self._menu_window.bind("<FocusOut>", lambda e: self._close_menu())
        self._menu_window.focus_set()

    def _close_menu(self):
        if self._menu_window:
            try:
                self._menu_window.destroy()
            except Exception:
                pass
            self._menu_window = None

    def _select_mode(self, mode_id: str):
        self.mm.set_by_id(mode_id)
        self._close_menu()

    def shutdown(self):
        if self._root:
            self._schedule(self._root.destroy)
