"""Unit tests for the proactive-monitoring engine (PULSEDEV-50/51/52).

Pure-Python, standard-library only — these import `monitor` directly (it has no
FastAPI/PowerShell dependency) so they run anywhere:

    cd Pulse.Web && .venv/bin/python -m unittest discover -s tests -v

They cover the state diff, the severity gate, the recording-aware out-of-scope
carry-forward, the file-backed state round-trip, and the full-recompute
orchestration with mocked collectors. The async loop's wall-clock timing is not
unit-tested (it's a thin scheduler over these pure functions).
"""

import asyncio
import json
import os
import sys
import tempfile
import unittest

_APP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
if _APP_DIR not in sys.path:
    sys.path.insert(0, _APP_DIR)

import monitor  # noqa: E402


def _verdict(status="PASS", blockers=(), risks=(), info=()):
    def mk(codes):
        return [{"code": c, "title": f"{c} title", "category": "Cat",
                 "recommendation": f"fix {c}"} for c in codes]
    return {"status": status, "policyVersion": "v1",
            "blockers": mk(blockers), "risks": mk(risks), "info": mk(info)}


class TestCodesFromVerdict(unittest.TestCase):
    def test_flattens_with_class(self):
        v = _verdict("FAIL", blockers=["agent-down"], risks=["nic-slow"], info=["tz-non-us"])
        codes = monitor.codes_from_verdict(v)
        self.assertEqual(codes["agent-down"]["class"], "blocker")
        self.assertEqual(codes["nic-slow"]["class"], "risk")
        self.assertEqual(codes["tz-non-us"]["class"], "info")
        self.assertEqual(codes["agent-down"]["title"], "agent-down title")

    def test_empty_and_none(self):
        self.assertEqual(monitor.codes_from_verdict(None), {})
        self.assertEqual(monitor.codes_from_verdict({}), {})

    def test_skips_codeless_entries(self):
        v = {"blockers": [{"title": "no code"}], "risks": [], "info": []}
        self.assertEqual(monitor.codes_from_verdict(v), {})


class TestRouting(unittest.TestCase):
    def test_route_for(self):
        self.assertEqual(monitor.route_for("blocker"), "alert")
        self.assertEqual(monitor.route_for("risk"), "digest")
        self.assertEqual(monitor.route_for("info"), "log")
        self.assertEqual(monitor.route_for("nonsense"), "log")


class TestComputeDelta(unittest.TestCase):
    def _codes(self, verdict):
        return monitor.codes_from_verdict(verdict)

    def test_opened_blocker_sets_alert(self):
        prev = {}
        cur = self._codes(_verdict("FAIL", blockers=["agent-down"]))
        new_open, delta = monitor.compute_delta(prev, cur, "PASS", "FAIL", "SN1", now="T0")
        self.assertEqual([e["code"] for e in delta["opened"]], ["agent-down"])
        self.assertEqual(delta["opened"][0]["fingerprint"], "SN1:agent-down")
        self.assertEqual(delta["opened"][0]["route"], "alert")
        self.assertTrue(delta["alert"])
        self.assertTrue(delta["statusChanged"])
        self.assertEqual(new_open["agent-down"]["since"], "T0")

    def test_resolved_when_code_absent(self):
        prev = {"agent-down": {"class": "blocker", "title": "t", "category": "Services",
                               "recommendation": "r", "since": "T0"}}
        cur = self._codes(_verdict("PASS"))
        new_open, delta = monitor.compute_delta(prev, cur, "FAIL", "PASS", "SN1", now="T1")
        self.assertEqual([e["code"] for e in delta["resolved"]], ["agent-down"])
        self.assertTrue(delta["alert"])
        self.assertEqual(new_open, {})

    def test_persisting_is_silent_and_keeps_since(self):
        prev = {"nic-slow": {"class": "risk", "title": "t", "category": "Network",
                             "recommendation": "r", "since": "T0"}}
        cur = self._codes(_verdict("WARN", risks=["nic-slow"]))
        new_open, delta = monitor.compute_delta(prev, cur, "WARN", "WARN", "SN1", now="T9")
        self.assertEqual(delta["opened"], [])
        self.assertEqual(delta["resolved"], [])
        self.assertEqual(delta["persisting"], ["nic-slow"])
        self.assertFalse(delta["statusChanged"])
        self.assertEqual(new_open["nic-slow"]["since"], "T0")  # carried forward, not reset

    def test_info_only_transition_does_not_alert(self):
        prev = {}
        cur = self._codes(_verdict("PASS", info=["tz-non-us"]))
        _, delta = monitor.compute_delta(prev, cur, "PASS", "PASS", "SN1", now="T0")
        self.assertEqual([e["code"] for e in delta["opened"]], ["tz-non-us"])
        self.assertFalse(delta["alert"])            # info never sets the blocker alert flag
        self.assertFalse(delta["statusChanged"])
        self.assertFalse(monitor.should_alert_now(delta))   # info-only → wait for periodic

    def test_risk_transition_alerts_now_without_blocker_flag(self):
        prev = {}
        cur = self._codes(_verdict("WARN", risks=["nic-slow"]))
        _, delta = monitor.compute_delta(prev, cur, "PASS", "WARN", "SN1", now="T0")
        self.assertFalse(delta["alert"])            # alert flag is blocker-only
        self.assertTrue(monitor.should_alert_now(delta))    # but a risk still warrants an immediate beacon

    def test_out_of_scope_code_carried_forward_not_resolved(self):
        # Recording-aware backoff: the port probe was skipped, so its blocker is
        # absent from the current verdict. It must NOT be reported resolved.
        prev = {"stream-2088-blocked": {"class": "blocker", "title": "t",
                                        "category": "Network", "recommendation": "r", "since": "T0"}}
        cur = self._codes(_verdict("PASS"))  # port probe skipped → no port codes
        new_open, delta = monitor.compute_delta(
            prev, cur, "FAIL", "PASS", "SN1",
            out_of_scope=monitor.INTRUSIVE_PORT_CODES, now="T1")
        self.assertEqual(delta["resolved"], [])
        self.assertIn("stream-2088-blocked", new_open)
        self.assertEqual(new_open["stream-2088-blocked"]["since"], "T0")

    def test_out_of_scope_still_resolves_non_port_codes(self):
        prev = {
            "stream-2088-blocked": {"class": "blocker", "since": "T0"},
            "agent-down": {"class": "blocker", "title": "t", "category": "Services",
                           "recommendation": "r", "since": "T0"},
        }
        cur = self._codes(_verdict("PASS"))
        new_open, delta = monitor.compute_delta(
            prev, cur, "FAIL", "PASS", "SN1",
            out_of_scope=monitor.INTRUSIVE_PORT_CODES, now="T1")
        self.assertEqual([e["code"] for e in delta["resolved"]], ["agent-down"])
        self.assertIn("stream-2088-blocked", new_open)   # carried
        self.assertNotIn("agent-down", new_open)         # resolved


class TestStatePersistence(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "pulse-monitor-state.json")

    def test_missing_file_is_empty(self):
        s = monitor.load_state(self.path)
        self.assertEqual(s["open"], {})
        self.assertIsNone(s["status"])

    def test_round_trip(self):
        open_map = {"agent-down": {"class": "blocker", "title": "t",
                                   "category": "Services", "recommendation": "r", "since": "T0"}}
        monitor.save_state(self.path, open_map, "FAIL", "SN1")
        s = monitor.load_state(self.path)
        self.assertEqual(s["status"], "FAIL")
        self.assertEqual(s["serial"], "SN1")
        self.assertEqual(s["open"], open_map)

    def test_version_mismatch_resets(self):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump({"version": 999, "open": {"x": {}}, "status": "FAIL"}, f)
        s = monitor.load_state(self.path)
        self.assertEqual(s["open"], {})

    def test_corrupt_file_resets(self):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("{not json")
        self.assertEqual(monitor.load_state(self.path)["open"], {})


class _FakeDeps(monitor.MonitorDeps):
    """In-memory deps for orchestration tests — records what the loop did."""
    def __init__(self, dashboard, recording=False, tripwire=False):
        self._dash = dashboard
        self._recording = recording
        self._tripwire = tripwire
        self.beacons = []
        self.cache_cleared = 0
        self.collected_with = []

        async def collect(skip_intrusive):
            self.collected_with.append(skip_intrusive)
            return self._dash

        async def send(dashboard=None, delta=None, reason=None):
            self.beacons.append({"reason": reason, "delta": delta})

        async def is_rec():
            return self._recording

        async def trip():
            return self._tripwire

        super().__init__(
            collect_dashboard=collect, send_checkin=send, is_recording=is_rec,
            service_tripwire=trip, get_serial=lambda d: "SN1",
            clear_cache=self._clear,
        )

    def _clear(self):
        self.cache_cleared += 1


class TestFullRecompute(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "state.json")

    async def test_opened_blocker_fires_state_change_beacon(self):
        deps = _FakeDeps({"readiness": _verdict("FAIL", blockers=["agent-down"])})
        delta = await monitor.run_full_recompute(deps, self.path, recording=False)
        self.assertEqual(deps.cache_cleared, 1)
        self.assertEqual(deps.collected_with, [False])
        self.assertEqual(len(deps.beacons), 1)
        self.assertEqual(deps.beacons[0]["reason"], "state-change")
        self.assertEqual([e["code"] for e in delta["opened"]], ["agent-down"])
        # State persisted so the next run sees it as persisting (no re-alert).
        self.assertIn("agent-down", monitor.load_state(self.path)["open"])

    async def test_steady_state_is_periodic_not_state_change(self):
        deps = _FakeDeps({"readiness": _verdict("WARN", risks=["nic-slow"])})
        await monitor.run_full_recompute(deps, self.path, recording=False)   # opens
        deps.beacons.clear()
        await monitor.run_full_recompute(deps, self.path, recording=False)   # persists
        self.assertEqual(deps.beacons[0]["reason"], "periodic")
        self.assertEqual(deps.beacons[0]["delta"]["opened"], [])

    async def test_recording_skips_cache_clear_and_intrusive_probe(self):
        deps = _FakeDeps({"readiness": _verdict("PASS")}, recording=True)
        await monitor.run_full_recompute(deps, self.path, recording=True)
        self.assertEqual(deps.cache_cleared, 0)        # don't disturb a live encode
        self.assertEqual(deps.collected_with, [True])  # skip_intrusive passed through


if __name__ == "__main__":
    unittest.main()
