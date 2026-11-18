"""Regression checks for scheduling, diagnostics, deadlines and owned processes."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("ashfall_check", Path(__file__).resolve().parents[1] / "tools/check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class RunnerTests(unittest.TestCase):
    def test_filters(self):
        for name in ["Import", "run_tests", "collector_display_probe", "profile_migration_probe", "Audit: UI"]:
            self.assertEqual(len(check.select_steps(only=name)), 1, name)
        self.assertEqual(check.select_steps(only="no-such-test"), [])
        self.assertFalse(any("Import" in step[0] for step in check.select_steps(only="probe")))

    def test_defaults_are_concise_and_extras_stay_reachable(self):
        default = check.select_steps()
        self.assertLessEqual(len(default), 13)
        self.assertTrue(all(step[3] for step in default))
        # Opt-in coverage must not disappear, only move behind the filter.
        self.assertFalse(any("l6_input_play" in " ".join(step[1]) for step in default))
        self.assertEqual(len(check.select_steps(only="l6_input_play")), 2)

    def test_ui_product_is_opt_in_and_capture_is_scoped(self):
        matches = [step for step in check.steps() if "tests/ui_product_probe.tscn" in step[1]]
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0][2], 60)
        self.assertFalse(matches[0][3])
        self.assertEqual(check.CAPTURES["ui-product"], ("ui_product_probe", 60))
        self.assertEqual(len(check.select_steps(only="ui_product_probe")), 1)
        self.assertFalse(any("ui_product_probe" in " ".join(step[1]) for step in check.select_steps()))
        self.assertTrue((check.ROOT / "tests/ui_product_probe.gd").is_file())

    def test_settings_probe_is_opt_in_and_scoped(self):
        matches = [step for step in check.steps() if "tests/settings_probe.tscn" in step[1]]
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0][2], 30)
        self.assertFalse(matches[0][3])
        self.assertEqual(len(check.select_steps(only="settings_probe")), 1)
        self.assertFalse(any("settings_probe" in " ".join(step[1]) for step in check.select_steps()))
        self.assertTrue((check.ROOT / "tests/settings_probe.gd").is_file())
        self.assertTrue((check.ROOT / "tests/settings_probe.tscn").is_file())
        self.assertEqual(check.CAPTURES["ui-product"], ("ui_product_probe", 60))

    def test_capture_aliases_resolve_to_existing_scenes(self):
        for alias, (scene, limit) in check.CAPTURES.items():
            self.assertGreater(limit, 0, alias)
            self.assertTrue((check.ROOT / f"tests/{scene}.tscn").is_file(), alias)
        self.assertEqual(check.CAPTURES["ui-product"], ("ui_product_probe", 60))

    def test_isolated_env_keeps_user_paths_in_temp_and_locale_clean(self):
        with tempfile.TemporaryDirectory(prefix="ashfall-runner-env-") as folder:
            with mock.patch.dict(os.environ, {"ASHFALL_LOCALE": "en"}):
                env = check.isolated_env(folder)
            self.assertEqual(Path(env["ASHFALL_PROFILE_PATH"]).parent, Path(folder))
            self.assertEqual(Path(env["ASHFALL_SETTINGS_PATH"]).parent, Path(folder))
            self.assertNotEqual(env["ASHFALL_PROFILE_PATH"], env["ASHFALL_SETTINGS_PATH"])
            self.assertNotIn("profile.json", env["ASHFALL_SETTINGS_PATH"])
            self.assertNotIn("ASHFALL_LOCALE", env)
            self.assertEqual(env["ASHFALL_TEST_PYTHON"], sys.executable)

    def test_retired_and_missing_paths_are_absent(self):
        retired = {"audit_a3", "audit_v1", "audit_v2", "audit_v3", "gen_stats",
                   "boss_probe", "climb_probe", "terrain_regression_probe", "map_capture"}
        registered = {argument for step in check.steps() for argument in step[1]}
        self.assertFalse({f"tests/{name}.tscn" for name in retired} & registered)
        for name in sorted(retired):
            # Full path so a live probe such as l5_boss_probe cannot match by suffix.
            self.assertEqual(check.select_steps(only=f"tests/{name}.tscn"), [], name)
        for step in check.steps():
            joined = " ".join(step[1])
            self.assertNotIn("tests/archive", joined, step[0])
            for argument in step[1]:
                if argument.startswith("res://tests/"):
                    argument = argument.replace("res://", "")
                if argument.startswith("tests/"):
                    self.assertTrue((check.ROOT / argument).is_file(), argument)

    def test_list_does_not_require_godot(self):
        with tempfile.TemporaryDirectory(prefix="ashfall-runner-list-") as folder:
            missing = Path(folder) / "missing-godot.exe"
            result = subprocess.run(
                [sys.executable, str(check.ROOT / "tools/check.py"), "--godot", str(missing), "--fast", "--list"],
                cwd=check.ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=8)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Import assets / compile scripts", result.stdout)
        self.assertNotIn("ALL CHECKS PASSED", result.stdout)

    def test_seed_scheduling(self):
        for fast, seeds in [(True, 4), (False, 32)]:
            selected = check.select_steps(fast)
            generation = [step for step in selected if "biome_gen_probe.gd" in " ".join(step[1])]
            self.assertEqual(len(generation), 1)
            self.assertIn(f"--seeds={seeds}", generation[0][1])
            self.assertEqual(selected[0][0], "Import assets / compile scripts")
            self.assertTrue(all(step[3] for step in selected))

    def test_error_lines_are_specific(self):
        for line in ["SCRIPT ERROR: fixture", "Parse Error: fixture", "Compile Error: fixture", "ERROR: Compile Error: fixture", "ERROR: Node not found: Missing", "ERROR: 1 resources still in use at exit", "AUDIT A3 FAILED (1)", "PROFILE FAIL: fixture"]:
            self.assertRegex(line, check.ERROR_LINE)
        for line in ["TESTS OK (118 checks)", "Example: SCRIPT ERROR is a label", "WARNING: ObjectDB instances leaked at exit", "WARNING: fixture"]:
            self.assertNotRegex(line, check.ERROR_LINE)
        self.assertRegex("ERROR: 1 resources still in use at exit", check.ERROR_LINE)

    def test_only_identified_audio_shutdown_resources_are_allowed(self):
        known = """Leaked instance: AudioStreamWAV:1 - Reference count: 1
Leaked instance: AudioStreamPlaybackWAV:2 - Reference count: 1
Resource still in use: res://assets/audio/music_loop.wav (AudioStreamWAV)
ERROR: 1 resources still in use at exit."""
        self.assertTrue(check.known_audio_shutdown(known))
        for unknown in [
            known.replace("res://assets/audio/music_loop.wav", "res://scenes/main.tscn"),
            known.replace("AudioStreamPlaybackWAV", "Texture2D"),
            known.replace("ERROR: 1 resources", "ERROR: 2 resources"),
            "ERROR: 1 resources still in use at exit.",
            known + "\nERROR: Node not found: Missing",
            known + "\n   ERROR: Node not found: Missing",
        ]:
            self.assertFalse(check.known_audio_shutdown(unknown))

    def run_fixture(self, source, limit=2, expected_errors=()):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code, elapsed = check.run_command([sys.executable, "-c", source], limit,
                                              dict(os.environ), expected_errors)
        return code, elapsed, output.getvalue()

    def test_normal_completion_and_nonzero(self):
        code, _, text = self.run_fixture("print('DONE', flush=True)")
        self.assertEqual(code, 0)
        self.assertIn("DONE", text)
        self.assertEqual(self.run_fixture("raise SystemExit(7)")[0], 7)

    def test_zero_exit_with_error_is_rejected(self):
        # Both script and scene checks use this single output/exit decision.
        for label in ["SCRIPT ERROR: fixture", "Parse Error: fixture", "Compile Error: fixture", "ERROR: Node not found: Missing", "   ERROR: Node not found: Missing", "ERROR: Main: required SkillTree is unavailable"]:
            code, _, text = self.run_fixture(f"print({label!r}, flush=True)")
            self.assertNotEqual(code, 0)
            self.assertIn("script/test error output", text)

    def test_zero_exit_with_identified_audio_shutdown_is_reported(self):
        source = "\n".join([
            "print('Leaked instance: AudioStreamWAV:1 - Reference count: 1', flush=True)",
            "print('Leaked instance: AudioStreamPlaybackWAV:2 - Reference count: 1', flush=True)",
            "print('Resource still in use: res://assets/audio/music_loop.wav (AudioStreamWAV)', flush=True)",
            "print('ERROR: 1 resources still in use at exit.', flush=True)",
        ])
        code, _, text = self.run_fixture(source)
        self.assertEqual(code, 0)
        self.assertIn("KNOWN LIMITATION", text)
        for prefix in ["", "   "]:
            code, _, text = self.run_fixture(f"print({(prefix + 'ERROR: 1 resources still in use at exit.')!r}, flush=True)")
            self.assertNotEqual(code, 0, text)
            self.assertIn("unrecognized error output", text)

    def test_expected_error_is_scoped_and_other_errors_still_fail(self):
        expected = "ERROR: Main: required SkillTree is unavailable"
        code, _, text = self.run_fixture(f"print({expected!r}, flush=True)", expected_errors={expected})
        self.assertEqual(code, 0)
        self.assertIn("EXPECTED TEST DIAGNOSTIC", text)
        source = "print(%r, flush=True); print('ERROR: Node not found: Missing', flush=True)" % expected
        code, _, text = self.run_fixture(source, expected_errors={expected})
        self.assertNotEqual(code, 0)
        self.assertIn("ERROR: Node not found: Missing", text)

    def test_warning_output_is_allowed(self):
        code, _, text = self.run_fixture("print('WARNING: fixture', flush=True)")
        self.assertEqual(code, 0)
        self.assertIn("WARNING: fixture", text)

    def test_real_godot_zero_exit_missing_node_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="ashfall-runner-profile-") as folder:
            command = [str(check.ROOT / ".tools/Godot_v4.7.2-stable_win64.exe"),
                       "--path", str(check.ROOT), "--headless", "--script",
                       "res://tests/fixtures/runner_missing_node.gd"]
            env = dict(os.environ, ASHFALL_PROFILE_PATH=str(Path(folder) / "profile.json"))
            raw = subprocess.run(command, cwd=check.ROOT, env=env, capture_output=True,
                                 text=True, encoding="utf-8", errors="replace", timeout=8)
            self.assertEqual(raw.returncode, 0, raw.stdout + raw.stderr)
            self.assertIn("ERROR: Node not found:", raw.stdout + raw.stderr)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code, _ = check.run_command(command, 8, env)
            self.assertNotEqual(code, 0, output.getvalue())
            self.assertIn("ERROR: Node not found:", output.getvalue())

    def test_early_error_does_not_wait_for_hang(self):
        code, elapsed, _ = self.run_fixture("import time; print('SCRIPT ERROR: fixture', flush=True); time.sleep(5)")
        self.assertNotEqual(code, 0)
        self.assertLess(elapsed, 1.5)

    def test_silent_timeout(self):
        code, elapsed, text = self.run_fixture("import time; time.sleep(5)", 0.3)
        self.assertNotEqual(code, 0)
        self.assertIn("timeout after", text)
        self.assertLess(elapsed, 1.5)

    @unittest.skipUnless(os.name == "nt", "Windows job ownership")
    def test_only_owned_descendants_are_stopped(self):
        kernel = check.ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [check.wintypes.DWORD, check.wintypes.BOOL, check.wintypes.DWORD]
        kernel.OpenProcess.restype = check.wintypes.HANDLE
        kernel.CloseHandle.argtypes = [check.wintypes.HANDLE]
        kernel.GetExitCodeProcess.argtypes = [check.wintypes.HANDLE, check.ctypes.POINTER(check.wintypes.DWORD)]
        sentinel = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(5)"])
        try:
            with tempfile.TemporaryDirectory(prefix="ashfall-runner-fixture-") as folder:
                pid_file = Path(folder) / "child.pid"
                source = ("import subprocess,sys,time,pathlib; "
                          "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(5)']); "
                          f"pathlib.Path({str(pid_file)!r}).write_text(str(child.pid)); time.sleep(5)")
                self.assertNotEqual(self.run_fixture(source, 0.8)[0], 0)
                self.assertTrue(pid_file.exists(), "fixture must spawn its child before the deadline")
                handle = kernel.OpenProcess(0x1000, False, int(pid_file.read_text()))
                if handle:
                    try:
                        status = check.wintypes.DWORD()
                        self.assertTrue(kernel.GetExitCodeProcess(handle, check.ctypes.byref(status)))
                        self.assertNotEqual(status.value, 259, "owned child still active")
                    finally:
                        kernel.CloseHandle(handle)
                self.assertIsNone(sentinel.poll(), "an unrelated process was terminated")
        finally:
            if sentinel.poll() is None:
                sentinel.terminate()
            sentinel.wait(timeout=2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
