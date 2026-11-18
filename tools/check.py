"""Bounded Godot checks: argument arrays, live output, isolated saves, no shell."""
import argparse
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
ERROR_LINE = re.compile(r"^(?:ERROR:|SCRIPT ERROR\b|Parse Error\b|Compile Error\b|(?:[A-Z0-9_ /-]*\s)?(?:FAILED\b|FAIL:))")
AUDIO_SHUTDOWN_ERROR = re.compile(r"^ERROR: (?P<count>\d+) resources still in use at exit\.?$")
RESOURCE_IN_USE = re.compile(r"^Resource still in use: (?P<path>res://[^ ]+ \([^)]+\))$")
LEAKED_INSTANCE = re.compile(r"^Leaked instance: (?P<class>[^:]+):")


def known_audio_shutdown(output, expected_errors=()):
    """Allow only identified project WAV shutdown references, never unknown resources."""
    lines = [line.strip() for line in output.splitlines()]
    error_lines = [line for line in lines if ERROR_LINE.match(line) and line.strip() not in expected_errors]
    if len(error_lines) != 1:
        return False
    error = AUDIO_SHUTDOWN_ERROR.match(error_lines[0])
    if not error:
        return False
    resources = {match.group("path") for line in lines if (match := RESOURCE_IN_USE.match(line))}
    classes = {match.group("class") for line in lines if (match := LEAKED_INSTANCE.match(line))}
    return (int(error.group("count")) == len(resources) and bool(resources)
            and all(path.startswith("res://assets/audio/") and path.endswith("(AudioStreamWAV)") for path in resources)
            and bool(classes) and classes <= {"AudioStreamWAV", "AudioStreamPlaybackWAV"})


class WindowsJob:
    """Closing this unnamed job stops only the check and its descendants."""
    def __init__(self):
        class Limits(ctypes.Structure):
            _fields_ = [("process_time", ctypes.c_longlong), ("job_time", ctypes.c_longlong),
                        ("flags", wintypes.DWORD), ("min_working", ctypes.c_size_t),
                        ("max_working", ctypes.c_size_t), ("active", wintypes.DWORD),
                        ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD),
                        ("scheduling", wintypes.DWORD)]
        class Extended(ctypes.Structure):
            _fields_ = [("basic", Limits), ("io", ctypes.c_ulonglong * 6),
                        ("process_memory", ctypes.c_size_t), ("job_memory", ctypes.c_size_t),
                        ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]
        self.api = ctypes.WinDLL("kernel32", use_last_error=True)
        for name, args, result in [
            ("CreateJobObjectW", [wintypes.LPVOID, wintypes.LPCWSTR], wintypes.HANDLE),
            ("SetInformationJobObject", [wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD], wintypes.BOOL),
            ("OpenProcess", [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
            ("AssignProcessToJobObject", [wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            ("CloseHandle", [wintypes.HANDLE], wintypes.BOOL),
        ]:
            func = getattr(self.api, name)
            func.argtypes, func.restype = args, result
        self.handle = self.api.CreateJobObjectW(None, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        limits = Extended()
        limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.api.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            error = ctypes.WinError(ctypes.get_last_error())
            self.close()
            raise error

    def attach(self, process):
        handle = self.api.OpenProcess(0x0101, False, process.pid)  # SET_QUOTA | TERMINATE
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            if not self.api.AssignProcessToJobObject(self.handle, handle):
                raise ctypes.WinError(ctypes.get_last_error())
        finally:
            self.api.CloseHandle(handle)

    def close(self):
        if self.handle:
            self.api.CloseHandle(self.handle)
            self.handle = None


def run_command(command, timeout, env, expected_errors=()):
    """Run one explicit argv; never evaluate a shell command or match processes by name."""
    start = time.monotonic()
    job = WindowsJob() if os.name == "nt" else None
    process = None
    reader = None
    reason = ""
    output_lines = []
    code = 1
    try:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding="utf-8", errors="replace",
                                   start_new_session=os.name != "nt")
        if job:
            job.attach(process)
        lines = queue.Queue()

        def read_output():
            for line in process.stdout:
                lines.put(line)
            lines.put(None)

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        while True:
            if time.monotonic() - start >= timeout:
                reason = f"timeout after {timeout}s"
                break
            try:
                line = lines.get(timeout=0.04)
            except queue.Empty:
                continue
            if line is None:
                # A child may close its output before it exits; the deadline still applies.
                try:
                    code = process.wait(timeout=max(0.001, timeout - (time.monotonic() - start)))
                except subprocess.TimeoutExpired:
                    reason = f"timeout after {timeout}s"
                break
            print(line, end="", flush=True)
            output_lines.append(line.rstrip("\r\n"))
            if ERROR_LINE.match(line.lstrip()):
                if line.strip() in expected_errors:
                    print("EXPECTED TEST DIAGNOSTIC: " + line.strip(), flush=True)
                    continue
                if not AUDIO_SHUTDOWN_ERROR.match(line.strip()):
                    reason = "script/test error output"
                    break
    finally:
        if job:
            job.close()
        elif process:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if process:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=2)
            if reader:
                reader.join(timeout=1)
            process.stdout.close()
    output = "\n".join(output_lines)
    unexpected_errors = [line for line in output_lines
                         if ERROR_LINE.match(line.lstrip()) and line.strip() not in expected_errors]
    if not reason and unexpected_errors:
        if known_audio_shutdown(output, expected_errors):
            print("KNOWN LIMITATION: Godot audio resources remain referenced at shutdown.", flush=True)
        else:
            reason = "unrecognized error output"
    if reason:
        print(f"FAILED: {reason}", flush=True)
        code = 1
    return code, time.monotonic() - start


def steps(fast=False):
    """One canonical table: `default` rows run with no arguments, the rest are
    opt-in through --only. Limits keep recent measurements plus margin; import
    keeps startup/import/editor teardown margin after two 10s timeouts."""
    seeds = 4 if fast else 32
    table = [
        # --- default: the contract set a change must not break ---
        ("Import assets / compile scripts", ["--editor", "--import"], 30, True),
        ("Data + damage formula tests", ["tests/run_tests.tscn"], 8, True),
        ("Biome route graph", ["--script", "res://tests/route_graph_probe.gd"], 8, True),
        ("Biome modules / sockets / collision reach", ["--script", "res://tests/biome_gen_probe.gd", "--", f"--seeds={seeds}"], 20 if fast else 35, True),
        ("Spatial embeddings / latest geometry", ["--script", "res://tests/generation_spatial_probe.gd"], 8, True),
        ("Biome traversal / keys / map / one-way decks", ["tests/biome_play_probe.tscn"], 30, True),
        ("Three save slots / entry and Passage checkpoint transactions", ["tests/save_slots_probe.tscn"], 16, True),
        ("Failed terminal settlement / keyboard retry and quit", ["tests/terminal_failure_probe.tscn"], 8, True),
        ("Combat HUD readability / canonical recharge", ["tests/hud_readability_probe.tscn"], 8, True),
        ("L3 run build / combat / economy", ["tests/l3_build_probe.tscn"], 30, True),
        ("L4 Passage services / atomic progression", ["tests/l4_passage_probe.tscn"], 30, True),
        ("L5 three distinct boss behaviors", ["tests/l5_boss_probe.tscn"], 35, True),
        ("L5 nine-visit lifecycle / atomic finale", ["tests/l5_route_probe.tscn"], 40, True),
        # --- opt-in extras: same behaviour, narrower purpose ---
        ("UI product probe / zh_TW first frame, shipped face, native text", ["tests/ui_product_probe.tscn"], 60, False),
        ("Settings preferences / locale / rebind / display preview", ["tests/settings_probe.tscn"], 30, False),
        ("World map font layout / keyboard modal", ["tests/world_map_probe.tscn"], 8, False),
        ("Collector pause / display", ["tests/collector_display_probe.tscn"], 8, False),
        ("Profile CLI isolation / paths", ["tests/profile_safety_probe.tscn"], 8, False),
        ("Profile migration / legacy protection", ["tests/profile_migration_probe.tscn"], 8, False),
        ("Profile purchase commit / failure rollback", ["tests/profile_purchase_probe.tscn"], 8, False),
        ("Profile selection commit / UI failure rollback", ["tests/profile_selection_probe.tscn"], 8, False),
        ("Generator revision / latest save and resume", ["tests/generation_revision_probe.tscn"], 10, False),
        ("Contact edge / source fallback / unchanged knockback", ["tests/contact_probe.tscn"], 8, False),
        ("Reward probe (keyboard boon picker)", ["tests/reward_probe.tscn"], 8, False),
        ("Hub panels (open/close/buy)", ["tests/esc_probe.tscn"], 10, False),
        ("Hub -> floor handoff", ["tests/floor_probe.tscn"], 8, False),
        ("Abandon run / death settlement", ["tests/restart_probe.tscn"], 8, False),
        ("Audio ownership across scene transitions", ["tests/audio_lifetime_probe.tscn"], 16, False),
        ("Combat probe (hit, damage, death, i-frames)", ["tests/combat_probe.tscn"], 15, False),
        ("Soak (all enemies, waves, victory)", ["tests/soak.tscn"], 50, False),
        ("L1 run slice (two routes -> first boss)", ["tests/run_probe.tscn"], 40, False),
        ("L6 focused Passage UI", ["tests/l6_input_play.tscn", "--", "--passage-only"], 30, False),
        ("L6 automatic keyboard primary / alternate clear", ["tests/l6_input_play.tscn"], 900, False),
        ("Audit: combat / weapons", ["tests/audit_a1.tscn"], 45, False),
        ("Audit: save / economy", ["tests/audit_a2.tscn"], 8, False),
        ("Audit: UI / input", ["tests/audit_a4.tscn"], 18, False),
    ]
    return table


def select_steps(fast=False, only=""):
    """Without --only, run the default set. With --only, the filter may reach the
    opt-in extras, so incident work never loses access to them."""
    pattern = re.compile(only, re.IGNORECASE)
    return [step for step in steps(fast)
            if pattern.search(" ".join([step[0], *step[1]])) and (only or step[3])]


# One table of display captures: alias -> (scene, seconds). Scripted waits are
# part of the limit; ui-product runs the same 60s probe the runner owns.
CAPTURES = {
    "title": ("title_capture", 8), "scene": ("capture_scene", 20),
    "impact": ("impact_capture", 10), "world": ("world_map_probe", 8), "bloom": ("bloom_probe", 8),
    "meta": ("meta_capture", 24), "jump": ("jump_capture", 8), "hud": ("hud_readability_probe", 8), "vine": ("biome_play_probe", 30), "saves": ("save_slots_probe", 16), "l3": ("l3_build_probe", 30), "l4": ("l4_passage_probe", 30), "l5": ("l5_route_probe", 40), "l6": ("l6_input_play", 900), "terminal": ("terminal_failure_probe", 8), "reward": ("reward_probe", 8), "burstside": ("burst_side_probe", 10),
    "ui-product": ("ui_product_probe", 60),
}


def isolated_env(folder):
    """Both user:// fixtures live in the throwaway directory. A developer shell
    locale never leaks into the first-frame zh_TW default under test."""
    env = dict(os.environ, ASHFALL_PROFILE_PATH=str(Path(folder) / "profile.json"),
               ASHFALL_SETTINGS_PATH=str(Path(folder) / "settings.cfg"),
               ASHFALL_TEST_PYTHON=sys.executable)
    env.pop("ASHFALL_LOCALE", None)
    env.pop("ASHFALL_EXPECT_FORMAL_PREFERENCES", None)
    env.pop("ASHFALL_EXPECT_RELATIVE_SETTINGS", None)
    env.pop("ASHFALL_EXPECT_CORRUPT_SIZE", None)
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".tools/Godot_v4.7.2-stable_win64.exe")
    parser.add_argument("--only", default="", help="case-insensitive regex over names and test paths; also reaches opt-in extras")
    parser.add_argument("--fast", action="store_true", help="four generation seeds instead of 32; the default set is already short")
    parser.add_argument("--turbo", action="store_true", help="fixed-fps smoke only, not acceptance")
    parser.add_argument("--capture", choices=tuple(CAPTURES), help="run a known display capture with an isolated save")
    parser.add_argument("--list", action="store_true", help="print the plan without launching anything")
    options = parser.parse_args()
    if options.capture and (options.only or options.fast or options.turbo):
        parser.error("--capture cannot be combined with --only, --fast or --turbo")
    try:
        selected = select_steps(options.fast, options.only)
    except re.error as error:
        parser.error(f"invalid filter: {error}")
    if options.capture:
        scene, limit = CAPTURES[options.capture]  # ~16s scripted waits + GL boot/captures
        selected = [(f"Display capture: {options.capture}", [f"tests/{scene}.tscn"], limit, False)]
    if not selected:
        print(f"NO CHECKS RAN: filter {options.only!r} matched no enabled tests.")
        return 1
    engine = options.godot.resolve()
    if engine.suffix.lower() in (".ps1", ".bat", ".cmd", ".py"):
        parser.error("--godot must be a native Godot executable, not a script")
    if not options.list and not engine.is_file():
        parser.error(f"Godot executable not found: {engine}")
    if options.turbo:
        print("SMOKE ONLY: fixed-fps 120; not an acceptance gate.")
    totals = []
    with tempfile.TemporaryDirectory(prefix="ashfall-check-") as folder:
        for index, (name, arguments, limit, _) in enumerate(selected):
            ## Each selected step owns its preferences file. A probe that proves
            ## first-use zh_TW must never see preferences persisted by an
            ## earlier probe in the same combined --only selection.
            step_folder = Path(folder) / f"step-{index:02d}"
            step_folder.mkdir()
            env = isolated_env(step_folder)
            command = [str(engine), "--path", str(ROOT)]
            if not options.capture:
                command += ["--headless"]
            if "--editor" not in arguments:
                command += ["--verbose"]
            if options.turbo:
                command += ["--fixed-fps", "120"]
            command += arguments
            print(f"\n== {name} (limit {limit}s) ==", flush=True)
            if options.list:
                print(subprocess.list2cmdline(command))
                continue
            expected_errors = {"ERROR: Main: required SkillTree is unavailable"} if arguments == ["tests/audit_a4.tscn"] else set()
            code, seconds = run_command(command, limit, env, expected_errors)
            totals.append((name, seconds))
            if code:
                print(f"FAILED: {name} (exit {code}; {seconds:.2f}s)")
                return code if 0 < code < 256 else 1
    if options.list:
        return 0
    print("\n== Timing ==")
    for name, seconds in sorted(totals, key=lambda row: row[1], reverse=True):
        print(f"  {seconds:6.2f}s  {name}")
    print(f"  {sum(seconds for _, seconds in totals):6.2f}s  TOTAL")
    print("\nALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print(f"FAILED: {error}", file=sys.stderr)
        sys.exit(1)
