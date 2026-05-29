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


# ── DNS discrepancy classification (PDF #10) ─────────────────
class TestDnsDiscrepancy(unittest.TestCase):
    """A real DNS redirect (system resolver returns an internal IP) must be
    distinguished from benign CDN/GeoDNS load balancing (two different public
    IPs) — the latter is normal and must not warn."""

    def test_private_ip_detection(self):
        for ip in ("10.0.0.5", "192.168.1.1", "172.16.4.9", "169.254.1.1",
                   "127.0.0.1", "100.64.0.1"):
            self.assertTrue(main._is_private_or_bogon_ip(ip), ip)
        for ip in ("52.44.182.199", "143.204.160.127", "8.8.8.8", "1.1.1.1"):
            self.assertFalse(main._is_private_or_bogon_ip(ip), ip)
        for junk in ("", None, "not-an-ip", "example.com"):
            self.assertFalse(main._is_private_or_bogon_ip(junk), junk)

    def _row(self, sys_ip, sys_status, goog_ip, goog_status):
        return ({"resolvedTo": sys_ip, "status": sys_status},
                {"resolvedTo": goog_ip, "status": goog_status})

    def test_cdn_different_public_ips_is_benign(self):
        # The reported false positive: software.pixellot.tv on CloudFront.
        s, g = self._row("143.204.160.127", "pass", "143.204.160.99", "pass")
        self.assertIsNone(main._classify_dns_row(s, g))
        # And the apex domain on different AWS IPs.
        s, g = self._row("52.44.182.199", "pass", "52.1.53.61", "pass")
        self.assertIsNone(main._classify_dns_row(s, g))

    def test_same_ip_is_benign(self):
        s, g = self._row("52.1.53.61", "pass", "52.1.53.61", "pass")
        self.assertIsNone(main._classify_dns_row(s, g))

    def test_redirect_to_internal_ip_flagged(self):
        # Captive portal / SSL-inspection proxy: system returns a private IP.
        s, g = self._row("192.168.1.50", "pass", "52.1.53.61", "pass")
        self.assertEqual(main._classify_dns_row(s, g), "redirect")

    def test_system_blocked_flagged(self):
        s, g = self._row(None, "fail", "52.1.53.61", "pass")
        self.assertEqual(main._classify_dns_row(s, g), "system-blocked")

    def test_google_blocked_flagged(self):
        s, g = self._row("52.1.53.61", "pass", None, "fail")
        self.assertEqual(main._classify_dns_row(s, g), "google-blocked")

    def test_annotate_recomputes_counts(self):
        dns = {"results": [
            {"system": {"resolvedTo": None, "status": "fail"},
             "google": {"resolvedTo": "52.1.53.61", "status": "pass"}},
            {"system": {"resolvedTo": "143.204.160.127", "status": "pass"},
             "google": {"resolvedTo": "143.204.160.99", "status": "pass"}},
            {"system": {"resolvedTo": "192.168.1.50", "status": "pass"},
             "google": {"resolvedTo": "52.1.53.61", "status": "pass"}},
        ]}
        out = main._annotate_dns_resolution(dns)
        self.assertEqual(out["systemBlockedCount"], 1)
        self.assertEqual(out["redirectCount"], 1)
        self.assertEqual([r["discrepancy"] for r in out["results"]],
                         ["system-blocked", None, "redirect"])


# ── Internet reachability derivation ─────────────────────────
class TestInternetReachable(unittest.TestCase):
    """A locked-down venue network blocks ICMP/8.8.8.8 but Pixellot services
    stay reachable. internetReachable must come from real service reachability
    (a passing TCP/443 test), not just the 8.8.8.8 probe."""

    _PORTS_443_PASS = {"results": [
        {"protocol": "TCP", "port": 443, "host": "pixellot.tv",
         "purpose": "Pixellot", "optional": False, "status": "pass"},
    ]}
    _PORTS_443_FAIL = {"results": [
        {"protocol": "TCP", "port": 443, "host": "pixellot.tv",
         "purpose": "Pixellot", "optional": False, "status": "fail"},
    ]}

    def test_probe_success_wins(self):
        cfg = {"internet": {"reachable": True, "testedHost": "8.8.8.8"}}
        self.assertEqual(main._internet_reachable(cfg, None), (True, "8.8.8.8"))

    def test_icmp_blocked_but_443_passes(self):
        # The field case: probe failed, but HTTPS to pixellot.tv works.
        cfg = {"internet": {"reachable": False, "testedHost": None}}
        reachable, host = main._internet_reachable(cfg, self._PORTS_443_PASS)
        self.assertTrue(reachable)
        self.assertEqual(host, "pixellot.tv:443")

    def test_truly_offline(self):
        cfg = {"internet": {"reachable": False, "testedHost": None}}
        self.assertEqual(main._internet_reachable(cfg, self._PORTS_443_FAIL), (False, None))

    def test_optional_443_does_not_count(self):
        cfg = {"internet": {"reachable": False, "testedHost": None}}
        ports = {"results": [{"protocol": "TCP", "port": 443, "host": "x",
                              "optional": True, "status": "pass"}]}
        self.assertEqual(main._internet_reachable(cfg, ports), (False, None))

    def test_missing_ports_falls_back_to_probe(self):
        cfg = {"internet": {"reachable": False, "testedHost": None}}
        self.assertEqual(main._internet_reachable(cfg, None), (False, None))


# ── Wi-Fi uplink finding gating ──────────────────────────────
class TestWifiUplinkFinding(unittest.TestCase):
    """The Wi-Fi warning must fire only when Wi-Fi is the actual internet
    uplink — never for Wi-Fi Direct / virtual adapters that merely show
    'connected'."""

    def _wifi_titles(self, wifi):
        findings = main._compute_findings(
            identity=_identity("5.2.0"), performance={}, services={}, nics={},
            hardware={"gpus": [{"vendor": "NVIDIA", "isDedicated": True}]},
            gpu_info=_gpu("Turing"), wifi=wifi,
        )
        return {f["title"] for f in findings if f.get("category") == "Network"}

    def _has_wifi_finding(self, titles):
        return any("Wi-Fi" in t or "WiFi" in t for t in titles)

    def test_virtual_adapter_does_not_warn(self):
        # The reported false positive: Wi-Fi Direct virtual adapter, connected,
        # but not the uplink. uplinkIsWifi=False → no finding.
        wifi = {
            "uplinkIsWifi": False, "ethernetHasDefaultRoute": True,
            "adapters": [{
                "interfaceDescription": "Microsoft Wi-Fi Direct Virtual Adapter #2",
                "isUp": True, "isVirtual": True, "hasDefaultRoute": False,
                "connected": True, "ssid": "DIRECT-3a-DESKTOP",
            }],
        }
        self.assertFalse(self._has_wifi_finding(self._wifi_titles(wifi)))

    def test_real_wifi_uplink_warns(self):
        # Real Wi-Fi NIC holding the default route, no wired uplink → warn.
        wifi = {
            "uplinkIsWifi": True, "ethernetHasDefaultRoute": False,
            "adapters": [{
                "interfaceDescription": "Intel(R) Wi-Fi 6 AX201 160MHz",
                "isUp": True, "isVirtual": False, "hasDefaultRoute": True,
                "connected": True, "ssid": "Venue-WiFi",
            }],
        }
        self.assertTrue(self._has_wifi_finding(self._wifi_titles(wifi)))

    def test_no_wifi_payload_no_warn(self):
        self.assertFalse(self._has_wifi_finding(self._wifi_titles(None)))
        self.assertFalse(self._has_wifi_finding(self._wifi_titles({"error": True})))


# ── NTP source allowlist (PDF #9) ────────────────────────────
class TestNtpAllowlist(unittest.TestCase):
    def test_canonical_sources_approved(self):
        for s in ("0.us.pool.ntp.org", "1.us.pool.ntp.org",
                  "2.us.pool.ntp.org", "3.us.pool.ntp.org"):
            self.assertTrue(main._is_approved_ntp_source(s), s)

    def test_case_and_whitespace_tolerant(self):
        self.assertTrue(main._is_approved_ntp_source("2.US.POOL.NTP.ORG"))
        self.assertTrue(main._is_approved_ntp_source("  0.us.pool.ntp.org  "))

    def test_any_us_pool_subdomain_approved(self):
        # The four canonical names are aliases into the same pool.
        self.assertTrue(main._is_approved_ntp_source("custom.us.pool.ntp.org"))

    def test_off_pool_sources_rejected(self):
        for s in ("time.windows.com", "time.nist.gov", "pool.ntp.org",
                  "Local CMOS Clock", "", None):
            self.assertFalse(main._is_approved_ntp_source(s), s)


# ── Demo-data contract (catches demo-vs-real drift) ──────────
class TestDemoDataContract(unittest.TestCase):
    """Every PowerShell script the backend invokes via run_ps must have a
    demo-mode entry, or demo mode silently returns null for that section
    on a non-Windows host. This is the class of bug behind the earlier
    Get-NetworkHealth `remoteHost` mismatch."""

    # Scripts referenced by main.py that intentionally have no demo entry yet.
    # Keep this minimal — each entry is a known gap. Remove an entry once its
    # demo data lands (test_exempt_list_has_no_stale_entries enforces that).
    _DEMO_EXEMPT = {
        # Owned by the ScoreConnect session — demo entries pending.
        "Get-Sc3InstallStatus.ps1",
        "Install-ScoreConnectIII.ps1",
    }

    def _referenced_scripts(self):
        import re
        with open(os.path.join(_APP_DIR, "main.py"), encoding="utf-8") as f:
            src = f.read()
        return set(re.findall(r'run_ps\(\s*"([^"]+\.ps1)"', src))

    def test_every_referenced_script_has_demo(self):
        import demo_data
        referenced = self._referenced_scripts()
        missing = referenced - set(demo_data.DEMO) - self._DEMO_EXEMPT
        self.assertEqual(
            missing, set(),
            f"Scripts invoked by main.py with no demo_data entry — demo mode "
            f"returns null for these: {sorted(missing)}",
        )

    def test_exempt_list_has_no_stale_entries(self):
        # If an exempt script gained a demo entry, drop it from the exempt set
        # so the contract stays honest.
        import demo_data
        stale = self._DEMO_EXEMPT & set(demo_data.DEMO)
        self.assertEqual(
            stale, set(),
            f"In _DEMO_EXEMPT but now have demo entries — remove them: {sorted(stale)}",
        )

    def test_demo_entries_callable_and_serializable(self):
        # A demo lambda that raises or returns non-JSON would break demo mode
        # for that section. Each must run with no args and serialize cleanly.
        import json
        import demo_data
        for name, fn in demo_data.DEMO.items():
            with self.subTest(script=name):
                result = fn()
                self.assertIsInstance(result, (dict, list), name)
                json.dumps(result, default=str)


if __name__ == "__main__":
    unittest.main(verbosity=2)
