"""Check CLI path isolation with direct native Godot calls, never a shell."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / ".tools/Godot_v4.7.2-stable_win64.exe"


def main():
    name = re.search(r'^config/name="([^"]+)"', (ROOT / "project.godot").read_text(encoding="utf-8"), re.M)[1]
    user = Path(os.environ["APPDATA"]) / "Godot/app_userdata" / name
    live = user / "ashfall_profile.json"
    slots = [live] + [live.with_name(live.name + f".slot{slot}") for slot in (2, 3)]
    settings = user / "ashfall_settings.cfg"
    watched = [*slots, settings]
    digest = lambda: {path.name: hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else "absent" for path in watched}
    before = digest()
    checks = 0
    scene = "tests/profile_safety_probe.tscn"
    variants = [scene, "res://" + scene, ".\\" + scene.replace("/", "\\"), str(ROOT / scene)]
    try:
        with tempfile.TemporaryDirectory(prefix="ashfall-path-settings-") as settings_folder:
            protected_aliases = ["user://" + path.name for path in slots] + [str(path) for path in slots]
            for alias in [*variants, *protected_aliases]:
                protected = alias not in variants
                env = dict(os.environ)
                env.pop("ASHFALL_PROFILE_PATH", None)
                env.pop("ASHFALL_SETTINGS_PATH", None)
                env.pop("ASHFALL_EXPECT_FORMAL_PREFERENCES", None)
                env.pop("ASHFALL_EXPECT_RELATIVE_SETTINGS", None)
                if protected:
                    # A protected progress alias must not let its directory
                    # decide the preferences path either.
                    env["ASHFALL_PROFILE_PATH"] = alias
                    env["ASHFALL_SETTINGS_PATH"] = str(Path(settings_folder) / "settings.cfg")
                result = subprocess.run([str(ENGINE), "--headless", "--path", str(ROOT), "--quit-after", "120",
                                         scene if protected else alias], cwd=ROOT, env=env,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, encoding="utf-8", errors="replace", timeout=5)
                if protected:
                    assert result.returncode != 0 and "test refused to access the live save" in result.stdout, result.stdout
                    checks += 2
                else:
                    assert result.returncode == 0, result.stdout
                    match = re.search(r"ISOLATED PROFILE: user://(ashfall_test_(\d+)\.json)", result.stdout)
                    assert match, result.stdout
                    assert "PROFILE SAFETY OK: 12 checks, 0 failures" in result.stdout, result.stdout
                    # Only the fixtures this run owns are removed; automatic
                    # PID isolation owns both the progress and settings files.
                    (user / match[1]).unlink(missing_ok=True)
                    isolated_settings = user / f"ashfall_test_{match[2]}_settings.cfg"
                    assert not isolated_settings.exists(), "automatic isolation never creates a missing settings file"
                    isolated_settings.unlink(missing_ok=True)
                    checks += 4

        # A direct test scene with the formal preferences path is refused, but
        # the independently isolated progress writer must still save.
        with tempfile.TemporaryDirectory(prefix="ashfall-formal-settings-") as profile_folder:
            env = dict(os.environ)
            env["ASHFALL_PROFILE_PATH"] = str(Path(profile_folder) / "profile.json")
            env["ASHFALL_SETTINGS_PATH"] = "user://ashfall_settings.cfg"
            env["ASHFALL_EXPECT_FORMAL_PREFERENCES"] = "1"
            env.pop("ASHFALL_EXPECT_RELATIVE_SETTINGS", None)
            env.pop("ASHFALL_EXPECT_CORRUPT_SIZE", None)
            env.pop("ASHFALL_LOCALE", None)
            result = subprocess.run([str(ENGINE), "--headless", "--path", str(ROOT), "--quit-after", "120", scene],
                                    cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, encoding="utf-8", errors="replace", timeout=5)
            assert result.returncode == 0, result.stdout
            assert "ERROR: Profile: test refused to access the live preferences" in result.stdout, result.stdout
            assert "FORMAL PREFERENCES GUARD OK: progress writer usable" in result.stdout, result.stdout
            assert (Path(profile_folder) / "profile.json").exists(), "the isolated progress writer saved"
            checks += 3

        # A bare relative ASHFALL_PROFILE_PATH has an empty get_base_dir().
        # Preferences must follow the resolved progress file, not fall through
        # to the live player file. The fixture directory is bounded and removed.
        relative_dir = ROOT / f"ashfall_relative_{os.getpid()}"
        relative_profile = relative_dir / "profile.json"
        adjacent_settings = relative_dir / "settings.cfg"
        assert not relative_dir.exists(), "relative fixture directory is free"
        relative_dir.mkdir()
        try:
            env = dict(os.environ)
            env["ASHFALL_PROFILE_PATH"] = str(relative_profile.relative_to(ROOT)).replace("\\", "/")
            env.pop("ASHFALL_SETTINGS_PATH", None)
            env.pop("ASHFALL_EXPECT_FORMAL_PREFERENCES", None)
            env.pop("ASHFALL_EXPECT_CORRUPT_SIZE", None)
            env["ASHFALL_EXPECT_RELATIVE_SETTINGS"] = "1"
            env.pop("ASHFALL_LOCALE", None)
            result = subprocess.run([str(ENGINE), "--headless", "--path", str(ROOT), "--quit-after", "120", scene],
                                    cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, encoding="utf-8", errors="replace", timeout=5)
            assert result.returncode == 0, result.stdout
            assert "RELATIVE SETTINGS OK: adjacent preferences" in result.stdout, result.stdout
            assert relative_profile.exists(), "the relative progress path wrote beside its resolved file"
            assert adjacent_settings.exists(), "the relative progress path kept settings adjacent"
            checks += 4
        finally:
            if relative_dir.exists():
                for leftover in relative_dir.iterdir():
                    leftover.unlink(missing_ok=True)
                relative_dir.rmdir()
    finally:
        assert digest() == before, "Direct tests changed live progress or preferences"
    checks += 1
    print(f"PROFILE PATHS OK: {checks} checks; live SHA-256 unchanged ({before})")


if __name__ == "__main__":
    main()
