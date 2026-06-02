"""Unit tests for Camera Connectivity logic (_enrich_ports + findings).

Stdlib unittest only — no pytest, no network, no PowerShell:

    cd Pulse.Web && python3 -m unittest discover -s tests

These lock in the camera-identification, port-ordering, dedup, labeling,
and finding logic that's easy to break silently when sessions edit
main.py. Pure functions only.
"""

import asyncio
import os
import sys
import time
import unittest

_APP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
if _APP_DIR not in sys.path:
    sys.path.insert(0, _APP_DIR)

import main  # noqa: E402
import powershell  # noqa: E402


def _port(name, mac, status="Up", speed=1000, rx=1, arp=None):
    return {
        "name": name, "mac": mac, "status": status,
        "linkSpeedMbps": speed, "rxBytes": rx,
        "arpEntries": arp or [],
    }


def _arp(ip, mac):
    return {"ip": ip, "mac": mac}


def _enrich(nics_ports, pix_config=None, probes=None, expected_main=None):
    return main._enrich_ports(
        {"ports": nics_ports}, pix_config, probes or {},
        expected_main_cameras=expected_main,
    )


class TestPortOrdering(unittest.TestCase):
    def test_lowest_mac_is_port_1_ascending(self):
        # Scrambled input order; lowest MAC must land at index 0 (Port 1).
        ports = _enrich([
            _port("Eth-C", "00-30-64-36-73-AC"),
            _port("Eth-A", "00-30-64-36-73-AA"),
            _port("Eth-D", "00-30-64-36-73-AD"),
            _port("Eth-B", "00-30-64-36-73-AB"),
        ])
        self.assertEqual([p["name"] for p in ports],
                         ["Eth-A", "Eth-B", "Eth-C", "Eth-D"])
        self.assertEqual(ports[0]["portLabel"], "Port 1")

    def test_hex_value_not_string_sort(self):
        # 0x09 < 0x0A < 0x10 numerically. Hex int ordering must hold.
        self.assertLess(main._mac_to_int("00:00:00:00:00:09"),
                        main._mac_to_int("00:00:00:00:00:0A"))
        self.assertLess(main._mac_to_int("00:00:00:00:00:0A"),
                        main._mac_to_int("00:00:00:00:00:10"))

    def test_separator_and_case_insensitive(self):
        self.assertEqual(main._mac_to_int("a4:4c:c8:12:34:01"),
                         main._mac_to_int("A4-4C-C8-12-34-01"))

    def test_malformed_mac_sorts_last(self):
        self.assertGreater(main._mac_to_int("not-a-mac"),
                           main._mac_to_int("FF:FF:FF:FF:FF:FF"))


class TestIdentityLayering(unittest.TestCase):
    def setUp(self):
        main._PORT_STATE_TRACKER.clear()

    def test_cgi_model_wins_over_wrong_cfg(self):
        # cameras.cfg wrongly calls .52 a Main; CGI model (E8NC-G) says OCR.
        cfg = {"cameras": [{"section": "C", "ip": "169.254.16.52",
                            "mac": "00-D0-89-1E-89-08", "role": "Main"}]}
        probes = {"00:D0:89:1E:89:08": {"mac": "00:D0:89:1E:89:08",
                  "ip": "169.254.16.52", "modelNumber": "E8NC-G"}}
        ports = _enrich([_port("E", "00-30-64-36-73-AA",
                         arp=[_arp("169.254.16.52", "00-D0-89-1E-89-08")])],
                        cfg, probes)
        cam = ports[0]["camerasDetected"][0]
        self.assertEqual(cam["role"], "OCR / Scoreboard")
        self.assertEqual(cam["identitySource"], "Camera model")

    def test_default_ip_overrides_wrong_cfg(self):
        # No CGI. cfg wrongly says .50 is OCR; default-IP convention wins.
        cfg = {"cameras": [{"section": "C", "ip": "169.254.16.50",
                            "mac": "00-D0-89-19-71-57", "role": "OCR"}]}
        ports = _enrich([_port("E", "00-30-64-36-73-AA",
                         arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")])], cfg)
        cam = ports[0]["camerasDetected"][0]
        self.assertEqual(cam["role"], "Main Camera")
        self.assertEqual(cam["identitySource"], "Default IP")

    def test_cfg_is_last_resort_for_non_default_ip(self):
        cfg = {"cameras": [{"section": "C", "ip": "192.168.5.20",
                            "mac": "00-0E-53-AA-01-01", "role": "Main"}]}
        ports = _enrich([_port("E", "00-30-64-36-73-AA",
                         arp=[_arp("192.168.5.20", "00-0E-53-AA-01-01")])], cfg)
        cam = ports[0]["camerasDetected"][0]
        self.assertEqual(cam["identitySource"], "cameras.cfg")


class TestDownReason(unittest.TestCase):
    """Classify *why* a port is down so the UI can guide the tech."""

    def test_disabled_via_admin_status(self):
        self.assertEqual(main._derive_down_reason(
            {"status": "Disconnected", "adminStatus": "Down"}), "disabled")

    def test_disabled_via_status(self):
        self.assertEqual(main._derive_down_reason({"status": "Disabled"}), "disabled")

    def test_driver_fault(self):
        self.assertEqual(main._derive_down_reason(
            {"status": "Down", "adminStatus": "Up", "driverStatus": "Error"}), "driver")

    def test_driver_ok_is_not_driver_reason(self):
        self.assertEqual(main._derive_down_reason(
            {"status": "Disconnected", "adminStatus": "Up",
             "driverStatus": "OK", "mediaConnectionState": "Disconnected"}), "no-link")

    def test_no_link_via_media(self):
        self.assertEqual(main._derive_down_reason(
            {"status": "Down", "adminStatus": "Up", "mediaConnectionState": "Disconnected"}), "no-link")

    def test_enriched_down_port_gets_reason_up_port_none(self):
        nics = {"ports": [
            _port("Up", "00-30-64-36-73-AA"),
            dict(_port("Dn", "00-30-64-36-73-AB", status="Down"), adminStatus="Up",
                 mediaConnectionState="Disconnected"),
        ]}
        ports = _enrich(nics["ports"])
        by = {p["name"]: p for p in ports}
        self.assertIsNone(by["Up"]["downReason"])
        self.assertEqual(by["Dn"]["downReason"], "no-link")

    # --- Regression: real VPUs serialize Windows enums as INTEGERS, not the
    # string names demo data uses. A bare .lower() on an int 500'd the whole
    # /api/cameras endpoint. These guard against that ever returning. ---
    def test_int_enum_fields_do_not_crash(self):
        # mediaConnectionState/adminStatus/status arriving as ints must not raise.
        r = main._derive_down_reason(
            {"status": "Down", "adminStatus": 1, "mediaConnectionState": 2,
             "driverStatus": 0})
        self.assertEqual(r, "no-link")  # falls through to the string status check

    def test_numeric_driver_status_not_flagged_as_driver_fault(self):
        # A numeric driverStatus we can't interpret must NOT mis-classify as a
        # driver fault — it should fall through to the link check.
        self.assertEqual(main._derive_down_reason(
            {"status": "Disconnected", "adminStatus": "Up",
             "driverStatus": 0, "mediaConnectionState": 0}), "no-link")

    def test_enriched_down_port_with_int_enums_no_crash(self):
        nics = {"ports": [
            dict(_port("Dn", "00-30-64-36-73-AB", status="Down"),
                 adminStatus=1, mediaConnectionState=2, driverStatus=0),
        ]}
        ports = _enrich(nics["ports"])  # must not raise
        self.assertEqual(ports[0]["downReason"], "no-link")


class TestDedupAndDownPorts(unittest.TestCase):
    def setUp(self):
        main._PORT_STATE_TRACKER.clear()

    def test_same_mac_two_up_ports_kept_on_higher_rx(self):
        ports = _enrich([
            _port("Low", "00-30-64-36-73-AA", rx=100,
                  arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")]),
            _port("High", "00-30-64-36-73-AB", rx=999999,
                  arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")]),
        ])
        by_name = {p["name"]: p for p in ports}
        self.assertEqual(len(by_name["High"]["camerasDetected"]), 1)
        self.assertEqual(len(by_name["Low"]["camerasDetected"]), 0)

    def test_down_port_has_no_cameras(self):
        ports = _enrich([_port("E", "00-30-64-36-73-AA", status="Down",
                         arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")])])
        self.assertEqual(ports[0]["camerasDetected"], [])
        self.assertIsNone(ports[0]["cameraLabel"])


class TestLabelingAndCap(unittest.TestCase):
    def setUp(self):
        main._PORT_STATE_TRACKER.clear()

    def test_main_numbering_by_ip(self):
        ports = _enrich([
            _port("A", "00-30-64-36-73-AA", arp=[_arp("169.254.16.51", "00-D0-89-19-71-51")]),
            _port("B", "00-30-64-36-73-AB", arp=[_arp("169.254.16.50", "00-D0-89-19-71-50")]),
        ])
        labels = {p["camerasDetected"][0]["ip"]: p["cameraLabel"] for p in ports}
        self.assertEqual(labels["169.254.16.50"], "Main Camera 1")
        self.assertEqual(labels["169.254.16.51"], "Main Camera 2")

    def test_ocr_1g_label_for_e8nc(self):
        probes = {"00:D0:89:1E:89:08": {"mac": "00:D0:89:1E:89:08",
                  "ip": "169.254.16.52", "modelNumber": "E8NC-G"}}
        ports = _enrich([_port("E", "00-30-64-36-73-AA",
                         arp=[_arp("169.254.16.52", "00-D0-89-1E-89-08")])], None, probes)
        self.assertEqual(ports[0]["cameraLabel"], "OCR-1G")

    def test_ocr_plain_for_100mbps(self):
        probes = {"00:D0:89:1B:03:01": {"mac": "00:D0:89:1B:03:01",
                  "ip": "169.254.16.52", "modelNumber": "R2SD-G"}}
        ports = _enrich([_port("E", "00-30-64-36-73-AA", speed=100,
                         arp=[_arp("169.254.16.52", "00-D0-89-1B-03-01")])], None, probes)
        self.assertEqual(ports[0]["cameraLabel"], "OCR")

    def test_main_cap_uses_expected_count(self):
        # 3 main cameras detected but the system expects 2 (S2) → 3rd is
        # downgraded to a generic "Camera", not "Main Camera 3".
        ps = [
            _port("A", "00-30-64-36-73-AA", arp=[_arp("169.254.16.50", "00-D0-89-19-71-50")]),
            _port("B", "00-30-64-36-73-AB", arp=[_arp("169.254.16.51", "00-D0-89-19-71-51")]),
            _port("C", "00-30-64-36-73-AC", arp=[_arp("169.254.16.55", "00-D0-89-19-71-55")]),
        ]
        ports = _enrich(ps, None, None, expected_main=2)
        labels = sorted(p["cameraLabel"] for p in ports)
        self.assertEqual(labels, ["Camera", "Main Camera 1", "Main Camera 2"])


class TestCameraDropFinding(unittest.TestCase):
    def setUp(self):
        main._PORT_STATE_TRACKER.clear()

    def _settle(self):
        # Backdate every tracked port so its current state counts as settled.
        for e in main._PORT_STATE_TRACKER.values():
            e["since"] -= main._PORT_SETTLE_SECONDS + 5

    def test_drop_flagged_when_camera_disappears(self):
        up = [_port("E", "00-30-64-36-73-AA",
              arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")])]
        down = [_port("E", "00-30-64-36-73-AA", status="Down")]
        _enrich(up)            # camera present → everHadCamera
        _enrich(down)          # camera gone → down state begins
        self._settle()          # let the down state settle
        ports = _enrich(down)
        findings = main._compute_camera_findings(ports)
        self.assertTrue(any("camera dropped" in f["title"].lower() for f in findings),
                        f"expected a drop finding, got {findings}")

    def test_move_not_flagged_as_drop(self):
        # Camera starts on port A, then appears on port B (moved). Port A
        # must NOT be flagged as a drop because the MAC is present elsewhere.
        start = [
            _port("A", "00-30-64-36-73-AA", arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")]),
            _port("B", "00-30-64-36-73-AB"),
        ]
        moved = [
            _port("A", "00-30-64-36-73-AA", status="Down"),
            _port("B", "00-30-64-36-73-AB", arp=[_arp("169.254.16.50", "00-D0-89-19-71-57")]),
        ]
        _enrich(start)
        _enrich(moved)
        self._settle()
        ports = _enrich(moved)
        findings = main._compute_camera_findings(ports)
        self.assertFalse(any("camera dropped" in f["title"].lower() for f in findings),
                         f"move should not flag a drop, got {findings}")

    def test_empty_port_never_flags_drop(self):
        # A port that never hosted a camera (e.g. uplink) → no drop finding.
        empty = [_port("Uplink", "00-30-64-36-73-AA", arp=[_arp("10.0.1.1", "00-1A-2B-3C-4D-5E")])]
        _enrich(empty)
        self._settle()
        ports = _enrich(empty)
        findings = main._compute_camera_findings(ports)
        self.assertFalse(any("camera dropped" in f["title"].lower() for f in findings))


class TestFrameCooldown(unittest.TestCase):
    """Frame-capture rate limit. The first capture must always be allowed
    (monotonic() can start near 0, so the default must read as 'long ago')."""

    def setUp(self):
        self._saved = main._LAST_FRAME_CAPTURE

    def tearDown(self):
        main._LAST_FRAME_CAPTURE = self._saved

    def test_first_capture_allowed(self):
        main._LAST_FRAME_CAPTURE = -1e9  # default init
        self.assertEqual(main._frame_cooldown_remaining(0.3), 0)
        self.assertEqual(main._frame_cooldown_remaining(0.0), 0)

    def test_blocks_within_window_then_ready(self):
        main._LAST_FRAME_CAPTURE = 100.0
        self.assertGreater(main._frame_cooldown_remaining(105.0), 0)   # 5s in → blocked
        self.assertEqual(main._frame_cooldown_remaining(116.0), 0)     # >15s → ready


class TestRunPsCacheBypass(unittest.TestCase):
    """run_ps(use_cache=False) must always run fresh — frame grabs can't
    replay a 25s-old cached snapshot."""

    def setUp(self):
        powershell._RESULT_CACHE.clear()

    def test_cached_run_populates_cache(self):
        asyncio.run(powershell.run_ps("Test-NtpDrift.ps1"))
        self.assertGreaterEqual(len(powershell._RESULT_CACHE), 1)

    def test_no_cache_run_skips_cache(self):
        asyncio.run(powershell.run_ps("Test-NtpDrift.ps1", use_cache=False))
        self.assertEqual(len(powershell._RESULT_CACHE), 0)


if __name__ == "__main__":
    unittest.main()
