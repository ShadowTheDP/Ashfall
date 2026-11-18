"""Static authored spatial contract, independent of Godot/Player acceptance.

Run: python tests/generation_schema_probe.py
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return json.loads((ROOT / "data" / (name + ".json")).read_text(encoding="utf-8"))


def intersects(a, b):
    return a[0] < b[0] + b[2] - 1e-6 and b[0] < a[0] + a[2] - 1e-6 and a[1] < b[1] + b[3] - 1e-6 and b[1] < a[1] + a[3] - 1e-6


def embeddings(profile, variant, spatial, biomes, modules):
    """Enumerate every compatible authored candidate, without mimicking Godot RNG."""
    cfg = biomes["biomes"][profile]
    known = {n["id"] for n in cfg["nodes"]}
    assert variant["nodes"].keys() <= known
    rooms = {}
    all_modules = modules["modules"] | spatial["modules"]
    for n in cfg["nodes"]:
        patch = variant["nodes"].get(n["id"], {})
        assert patch.keys() <= {"grid", "templates"}
        grid = patch.get("grid", n["grid"])
        origin = [grid[0] * biomes["grid"][0], 150 + grid[1] * biomes["grid"][1]]
        pool = patch.get("templates", [k for k, v in modules["modules"].items() if n["role"] in v["roles"] and cfg["tag"] in v["biome_tags"] and len(v["spawns"]) >= n.get("budget", 0)])
        assert pool, (profile, n["id"], "empty pool")
        choices = []
        for name in pool:
            m = all_modules[name]
            assert n["role"] in m["roles"] and cfg["tag"] in m["biome_tags"]
            w, h = m["size"]
            assert w > 0 and h > 0
            assert len(m["spawns"]) >= n.get("budget", 0)
            if n.get("cache", 0): assert m["loot"]
            for rect in m["solids"] + m["oneways"] + [gate["rect"] for gate in m.get("gates", [])]:
                x, y, rw, rh = rect
                assert rw > 0 and rh > 0 and x >= 0 and y >= -h and x + rw <= w + 1e-6 and y + rh <= 32 + 1e-6, (name, "collision footprint", rect)
            choices.append((m, [origin[0], origin[1] - h, w, h]))
        rooms[n["id"]] = (origin, choices)
    for name, (origin, choices) in rooms.items():
        for other, (_, other_choices) in rooms.items():
            if name >= other: continue
            for _, a in choices:
                for _, b in other_choices:
                    assert not intersects(a, b), (profile, variant["id"], name, other, "overlap")
    for edge in cfg["edges"]:
        a, ac = rooms[edge["from"]]
        b, bc = rooms[edge["to"]]
        for am, _ in ac:
            for bm, _ in bc:
                source = am["sockets"][edge["from_socket"]]
                target = bm["sockets"][edge["to_socket"]]
                assert source["normal"] in [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1]]
                if edge["mode"] == "phase": continue
                assert all(abs(a[i] + source["point"][i] - b[i] - target["point"][i]) < .1 for i in range(2)), (profile, variant["id"], edge, "socket position")
                assert source["normal"] == [-v for v in target["normal"]], (profile, edge, "socket direction")
    return tuple((k, tuple(v[0]), tuple(tuple(bounds) for _, bounds in v[1])) for k, v in rooms.items())


def run():
    biomes, modules, spatial = read("biomes"), read("room_modules"), read("generation_spatial_v2")
    assert spatial["algorithm_revision"] == "authored_spatial_v2"
    total = 0
    for profile, data in spatial["profiles"].items():
        assert not biomes["biomes"][profile].get("boss")
        assert 2 <= len(data["variants"]) <= 4
        signatures = [embeddings(profile, v, spatial, biomes, modules) for v in data["variants"]]
        assert len(set(signatures)) == len(signatures), (profile, "fake diversity")
        assert {seed % len(signatures) for seed in range(1, 33)} == set(range(len(signatures)))
        total += len(signatures)
    # Counterexamples exercise boundary-sharing, overlap, bad sockets and footprint escape.
    assert not intersects([0, 0, 640, 276], [640, 0, 640, 276])
    assert intersects([0, 0, 640, 276], [639, 0, 640, 276])
    for defect in ["overlap", "socket", "direction", "collision", "missing", "empty"]:
        bad = copy.deepcopy(spatial)
        v = bad["profiles"]["ash_gate"]["variants"][1]
        target = v["nodes"]["lower"]["templates"][0]
        if defect == "overlap": v["nodes"]["lower"]["grid"] = [1, 0]
        if defect == "socket": bad["modules"][target]["sockets"]["east"]["point"][0] += 32
        if defect == "direction": bad["modules"][target]["sockets"]["east"]["normal"] = [-1, 0]
        if defect == "collision": bad["modules"][target]["solids"][0][2] += 32
        if defect == "missing": del bad["modules"][target]["sockets"]["east"]
        if defect == "empty": v["nodes"]["lower"]["templates"] = []
        try:
            embeddings("ash_gate", v, bad, biomes, modules)
        except (AssertionError, KeyError):
            pass
        else:
            raise AssertionError("counterexample accepted: " + defect)
    fixture = ROOT / "tests/fixtures/generation_baseline_layouts_v1.json"
    frozen = json.loads(fixture.read_text(encoding="utf-8"))
    assert len(frozen["records"]) == 20
    legacy_path = ROOT / "tests/fixtures/generation_legacy_v1.json"
    assert hashlib.sha256(legacy_path.read_bytes()).hexdigest() == "f36efd0dfe7f85d955fb16dfd5653995ed405e462408a31c93e3881f2ca41397"
    legacy = json.loads(legacy_path.read_text(encoding="utf-8"))
    assert "generator_revision" not in legacy["biome_entry"] and "generator_revision" not in legacy["passage"]
    for path, digest in legacy["source_hashes"].items():
        if path.startswith("data/"):
            assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    generator = (ROOT / "scripts/world/biome_gen.gd").read_text(encoding="utf-8")
    old_body = generator[generator.index("static func _generate_legacy("):].replace("static func _generate_legacy(", "static func generate(", 1)
    assert hashlib.sha256(old_body.encode()).hexdigest() == "c27843895549d94d029748f16dfaa2d56a2de8e629b7332de2a9b33b34ded1e8"
    print(f"GENERATION SCHEMA OK: {len(spatial['profiles'])} profiles, {total} authored embeddings, 6 rejected counterexamples; no Player/Godot claim")


if __name__ == "__main__":
    run()
