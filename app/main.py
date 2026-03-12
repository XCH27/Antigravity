from __future__ import annotations

import json
import os
import platform
import queue
import subprocess
import sys
import threading
import time
import tkinter as tk
from dataclasses import dataclass
from tkinter import filedialog, messagebox, ttk

try:
    # 以包形式运行（python -m app.main）
    from .api_client import (
        AnthropicClient,
        AnthropicConfig,
        decrypt_api_key,
        encrypt_api_key,
        GeminiClient,
        GeminiConfig,
        OpenAICompatClient,
        OpenAICompatConfig,
        PROVIDER_PRESETS,
        safe_get_env,
    )
except ImportError:
    try:
        # PyInstaller 打包后：模块保留完整包路径 app.api_client
        from app.api_client import (  # type: ignore
            AnthropicClient,
            AnthropicConfig,
            decrypt_api_key,
            encrypt_api_key,
            GeminiClient,
            GeminiConfig,
            OpenAICompatClient,
            OpenAICompatConfig,
            PROVIDER_PRESETS,
            safe_get_env,
        )
    except ImportError:
        # 兜底：直接裸导入
        from api_client import (  # type: ignore
            AnthropicClient,
            AnthropicConfig,
            decrypt_api_key,
            encrypt_api_key,
            GeminiClient,
            GeminiConfig,
            OpenAICompatClient,
            OpenAICompatConfig,
            PROVIDER_PRESETS,
            safe_get_env,
        )


def now_ts() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def collect_system_info() -> str:
    parts = [
        f"时间: {now_ts()}",
        f"系统: {platform.platform()}",
        f"Python: {platform.python_version()}",
        f"架构: {platform.machine()}",
        f"用户: {os.environ.get('USERNAME') or os.environ.get('USER') or 'unknown'}",
        f"工作目录: {os.getcwd()}",
    ]
    return "\n".join(parts)


def config_path() -> str:
    base = os.environ.get("APPDATA") or os.path.expanduser("~")
    d = os.path.join(base, "OpenClawInstaller")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "config.json")


def load_config() -> dict:
    p = config_path()
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_config(data: dict) -> None:
    p = config_path()
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, p)


def resource_path(rel_path: str) -> str:
    """
    兼容 PyInstaller：
    - 开发态：相对当前文件所在项目根目录
    - 打包态：sys._MEIPASS 下的资源目录
    """
    base = getattr(sys, "_MEIPASS", None)
    if isinstance(base, str) and base:
        return os.path.join(base, rel_path)
    # 当前文件：.../app/main.py -> 项目根目录为上一级
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    return os.path.join(root, rel_path)


def bundled_script_paths() -> ScriptPaths:
    # 根据系统选择默认脚本（Windows: ps1，其他: sh）
    if sys.platform.startswith("win"):
        install = resource_path(os.path.join("assets", "OpenClaw-Skill-Project", "scripts", "install.ps1"))
        uninstall = resource_path(os.path.join("assets", "OpenClaw-Skill-Project", "scripts", "uninstall.ps1"))
    else:
        install = resource_path(os.path.join("assets", "OpenClaw-Skill-Project", "scripts", "install.sh"))
        uninstall = resource_path(os.path.join("assets", "OpenClaw-Skill-Project", "scripts", "uninstall.sh"))
    return ScriptPaths(
        install_ps1=install if os.path.isfile(install) else None,
        uninstall_ps1=uninstall if os.path.isfile(uninstall) else None,
    )


class Status:
    IDLE = "idle"
    RUNNING = "running"
    OK = "ok"
    FAIL = "fail"


class Step:
    API = 1
    SCRIPT = 2
    RUN = 3
    DONE = 4


@dataclass
class ScriptPaths:
    install_ps1: str | None = None
    uninstall_ps1: str | None = None


def guess_scripts(root_dir: str) -> ScriptPaths:
    candidates = [
        os.path.join(root_dir, "scripts"),
        root_dir,
    ]
    install = None
    uninstall = None
    is_win = sys.platform.startswith("win")
    exts = [".ps1"] if is_win else [".sh", ".ps1"]
    for d in candidates:
        if os.path.isdir(d):
            for ext in exts:
                ip = os.path.join(d, f"install{ext}")
                up = os.path.join(d, f"uninstall{ext}")
                if install is None and os.path.isfile(ip):
                    install = ip
                if uninstall is None and os.path.isfile(up):
                    uninstall = up
    return ScriptPaths(install_ps1=install, uninstall_ps1=uninstall)


class LogBuffer:
    def __init__(self, limit_chars: int = 200_000):
        self.limit_chars = limit_chars
        self._buf: list[str] = []
        self._size = 0

    def append(self, s: str) -> None:
        if not s:
            return
        self._buf.append(s)
        self._size += len(s)
        while self._size > self.limit_chars and self._buf:
            drop = self._buf.pop(0)
            self._size -= len(drop)

    def text(self) -> str:
        return "".join(self._buf)


class ScriptRunner:
    def __init__(self, on_line):
        self.on_line = on_line
        self._proc: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()
        self._last_rc: int | None = None
        self._last_done: threading.Event | None = None

    def running(self) -> bool:
        with self._lock:
            return self._proc is not None and self._proc.poll() is None

    def last_rc(self) -> int | None:
        with self._lock:
            return self._last_rc

    def stop(self) -> None:
        with self._lock:
            p = self._proc
        if p and p.poll() is None:
            try:
                p.terminate()
            except Exception:
                pass

    def run_script(self, script_path: str) -> threading.Event:
        if self.running():
            raise RuntimeError("已有任务在运行，请先等待完成或点击“停止”。")
        if not os.path.isfile(script_path):
            raise FileNotFoundError(f"脚本不存在: {script_path}")

        if sys.platform.startswith("win"):
            cmd = [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                script_path,
            ]
        else:
            cmd = [
                "bash",
                script_path,
            ]

        done = threading.Event()
        with self._lock:
            self._last_done = done
            self._last_rc = None

        def _worker():
            self.on_line(f"[{now_ts()}] 开始执行: {' '.join(cmd)}\n")
            try:
                with self._lock:
                    self._proc = subprocess.Popen(
                        cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                    )
                    p = self._proc

                assert p.stdout is not None
                for line in p.stdout:
                    self.on_line(line)
                rc = p.wait()
                with self._lock:
                    self._last_rc = rc
                self.on_line(f"\n[{now_ts()}] 进程结束，退出码: {rc}\n")
            except Exception as e:
                with self._lock:
                    self._last_rc = -1
                self.on_line(f"\n[{now_ts()}] 执行失败: {e}\n")
            finally:
                with self._lock:
                    self._proc = None
                done.set()

        threading.Thread(target=_worker, daemon=True).start()
        return done


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("OpenClaw 图形化安装器（带 API 辅助）")
        self.geometry("980x700")

        self._apply_window_icon()
        self._init_styles()

        self.log_buf = LogBuffer()
        self.ui_queue: queue.Queue[str] = queue.Queue()
        self.runner = ScriptRunner(on_line=self._enqueue_log)

        self.skill_dir_var = tk.StringVar(value="")
        self.install_var = tk.StringVar(value="")
        self.uninstall_var = tk.StringVar(value="")

        cfg = load_config()
        # 解密 API Key（如果已加密存储）
        raw_key = cfg.get("api_key") or ""
        decrypted_key = decrypt_api_key(raw_key) if raw_key else ""

        self.provider_var = tk.StringVar(value=str(cfg.get("provider_id") or "chatgpt"))
        self.api_base_var = tk.StringVar(value=str(cfg.get("base_url") or safe_get_env("OPENAI_BASE_URL") or "https://api.openai.com/v1"))
        self.api_key_var = tk.StringVar(value=str(decrypted_key or safe_get_env("OPENAI_API_KEY") or ""))
        self.api_model_var = tk.StringVar(value=str(cfg.get("model") or safe_get_env("OPENAI_MODEL") or "gpt-4.1-mini"))
        self.ai_question_var = tk.StringVar(value="我卡在这里：\n\n（请结合日志告诉我下一步怎么做）")
        self.agent_running = False
        self.show_advanced_install_var = tk.BooleanVar(value=False)
        self.show_advanced_api_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value=Status.IDLE)
        self.step_var = tk.IntVar(value=Step.API)

        self._build_ui()
        self._auto_fill_bundled_scripts()
        self.after(50, self._drain_queue)

    def _init_styles(self) -> None:
        try:
            style = ttk.Style(self)
            # 当前主题下做一个轻量高亮
            style.configure("ActiveStep.TLabel", foreground="#1e88e5")
        except Exception:
            pass

    def _apply_window_icon(self) -> None:
        for rel in [
            os.path.join("assets", "app_icon.ico"),
            "app_icon.ico",
        ]:
            p = resource_path(rel)
            if os.path.isfile(p):
                try:
                    self.iconbitmap(p)
                except Exception:
                    pass
                break

    def _enqueue_log(self, s: str) -> None:
        self.ui_queue.put(s)

    def _drain_queue(self) -> None:
        drained = False
        while True:
            try:
                s = self.ui_queue.get_nowait()
            except queue.Empty:
                break
            drained = True
            self.log_buf.append(s)
            self.log_text.configure(state="normal")
            self.log_text.insert("end", s)
            self.log_text.see("end")
            self.log_text.configure(state="disabled")

        if drained:
            self._update_buttons_state()
            self._refresh_status_and_step()
        self.after(100, self._drain_queue)


    def _build_ui(self) -> None:
        ctrl = ttk.Frame(self, padding=(12, 8, 12, 0))
        ctrl.pack(fill="x")
        self._build_header(ctrl)
        self._build_api_section(ctrl)
        self._build_action_buttons(ctrl)
        self._build_ai_question_section(ctrl)

        out_nb = ttk.Notebook(self)
        out_nb.pack(fill="both", expand=True, padx=12, pady=(6, 12))
        self._build_log_tab(out_nb)
        self._build_ai_answer_tab(out_nb)

        self._toggle_install_advanced()
        self._toggle_api_advanced()
        self._toggle_ai_question()
        self._enqueue_log("欢迎使用 OpenClaw 图形化安装器。\n")
        self._enqueue_log('提示：直接点"使用内置脚本" + "安装"即可。\n\n')
        self._update_buttons_state()
        self._refresh_status_and_step()

    def _build_header(self, parent: ttk.Frame) -> None:
        header = ttk.Frame(parent)
        header.pack(fill="x")
        self.step_labels: dict[int, ttk.Label] = {}
        steps = [
            (Step.API, "1 配置 API"),
            (Step.SCRIPT, "2 脚本"),
            (Step.RUN, "3 安装中"),
            (Step.DONE, "4 完成"),
        ]
        for i, (sid, text) in enumerate(steps):
            lbl = ttk.Label(header, text=text, padding=(6, 2))
            lbl.pack(side="left")
            self.step_labels[sid] = lbl
            if i != len(steps) - 1:
                ttk.Label(header, text=">", padding=(6, 2)).pack(side="left")
        header_right = ttk.Frame(header)
        header_right.pack(side="right")
        ttk.Label(header_right, text="状态：").pack(side="left")
        self.status_canvas = tk.Canvas(header_right, width=14, height=14, highlightthickness=0)
        self.status_canvas.pack(side="left", padx=(0, 6))
        self.status_dot = self.status_canvas.create_oval(2, 2, 12, 12, fill="#9e9e9e", outline="#9e9e9e")
        self.status_text = ttk.Label(header_right, text="空闲")
        self.status_text.pack(side="left")
        self.progress = ttk.Progressbar(parent, mode="indeterminate")
        self.progress.pack(fill="x", pady=(6, 0))

    def _build_api_section(self, parent: ttk.Frame) -> None:
        cfg = ttk.LabelFrame(parent, text="AI 配置", padding=(10, 6))
        cfg.pack(fill="x", pady=(8, 0))
        r0 = ttk.Frame(cfg)
        r0.pack(fill="x")
        ttk.Label(r0, text="提供方：").pack(side="left")
        self.provider_combo = ttk.Combobox(
            r0, state="readonly",
            values=[p.label for p in PROVIDER_PRESETS],
            width=28,
        )
        self._sync_provider_combo_from_id()
        self.provider_combo.pack(side="left", padx=(4, 8))
        ttk.Button(r0, text="应用预设", command=self._apply_provider_preset).pack(side="left")
        ttk.Button(r0, text="申请入口", command=self._copy_provider_apply_url).pack(side="left", padx=(6, 0))
        ttk.Checkbutton(
            r0, text="高级 (Base URL)",
            variable=self.show_advanced_api_var,
            command=self._toggle_api_advanced,
        ).pack(side="right")
        self.api_adv_frame = ttk.Frame(cfg)
        r_base = ttk.Frame(self.api_adv_frame)
        r_base.pack(fill="x", pady=(4, 0))
        ttk.Label(r_base, text="Base URL：", width=10).pack(side="left")
        ttk.Entry(r_base, textvariable=self.api_base_var).pack(side="left", fill="x", expand=True, padx=4)
        r2 = ttk.Frame(cfg)
        r2.pack(fill="x", pady=(6, 0))
        ttk.Label(r2, text="API Key：", width=10).pack(side="left")
        ttk.Entry(r2, textvariable=self.api_key_var, show="*").pack(side="left", fill="x", expand=True, padx=4)
        r3 = ttk.Frame(cfg)
        r3.pack(fill="x", pady=(4, 0))
        ttk.Label(r3, text="Model：", width=10).pack(side="left")
        ttk.Entry(r3, textvariable=self.api_model_var).pack(side="left", fill="x", expand=True, padx=4)
        ttk.Button(r3, text="保存配置", command=self._save_api_config).pack(side="left", padx=(6, 0))

    def _build_action_buttons(self, parent: ttk.Frame) -> None:
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=(8, 0))
        self.btn_install = ttk.Button(row, text="安装", command=self._run_install)
        self.btn_uninstall = ttk.Button(row, text="卸载", command=self._run_uninstall)
        self.btn_stop = ttk.Button(row, text="停止", command=self._stop)
        self.btn_use_bundled = ttk.Button(row, text="使用内置脚本", command=self._use_bundled_scripts)
        self.btn_install.pack(side="left")
        self.btn_uninstall.pack(side="left", padx=(6, 0))
        self.btn_stop.pack(side="left", padx=(6, 0))
        self.btn_use_bundled.pack(side="left", padx=(6, 0))
        ttk.Separator(row, orient="vertical").pack(side="left", fill="y", padx=10, pady=2)
        self.btn_ai = ttk.Button(row, text="问答", command=self._ask_ai)
        self.btn_agent_install = ttk.Button(row, text="自动安装", command=self._agent_auto_install)
        self.btn_agent_stop = ttk.Button(row, text="停止 Agent", command=self._agent_stop)
        self.btn_ai.pack(side="left")
        self.btn_agent_install.pack(side="left", padx=(6, 0))
        self.btn_agent_stop.pack(side="left", padx=(6, 0))
        self.btn_copylog = ttk.Button(row, text="复制日志", command=self._copy_log)
        self.btn_clearlg = ttk.Button(row, text="清空", command=self._clear_log)
        self.btn_copylog.pack(side="right")
        self.btn_clearlg.pack(side="right", padx=(0, 6))
        adv_row = ttk.Frame(parent)
        adv_row.pack(fill="x", pady=(4, 0))
        ttk.Checkbutton(
            adv_row, text="高级（显示脚本路径）",
            variable=self.show_advanced_install_var,
            command=self._toggle_install_advanced,
        ).pack(side="left")
        self.install_adv_frame = ttk.Frame(parent)
        r1 = ttk.Frame(self.install_adv_frame)
        r1.pack(fill="x", pady=(4, 0))
        ttk.Label(r1, text="脚本目录：", width=10).pack(side="left")
        ttk.Entry(r1, textvariable=self.skill_dir_var).pack(side="left", fill="x", expand=True, padx=4)
        ttk.Button(r1, text="选择", command=self._pick_skill_dir).pack(side="left")
        r2 = ttk.Frame(self.install_adv_frame)
        r2.pack(fill="x", pady=(4, 0))
        ttk.Label(r2, text="安装脚本：", width=10).pack(side="left")
        ttk.Entry(r2, textvariable=self.install_var).pack(side="left", fill="x", expand=True, padx=4)
        ttk.Button(r2, text="选择", command=self._pick_install).pack(side="left")
        r3 = ttk.Frame(self.install_adv_frame)
        r3.pack(fill="x", pady=(4, 0))
        ttk.Label(r3, text="卸载脚本：", width=10).pack(side="left")
        ttk.Entry(r3, textvariable=self.uninstall_var).pack(side="left", fill="x", expand=True, padx=4)
        ttk.Button(r3, text="选择", command=self._pick_uninstall).pack(side="left")

    def _build_ai_question_section(self, parent: ttk.Frame) -> None:
        self.show_ai_question_var = tk.BooleanVar(value=False)
        toggle_row = ttk.Frame(parent)
        toggle_row.pack(fill="x", pady=(4, 0))
        ttk.Checkbutton(
            toggle_row, text="显示 AI 提问框",
            variable=self.show_ai_question_var,
            command=self._toggle_ai_question,
        ).pack(side="left")
        ttk.Button(
            toggle_row, text="粘贴日志到提问框",
            command=self._paste_log_to_question,
        ).pack(side="left", padx=(8, 0))
        self.ai_q_frame = ttk.Frame(parent)
        self.ai_q_text = tk.Text(self.ai_q_frame, wrap="word", height=5)
        self.ai_q_text.pack(fill="x", pady=(4, 0))
        self.ai_q_text.insert("1.0", self.ai_question_var.get())

    def _build_log_tab(self, nb: ttk.Notebook) -> None:
        frame = ttk.Frame(nb, padding=(0, 4, 0, 0))
        nb.add(frame, text="运行日志")
        self.log_text = tk.Text(frame, wrap="word")
        scroll = ttk.Scrollbar(frame, orient="vertical", command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scroll.set, state="disabled")
        scroll.pack(side="right", fill="y")
        self.log_text.pack(fill="both", expand=True)

    def _build_ai_answer_tab(self, nb: ttk.Notebook) -> None:
        frame = ttk.Frame(nb, padding=(0, 4, 0, 0))
        nb.add(frame, text="AI 回复")
        self.ai_a_text = tk.Text(frame, wrap="word")
        scroll = ttk.Scrollbar(frame, orient="vertical", command=self.ai_a_text.yview)
        self.ai_a_text.configure(yscrollcommand=scroll.set, state="disabled")
        scroll.pack(side="right", fill="y")
        self.ai_a_text.pack(fill="both", expand=True)

    def _build_install_tab(self) -> None:
        pass

    def _build_ai_tab(self) -> None:
        pass

    def _build_about_tab(self) -> None:
        pass

    def _toggle_install_advanced(self) -> None:
        if self.show_advanced_install_var.get():
            self.install_adv_frame.pack(fill="x", pady=(2, 0))
        else:
            self.install_adv_frame.pack_forget()

    def _toggle_api_advanced(self) -> None:
        if self.show_advanced_api_var.get():
            self.api_adv_frame.pack(fill="x", pady=(4, 0))
        else:
            self.api_adv_frame.pack_forget()

    def _toggle_ai_question(self) -> None:
        if self.show_ai_question_var.get():
            self.ai_q_frame.pack(fill="x", pady=(2, 0))
        else:
            self.ai_q_frame.pack_forget()


    def _update_buttons_state(self) -> None:
        running = self.runner.running()
        self.btn_stop.configure(state=("normal" if running else "disabled"))
        self.btn_install.configure(state=("disabled" if running else "normal"))
        self.btn_uninstall.configure(state=("disabled" if running else "normal"))

        # 进度条：脚本或 Agent 在跑就动
        if getattr(self, "progress", None) is not None:
            if running or self.agent_running:
                try:
                    self.progress.start(10)
                except Exception:
                    pass
            else:
                try:
                    self.progress.stop()
                except Exception:
                    pass

    def _refresh_status_and_step(self) -> None:
        if not hasattr(self, "status_text"):
            return

        api_ready = bool(self.api_key_var.get().strip() and self.api_model_var.get().strip() and self.api_base_var.get().strip())
        script_ready = bool(self.install_var.get().strip())
        running = self.runner.running() or self.agent_running
        rc = self.runner.last_rc()

        if running:
            self.status_var.set(Status.RUNNING)
        else:
            if rc is None:
                self.status_var.set(Status.IDLE)
            elif rc == 0:
                self.status_var.set(Status.OK)
            else:
                self.status_var.set(Status.FAIL)

        if not api_ready:
            self.step_var.set(Step.API)
        elif not script_ready:
            self.step_var.set(Step.SCRIPT)
        elif running:
            self.step_var.set(Step.RUN)
        else:
            if rc == 0:
                self.step_var.set(Step.DONE)
            else:
                self.step_var.set(Step.SCRIPT)

        self._render_status()
        self._render_steps()

    def _render_status(self) -> None:
        st = self.status_var.get()
        if st == Status.IDLE:
            color, text = "#9e9e9e", "空闲"
        elif st == Status.RUNNING:
            color, text = "#1e88e5", "运行中"
        elif st == Status.OK:
            color, text = "#43a047", "成功"
        else:
            color, text = "#e53935", "失败"
        try:
            self.status_canvas.itemconfig(self.status_dot, fill=color, outline=color)
        except Exception:
            pass
        self.status_text.configure(text=text)

    def _render_steps(self) -> None:
        cur = int(self.step_var.get())
        if not hasattr(self, "step_labels"):
            return
        for sid, lbl in self.step_labels.items():
            try:
                if sid == cur:
                    lbl.configure(style="ActiveStep.TLabel")
                else:
                    lbl.configure(style="TLabel")
            except Exception:
                pass

    def _pick_skill_dir(self) -> None:
        d = filedialog.askdirectory(title="选择技能/脚本目录")
        if not d:
            return
        self.skill_dir_var.set(d)
        guessed = guess_scripts(d)
        if guessed.install_ps1 and not self.install_var.get():
            self.install_var.set(guessed.install_ps1)
        if guessed.uninstall_ps1 and not self.uninstall_var.get():
            self.uninstall_var.set(guessed.uninstall_ps1)
        self._enqueue_log(f"[{now_ts()}] 已选择目录: {d}\n")
        if guessed.install_ps1:
            self._enqueue_log(f"[{now_ts()}] 发现安装脚本: {guessed.install_ps1}\n")
        if guessed.uninstall_ps1:
            self._enqueue_log(f"[{now_ts()}] 发现卸载脚本: {guessed.uninstall_ps1}\n")
        self._enqueue_log("\n")

    def _pick_install(self) -> None:
        ft = [("Script", "*.ps1;*.sh"), ("All", "*.*")]
        p = filedialog.askopenfilename(title="选择安装脚本", filetypes=ft)
        if p:
            self.install_var.set(p)

    def _pick_uninstall(self) -> None:
        ft = [("Script", "*.ps1;*.sh"), ("All", "*.*")]
        p = filedialog.askopenfilename(title="选择卸载脚本", filetypes=ft)
        if p:
            self.uninstall_var.set(p)

    def _run_install(self) -> None:
        p = self.install_var.get().strip()
        if not p:
            messagebox.showerror("缺少脚本", "请先选择安装脚本（或选择脚本目录让程序自动识别）。")
            return
        try:
            self.runner.run_script(p)
            self._refresh_status_and_step()
        except Exception as e:
            messagebox.showerror("无法运行", str(e))

    def _run_uninstall(self) -> None:
        p = self.uninstall_var.get().strip()
        if not p:
            messagebox.showerror("缺少脚本", "请先选择卸载脚本（或选择脚本目录让程序自动识别）。")
            return
        try:
            self.runner.run_script(p)
            self._refresh_status_and_step()
        except Exception as e:
            messagebox.showerror("无法运行", str(e))

    def _stop(self) -> None:
        self.runner.stop()
        self._enqueue_log(f"[{now_ts()}] 已发送停止信号（若脚本在执行关键步骤，可能需要稍等）。\n")
        self._refresh_status_and_step()

    def _copy_log(self) -> None:
        s = self.log_buf.text()
        self.clipboard_clear()
        self.clipboard_append(s)
        messagebox.showinfo("已复制", "日志已复制到剪贴板。")

    def _clear_log(self) -> None:
        self.log_buf = LogBuffer()
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")

    def _paste_log_to_question(self) -> None:
        log = self.log_buf.text().strip()
        if not log:
            messagebox.showinfo("无日志", "当前没有日志内容。")
            return
        self.ai_q_text.insert("end", "\n\n---\n以下为运行日志（节选/完整）：\n" + log[-50_000:] + "\n")

    def _ask_ai(self) -> None:
        provider = self._selected_provider()
        base_url = self.api_base_var.get().strip()
        api_key = self.api_key_var.get().strip()
        model = self.api_model_var.get().strip()
        question = self.ai_q_text.get("1.0", "end").strip()

        if not base_url or not api_key or not model:
            messagebox.showerror("缺少配置", "请填写 Base URL / API Key / Model。")
            return
        if not question:
            messagebox.showerror("缺少问题", "请输入你的问题。")
            return

        sys_info = collect_system_info()
        log_tail = self.log_buf.text().strip()[-50_000:]
        prompt = (
            "【系统信息】\n"
            f"{sys_info}\n\n"
            "【最近日志（末尾）】\n"
            f"{log_tail}\n\n"
            "【用户问题】\n"
            f"{question}\n"
        )
        system = (
            "你是一个 Windows 安装与排障助手。"
            "你要用中文给出可执行的下一步排查/解决步骤。"
            "不要要求用户去打开网页；如果必须引用概念，直接解释要点。"
            "不要编造已经成功/失败的结论；基于用户提供的系统信息与日志推断。"
            "输出用清晰的步骤列表。"
        )

        self._set_ai_answer("正在请求 API，请稍等...\n")

        def _worker():
            try:
                ans = self._call_provider_chat(provider_id=provider["id"], base_url=base_url, api_key=api_key, model=model, system=system, user=prompt)
                self._set_ai_answer(ans)
            except Exception as e:
                self._set_ai_answer(f"请求失败：{e}")

        threading.Thread(target=_worker, daemon=True).start()

    def _agent_stop(self) -> None:
        self.agent_running = False
        self.runner.stop()
        self._set_ai_answer("已请求停止 Agent。若正在执行脚本，可能需要等待脚本退出。\n")
        self._refresh_status_and_step()

    def _agent_auto_install(self) -> None:
        """
        Agent 模式：让模型输出严格 JSON 动作，程序按白名单自动执行并回传结果，直到 done。
        """
        if self.agent_running:
            messagebox.showinfo("已在运行", "Agent 正在运行中。")
            return

        provider = self._selected_provider()
        base_url = self.api_base_var.get().strip()
        api_key = self.api_key_var.get().strip()
        model = self.api_model_var.get().strip()
        if not base_url or not api_key or not model:
            messagebox.showerror("缺少配置", "请先在上方填写 Base URL / API Key / Model。")
            return

        install_ps1 = self.install_var.get().strip()
        if not install_ps1:
            messagebox.showerror("缺少脚本", "请先选择 install.ps1（或选择技能目录让程序自动识别）。")
            return

        self.agent_running = True
        self._set_ai_answer("Agent 启动中：将自动尝试安装，并在失败时自动排障/重试。\n")
        self._refresh_status_and_step()

        def _worker():
            try:
                self._agent_loop(provider_id=provider["id"], base_url=base_url, api_key=api_key, model=model)
            except Exception as e:
                self._set_ai_answer(f"Agent 启动失败：{e}")
            finally:
                self.agent_running = False
                self._refresh_status_and_step()

        threading.Thread(target=_worker, daemon=True).start()

    def _agent_loop(self, *, provider_id: str, base_url: str, api_key: str, model: str) -> None:
        system = (
            "你是一个 Windows 安装自动化智能体（Agent）。"
            "你必须输出严格的 JSON（不要输出多余文字），用于驱动一个图形化安装器执行动作。"
            "允许的 action 只有："
            "run_install, run_uninstall, suggest, done, fail。"
            "当需要执行安装时输出："
            '{"action":"run_install"}'
            "当需要执行卸载时输出："
            '{"action":"run_uninstall"}'
            "当需要给用户解释/说明但不需要执行时输出："
            '{"action":"suggest","message":"...中文建议..."}'
            "成功结束输出："
            '{"action":"done","message":"..."}'
            "确定失败且无法继续输出："
            '{"action":"fail","message":"...","reason":"..."}'
            "你不能要求用户去打开网页；你要基于系统信息和日志做决策。"
        )

        max_turns = 12
        last_message = ""

        for turn in range(1, max_turns + 1):
            if not self.agent_running:
                self._set_ai_answer("Agent 已停止。\n")
                return

            sys_info = collect_system_info()
            log_tail = self.log_buf.text().strip()[-50_000:]
            context = {
                "turn": turn,
                "system_info": sys_info,
                "install_ps1": self.install_var.get().strip(),
                "uninstall_ps1": self.uninstall_var.get().strip(),
                "last_rc": self.runner.last_rc(),
                "log_tail": log_tail,
                "last_message": last_message,
            }
            user = (
                "你的目标：把目标程序安装成功。"
                "如果安装失败，先分析日志，给出最小必要的修复动作，再重试。"
                "现在给出下一步 action。\n\n"
                + json.dumps(context, ensure_ascii=False)
            )

            raw = self._call_provider_chat(
                provider_id=provider_id,
                base_url=base_url,
                api_key=api_key,
                model=model,
                system=system,
                user=user,
            )
            parsed = self._agent_parse_json(raw)
            if parsed is None:
                last_message = f"解析失败：{raw[:500]}"
                self._set_ai_answer("Agent 输出无法解析为 JSON，停止以避免误操作。\n\n原始输出：\n" + raw)
                return

            action = parsed.get("action")
            if action == "suggest":
                msg = str(parsed.get("message") or "").strip()
                last_message = msg
                self._set_ai_answer(msg or "（空建议）")
                return

            if action == "done":
                msg = str(parsed.get("message") or "安装完成。").strip()
                self._set_ai_answer(msg)
                return

            if action == "fail":
                msg = str(parsed.get("message") or "安装失败。").strip()
                reason = str(parsed.get("reason") or "").strip()
                out = msg + (("\n\n原因：\n" + reason) if reason else "")
                self._set_ai_answer(out)
                return

            if action == "run_install":
                script = self.install_var.get().strip()
                self._set_ai_answer("Agent：正在运行安装脚本...\n")
                try:
                    done = self.runner.run_script(script)
                except Exception as e:
                    last_message = f"运行安装脚本失败：{e}"
                    continue
                while not done.wait(timeout=0.5):
                    if not self.agent_running:
                        self._set_ai_answer("Agent 已停止（脚本可能仍在退出中）。\n")
                        return
                rc = self.runner.last_rc()
                last_message = f"安装脚本退出码: {rc}"
                continue

            if action == "run_uninstall":
                script = self.uninstall_var.get().strip()
                if not script:
                    last_message = "没有 uninstall.ps1/sh，但模型要求卸载。"
                    continue
                self._set_ai_answer("Agent：正在运行卸载脚本...\n")
                try:
                    done = self.runner.run_script(script)
                except Exception as e:
                    last_message = f"运行卸载脚本失败：{e}"
                    continue
                while not done.wait(timeout=0.5):
                    if not self.agent_running:
                        self._set_ai_answer("Agent 已停止（脚本可能仍在退出中）。\n")
                        return
                rc = self.runner.last_rc()
                last_message = f"卸载脚本退出码: {rc}"
                continue

            last_message = f"不支持的 action: {action}"

        self._set_ai_answer("Agent 达到最大轮次仍未完成。建议你复制日志到问题框，改用“仅建议”模式继续排障。\n")

    def _call_provider_chat(self, *, provider_id: str, base_url: str, api_key: str, model: str, system: str, user: str) -> str:
        preset = next((p for p in PROVIDER_PRESETS if p.id == provider_id), None)
        if preset is None:
            raise RuntimeError(f"未知提供方: {provider_id}")
        if preset.api_kind == "openai_compat":
            return OpenAICompatClient(OpenAICompatConfig(base_url=base_url, api_key=api_key, model=model)).chat(system=system, user=user)
        if preset.api_kind == "anthropic":
            return AnthropicClient(AnthropicConfig(base_url=base_url, api_key=api_key, model=model)).chat(system=system, user=user)
        if preset.api_kind == "gemini":
            return GeminiClient(GeminiConfig(base_url=base_url, api_key=api_key, model=model)).chat(system=system, user=user)
        raise RuntimeError(f"不支持的 api_kind: {preset.api_kind}")

    def _selected_provider(self) -> dict:
        pid = (self.provider_var.get() or "chatgpt").strip()
        preset = next((p for p in PROVIDER_PRESETS if p.id == pid), None)
        if preset is None:
            preset = next((p for p in PROVIDER_PRESETS if p.id == "chatgpt"), PROVIDER_PRESETS[0])
            self.provider_var.set(preset.id)
        return {"id": preset.id, "label": preset.label, "api_kind": preset.api_kind, "apply_url": preset.apply_url}

    def _sync_provider_combo_from_id(self) -> None:
        pid = (self.provider_var.get() or "chatgpt").strip()
        idx = 0
        for i, p in enumerate(PROVIDER_PRESETS):
            if p.id == pid:
                idx = i
                break
        # ttk.Combobox 用当前选中项
        try:
            self.provider_combo.current(idx)
        except Exception:
            pass

    def _apply_provider_preset(self) -> None:
        # 以 combobox 当前 label 反查 preset
        label = self.provider_combo.get().strip()
        preset = next((p for p in PROVIDER_PRESETS if p.label == label), None)
        if preset is None:
            return
        self.provider_var.set(preset.id)
        if preset.default_base_url:
            self.api_base_var.set(preset.default_base_url)
        if preset.default_model:
            self.api_model_var.set(preset.default_model)
        # key 不自动覆盖，避免覆盖用户已填内容
        self._enqueue_log(f"[{now_ts()}] 已应用 API 预设：{preset.label}\n\n")

    def _copy_provider_apply_url(self) -> None:
        label = self.provider_combo.get().strip()
        preset = next((p for p in PROVIDER_PRESETS if p.label == label), None)
        if preset is None:
            preset = next((p for p in PROVIDER_PRESETS if p.id == self.provider_var.get().strip()), None)
        if preset is None:
            messagebox.showerror("未知提供方", "未找到提供方信息。")
            return
        self.clipboard_clear()
        self.clipboard_append(preset.apply_url)
        messagebox.showinfo("已复制", f"申请入口已复制到剪贴板：\n{preset.apply_url}")

    def _save_api_config(self) -> None:
        label = self.provider_combo.get().strip()
        preset = next((p for p in PROVIDER_PRESETS if p.label == label), None)
        if preset is not None:
            self.provider_var.set(preset.id)

        raw_key = self.api_key_var.get().strip()
        encrypted_key = encrypt_api_key(raw_key) if raw_key else ""

        data = {
            "provider_id": self.provider_var.get().strip() or "chatgpt",
            "base_url": self.api_base_var.get().strip(),
            "api_key": encrypted_key,  # 加密存储
            "model": self.api_model_var.get().strip(),
            "saved_at": now_ts(),
        }
        try:
            save_config(data)
            messagebox.showinfo("已保存", f"配置已保存到：\n{config_path()}")
        except Exception as e:
            messagebox.showerror("保存失败", str(e))

    def _auto_fill_bundled_scripts(self) -> None:
        # 只有在用户尚未指定脚本时才自动填充
        if self.install_var.get().strip():
            return
        paths = bundled_script_paths()
        if paths.install_ps1:
            self.install_var.set(paths.install_ps1)
        if paths.uninstall_ps1:
            self.uninstall_var.set(paths.uninstall_ps1)
        if paths.install_ps1:
            self._enqueue_log(f"[{now_ts()}] 已检测到内置 install.ps1，已自动填充。\n")
        if paths.uninstall_ps1:
            self._enqueue_log(f"[{now_ts()}] 已检测到内置 uninstall.ps1，已自动填充。\n")
        if paths.install_ps1 or paths.uninstall_ps1:
            self._enqueue_log("\n")

    def _use_bundled_scripts(self) -> None:
        paths = bundled_script_paths()
        if not paths.install_ps1:
            messagebox.showerror("未找到内置脚本", "当前安装器包内未找到内置脚本资源。")
            return
        self.install_var.set(paths.install_ps1)
        if paths.uninstall_ps1:
            self.uninstall_var.set(paths.uninstall_ps1)
        self._enqueue_log(f"[{now_ts()}] 已切换为内置脚本。\n\n")

    def _agent_parse_json(self, s: str) -> dict | None:
        try:
            s2 = s.strip()
            # 容错：如果模型包在 ```json ... ``` 里
            if s2.startswith("```"):
                s2 = s2.strip("`")
                s2 = s2.replace("json", "", 1).strip()
            data = json.loads(s2)
            if isinstance(data, dict):
                return data
            return None
        except Exception:
            return None

    def _set_ai_answer(self, s: str) -> None:
        def _apply():
            self.ai_a_text.configure(state="normal")
            self.ai_a_text.delete("1.0", "end")
            self.ai_a_text.insert("1.0", s)
            self.ai_a_text.configure(state="disabled")

        self.after(0, _apply)


def main() -> None:
    app = App()
    app.mainloop()


if __name__ == "__main__":
    main()

