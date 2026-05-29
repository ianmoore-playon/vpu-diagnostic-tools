"""Unit tests for Pulse's pure-Python diagnostic logic.

Runs with the standard library only — no pytest, no extra deps — so it
works on a locked-down VPU or any checkout:

    cd Pulse.Web && .venv/bin/python -m unittest discover -s tests -v
    # or:  python3 -m unittest discover -s tests

These cover the finding/compatibility/parsing logic that is easy to break
silently when multiple sessions edit main.py and powershell.py. They do NOT
exercise PowerShell or the network — pure functions only.
"""

import os
import sys
import unittest

# Make `app/` importable (mirrors how main.py puts itself on sys.path).
_APP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
if _APP_DIR not in sys.path:
    sys.path.insert(0, _APP_DIR)

import main  # noqa: E402
import powershell  # noqa: E402


# ── Version comparison (GPU compat caps) ─────────────────────
class TestVersionCompare(unittest.TestCase):
    def test_wildcard_cap_allows_any_patch(self):
        self.assertFalse(main._version_exceeds_cap("5.2.0", "5.2.x"))
        self.assertFalse(main._version_exceeds_cap("5.2.99", "5.2.x"))

    def test_wildcard_cap_blocks_higher_minor_or_major(self):
        self.assertTrue(main._version_exceeds_cap("5.3.0", "5.2.x"))
        self.assertTrue(main._version_exceeds_cap("6.0.0", "5.2.x"))
        self.assertTrue(main._version_exceeds_cap("5.13.6", "5.2.x"))

    def test_wildcard_cap_allows_lower(self):
        self.assertFalse(main._version_exceeds_cap("5.1.99", "5.2.x"))
        self.assertFalse(main._version_exceeds_cap("4.99.0", "5.2.x"))

    def test_exact_cap_boundary(self):
        self.assertFalse(main._version_exceeds_cap("2.66.17", "2.66.17"))  # equal = OK
        self.assertFalse(main._version_exceeds_cap("2.66.16", "2.66.17"))
        self.assertTrue(main._version_exceeds_cap("2.66.18", "2.66.17"))
        self.assertTrue(main._version_exceeds_cap("2.67.0", "2.66.17"))

    def test_empty_inputs_never_exceed(self):
        self.assertFalse(main._version_exceeds_cap("", "5.2.x"))
        self.assertFalse(main._version_exceeds_cap("5.2.0", ""))

    def test_suffix_tolerance(self):
        # Beta/suffix tags shouldn't crash the parser.
        self.assertFalse(main._version_exceeds_cap("5.2.0-beta", "5.2.x"))


# ── US timezone allowlist ────────────────────────────────────
class TestUsTimezone(unittest.TestCase):
    def test_us_standard_names_accepted(self):
        for tz in ("Eastern Standard Time", "Central Standard Time",
                   "Mountain Standard Time", "Pacific Standard Time",
                   "US Mountain Standard Time", "US Eastern Standard Time",
                   "Alaskan Standard Time", "Aleutian Standard Time",
                   "Hawaiian Standard Time"):
            self.assertTrue(main._is_us_timezone(tz, ""), tz)

    def test_non_us_rejected(self):
        for tz in ("Israel Standard Time", "GMT Standard Time", "UTC",
                   "Tokyo Standard Time", "Central Europe Standard Time",
                   "Central America Standard Time", "Pacific Standard Time (Mexico)",
                   "Atlantic Standard Time"):
            self.assertFalse(main._is_us_timezone(tz, ""), tz)

    def test_caption_fallback(self):
        self.assertTrue(main._is_us_timezone("", "(UTC-05:00) Eastern Time (US & Canada)"))
        self.assertTrue(main._is_us_timezone("", "(UTC-09:00) Alaska"))
        self.assertTrue(main._is_us_timezone("", "(UTC-07:00) Arizona"))
        self.assertFalse(main._is_us_timezone("", "(UTC+02:00) Jerusalem"))

    def test_empty_is_not_us(self):
        self.assertFalse(main._is_us_timezone("", ""))


# ── GPU compatibility matrix ─────────────────────────────────
def _identity(version, os_caption="Microsoft Windows 10 IoT Enterprise LTSC", build="19044"):
    return {
        "pixellot": {"version": version},
        "operatingSystem": {"caption": os_caption, "buildNumber": build},
    }


def _gpu(arch):
    return {"primaryArchitecture": arch}


class TestPixellotCompat(unittest.TestCase):
    def test_pascal_caps_at_52x(self):
        r = main._check_pixellot_compatibility(_identity("5.13.6"), _gpu("Pascal"))
        self.assertEqual(r["status"], "over")
        self.assertEqual(r["maxVersion"], "5.2.x")

    def test_pascal_within_cap_ok(self):
        r = main._check_pixellot_compatibility(_identity("5.2.4"), _gpu("Pascal"))
        self.assertEqual(r["status"], "ok")

    def test_turing_unlimited(self):
        r = main._check_pixellot_compatibility(_identity("5.13.6"), _gpu("Turing"))
        self.assertEqual(r["status"], "ok")
        self.assertIsNone(r["maxVersion"])

    def test_maxwell_caps_at_26617(self):
        r = main._check_pixellot_compatibility(_identity("5.13.6"), _gpu("Maxwell"))
        self.assertEqual(r["status"], "over")
        self.assertEqual(r["maxVersion"], "2.66.17")

    def test_volta_is_anomaly(self):
        r = main._check_pixellot_compatibility(_identity("5.13.6"), _gpu("Volta"))
        self.assertEqual(r["status"], "anomaly")

    def test_win8_caps_regardless_of_gpu(self):
        ident = _identity("5.13.6", os_caption="Microsoft Windows 8.1 Pro", build="9600")
        r = main._check_pixellot_compatibility(ident, _gpu("Turing"))
        self.assertEqual(r["status"], "over")
        self.assertEqual(r["maxVersion"], "2.66.17")

    def test_no_gpu(self):
        r = main._check_pixellot_compatibility(_identity("5.13.6"), {"primaryArchitecture": "None"})
        self.assertEqual(r["status"], "no-gpu")

    def test_missing_pixellot_version_skips(self):
        r = main._check_pixellot_compatibility(_identity(None), _gpu("Pascal"))
        self.assertEqual(r["status"], "skip")


# ── OS lifecycle ─────────────────────────────────────────────
class TestOsLifecycle(unittest.TestCase):
    def test_known_builds_have_eos(self):
        for build in ("17763", "19044"):
            lc = main._os_lifecycle(build)
            self.assertIsNotNone(lc, build)
            self.assertIn("eosDate", lc)
            self.assertIn("daysToEos", lc)

    def test_unknown_build_returns_none(self):
        self.assertIsNone(main._os_lifecycle("19045"))  # 22H2 — not an LTSC we track
        self.assertIsNone(main._os_lifecycle(None))


# ── Total RAM resolution ─────────────────────────────────────
class TestTotalRam(unittest.TestCase):
    def test_prefers_dimm_sum(self):
        hw = {"memory": [{"capacityGB": 16}, {"capacityGB": 16}]}
        self.assertEqual(main._total_ram_gb(hw, None), 32.0)

    def test_falls_back_to_performance_total_mb(self):
        self.assertEqual(main._total_ram_gb({"memory": []}, {"memory": {"totalMB": 32768}}), 32.0)

    def test_zero_when_no_source(self):
        self.assertEqual(main._total_ram_gb(None, None), 0.0)


# ── Concerning-software detection ────────────────────────────
class TestConcerningSoftware(unittest.TestCase):
    def _sw(self, *names):
        return {"software": [{"displayName": n, "displayVersion": "1.0"} for n in names]}

    def test_security_av_detected(self):
        out = main._detect_concerning_software(self._sw("CrowdStrike Falcon Sensor"))
        self.assertEqual(len(out["security"]), 1)

    def test_clean_box_no_hits(self):
        out = main._detect_concerning_software(self._sw("Google Chrome", "7-Zip 23.01 (x64)"))
        self.assertEqual(sum(len(v) for v in out.values()), 0)

    def test_categories_route_correctly(self):
        out = main._detect_concerning_software(
            self._sw("qBittorrent", "CCleaner", "TeamViewer", "Steam"))
        self.assertEqual(len(out["torrent"]), 1)
        self.assertEqual(len(out["system_cleaner"]), 1)
        self.assertEqual(len(out["alt_remote"]), 1)
        self.assertEqual(len(out["game_platform"]), 1)

    def test_error_payload_is_safe(self):
        self.assertEqual(
            sum(len(v) for v in main._detect_concerning_software({"error": True}).values()), 0)


# ── _compute_findings integration (the high-churn function) ──
class TestComputeFindings(unittest.TestCase):
    def _titles(self, **kwargs):
        return {f["title"] for f in main._compute_findings(**kwargs)}

    def test_clean_system_no_findings(self):
        # Healthy: US tz, 32GB, Turing GPU running a capped version, no bad SW.
        # Build 17763 (LTSC 2019) — EOS 2029, far enough out that the OS
        # lifecycle warning does not fire. (19044/21H2 would, by design.)
        ident = _identity("5.2.0", build="17763")
        ident["timezoneId"] = "Eastern Standard Time"
        ident["uptime"] = {"totalSeconds": 3600}
        titles = self._titles(
            identity=ident,
            performance={"cpu": {"usagePercent": 20}, "memory": {"usedPercent": 40},
                         "disk": {"usedPercent": 50}},
            services={"services": []},
            nics={"ports": []},
            hardware={"memory": [{"capacityGB": 16}, {"capacityGB": 16}],
                      "gpus": [{"vendor": "NVIDIA", "isDedicated": True}]},
            installed_sw={"software": [{"displayName": "Google Chrome"}]},
            gpu_info=_gpu("Turing"),
        )
        self.assertEqual(titles, set())

    def test_low_ram_flagged(self):
        titles = self._titles(
            identity=_identity("5.2.0"),
            performance={}, services={}, nics={},
            hardware={"memory": [{"capacityGB": 8}, {"capacityGB": 8}],
                      "gpus": [{"vendor": "NVIDIA", "isDedicated": True}]},
            gpu_info=_gpu("Turing"),
        )
        self.assertIn("Insufficient RAM", titles)

    def test_no_dedicated_gpu_flagged(self):
        titles = self._titles(
            identity=_identity("5.2.0"),
            performance={}, services={}, nics={},
            hardware={"memory": [{"capacityGB": 16}, {"capacityGB": 16}],
                      "gpus": [{"vendor": "Intel", "isDedicated": False}]},
            gpu_info=_gpu("Turing"),
        )
        self.assertIn("No dedicated GPU detected", titles)

    def test_findings_have_required_shape(self):
        # Every finding must carry severity + title so the dashboard can render it.
        findings = main._compute_findings(
            identity=_identity("5.13.6"),  # Pascal over-cap
            performance={}, services={}, nics={},
            hardware={"gpus": [{"vendor": "NVIDIA", "isDedicated": True}]},
            gpu_info=_gpu("Pascal"),
        )
        self.assertTrue(findings)
        for f in findings:
            self.assertIn(f.get("severity"), ("critical", "warning"), f)
            self.assertTrue(f.get("title"), f)

    def test_no_duplicate_findings(self):
        findings = main._compute_findings(
            identity=_identity("5.13.6"),
            performance={}, services={}, nics={},
            hardware={"gpus": [{"vendor": "Intel", "isDedicated": False}]},
            gpu_info=_gpu("Pascal"),
        )
        keys = [(f.get("category", ""), f["title"]) for f in findings]
        self.assertEqual(len(keys), len(set(keys)), "duplicate findings present")


# ── run_ps stdout JSON recovery (the resilience fix) ─────────
class TestExtractJson(unittest.TestCase):
    def test_clean_json(self):
        self.assertEqual(powershell._extract_json('{"a": 1}'), {"a": 1})

    def test_leading_noise_recovered(self):
        # PS leaked a warning line before the JSON — must still recover.
        noisy = 'WARNING: module slow to load\n{"devices": [], "ok": true}'
        self.assertEqual(powershell._extract_json(noisy), {"devices": [], "ok": True})

    def test_multiline_picks_json_line(self):
        blob = "VERBOSE: starting\nVERBOSE: done\n{\"x\": 5}"
        self.assertEqual(powershell._extract_json(blob), {"x": 5})

    def test_unparseable_returns_none(self):
        self.assertIsNone(powershell._extract_json("not json at all"))
        self.assertIsNone(powershell._extract_json(""))
        self.assertIsNone(powershell._extract_json(None))

    def test_array_payload(self):
        self.assertEqual(powershell._extract_json('[1, 2, 3]'), [1, 2, 3])


if __name__ == "__main__":
    unittest.main(verbosity=2)
