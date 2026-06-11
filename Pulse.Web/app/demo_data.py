"""Mock data for non-Windows demo mode."""

import base64
import random
import time
from datetime import datetime, timedelta


def _demo_frame(label, color):
    """A base64 SVG data URI standing in for a captured camera frame, so the
    Verify Video thumbnail UI can be exercised in demo mode (no ffmpeg)."""
    svg = (
        "<svg xmlns='http://www.w3.org/2000/svg' width='480' height='270'>"
        f"<rect width='480' height='270' fill='{color}'/>"
        "<text x='240' y='150' font-family='sans-serif' font-size='20' "
        f"fill='#cbd5e1' text-anchor='middle'>{label}</text></svg>"
    )
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()

# ── Demo venue identity ──────────────────────────────────────
# Picked once at module load so all scripts return consistent data
# for a single Pulse session. Each session re-imports → fresh pick.
# The pool is small + curated so demos look like real Pixellot
# venues without ever showing actual customer data.
_DEMO_VENUES = [
    {"hostname": "PXLS2-31402", "vpuName": "PXLS2_31402 Westfield Academy (TX) - Gymnasium",     "venueId": "5fdb1c042e3a86412c7a04b8", "serial": "CZC8847PQR", "city": "Houston",      "state": "TX", "uplinkIp": "10.40.16.50", "gatewayIp": "10.40.16.1", "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-22158", "vpuName": "PXLS2_22158 Roosevelt High School (CA) - Main Court","venueId": "603a45f08c9e217d09b51230", "serial": "CZC7235HXM", "city": "Riverside",    "state": "CA", "uplinkIp": "10.22.8.50",  "gatewayIp": "10.22.8.1",  "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-19844", "vpuName": "PXLS2_19844 Lincoln Memorial (FL) - Sports Complex", "venueId": "5f0bdd24a91c834b287e0c91", "serial": "CZC9912NTL", "city": "Orlando",      "state": "FL", "uplinkIp": "10.18.4.50",  "gatewayIp": "10.18.4.1",  "swVersion": "5.13.4", "imageVersion": "26.02.003"},
    {"hostname": "PXLS2-27619", "vpuName": "PXLS2_27619 Northridge Prep (IL) - Fieldhouse",      "venueId": "6184e90f3d7c5e228f3ab472", "serial": "CZC8104WBQ", "city": "Chicago",      "state": "IL", "uplinkIp": "10.31.12.50", "gatewayIp": "10.31.12.1", "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-18203", "vpuName": "PXLS2_18203 Cedar Ridge (CO) - Performance Center",  "venueId": "60c2f1b8e84a5d3192058c6a", "serial": "CZC6502RJD", "city": "Denver",       "state": "CO", "uplinkIp": "10.55.20.50", "gatewayIp": "10.55.20.1", "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-34701", "vpuName": "PXLS2_34701 Pinecrest Academy (GA) - Stadium",       "venueId": "62a85b714c0f9d27ab1e6df3", "serial": "CZC9118MWE", "city": "Atlanta",      "state": "GA", "uplinkIp": "10.12.4.50",  "gatewayIp": "10.12.4.1",  "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-25618", "vpuName": "PXLS2_25618 Saguaro Heights (AZ) - West Court",      "venueId": "5e7c39d8d416a72594b30e85", "serial": "CZC7794KAV", "city": "Phoenix",      "state": "AZ", "uplinkIp": "10.66.8.50",  "gatewayIp": "10.66.8.1",  "swVersion": "5.13.4", "imageVersion": "26.02.003"},
    {"hostname": "PXLS2-29115", "vpuName": "PXLS2_29115 Harbor Bay HS (WA) - Aquatics Center",   "venueId": "6310aa56b9e1c4083f7d8290", "serial": "CZC8329LPB", "city": "Seattle",      "state": "WA", "uplinkIp": "10.77.16.50", "gatewayIp": "10.77.16.1", "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-21947", "vpuName": "PXLS2_21947 Magnolia Charter (LA) - Gymnasium",      "venueId": "612bf4c0a8351629d7f06ee4", "serial": "CZC6981XQH", "city": "Baton Rouge",  "state": "LA", "uplinkIp": "10.88.12.50", "gatewayIp": "10.88.12.1", "swVersion": "5.13.6", "imageVersion": "26.04.001"},
    {"hostname": "PXLS2-33028", "vpuName": "PXLS2_33028 Granite Peak (UT) - Field House",        "venueId": "5f8e6a3142b9d05c8773ec19", "serial": "CZC8866TRC", "city": "Salt Lake City", "state": "UT", "uplinkIp": "10.99.4.50",  "gatewayIp": "10.99.4.1",  "swVersion": "5.13.6", "imageVersion": "26.04.001"},
]
_VENUE = random.choice(_DEMO_VENUES)

# Uptime varies between 1-12 days for that "real VPU" feel — long enough
# to look stable, short enough not to trip the >30-day high-uptime finding.
_BOOT = time.time() - random.randint(1, 12) * 86400 - random.randint(0, 23) * 3600


def _uptime_secs():
    return int(time.time() - _BOOT)


def _fmt_uptime(s):
    d, r = divmod(s, 86400)
    h, r = divmod(r, 3600)
    m, _ = divmod(r, 60)
    return f"{d}d {h}h {m}m"


# Demo "game" state — chosen once per session so the full fetch and the
# live polls agree on scores. The clock is derived from wall-clock time so
# it ticks down realistically across live polls.
_DEMO_GAME = {
    "guest": random.randint(0, 35),
    "home": random.randint(0, 35),
    "quarter": random.randint(1, 4),
    "down": random.randint(1, 4),
    "to_go": random.randint(1, 15),
    "ball_on": random.randint(10, 50),
    "period_secs": 12 * 60,  # 12:00 quarters
    "anchor": time.time(),
}


def _demo_live_clock():
    """Count down from the period length based on wall-clock elapsed time,
    wrapping at 0 so the demo clock ticks forever."""
    elapsed = int(time.time() - _DEMO_GAME["anchor"])
    remaining = _DEMO_GAME["period_secs"] - (elapsed % _DEMO_GAME["period_secs"])
    return remaining // 60, remaining % 60


def _demo_raw_data():
    """Build a ScoreConnect CG raw string from the demo game state with a
    live (wall-clock-derived) game clock. Reproduces the real SC III
    FIXED-WIDTH byte layout exactly (verified against live VPU captures):

        "025728  25 38 42  33     3Home    Visitor R:S <chk>"
         pos 0-1  header "02"
         pos 2-5  clock (right-justified: "5728" or " 944" under 10:00)
         pos 8-9  field A (constant in tests)
         pos 11-12 HOME score
         pos 14-15 VISITOR score
         pos 18-19 field B (constant in tests)
         pos 25   quarter
         then Home/Visitor labels + clock-run flag + checksum
    """
    g = _DEMO_GAME
    minutes, seconds = _demo_live_clock()
    clock = f"{minutes}{seconds:02d}".rjust(4)   # "1225" or " 944"
    chk = f"00D3098DEBCE{random.randint(0, 0xFFFFFF):06X}"
    # Packed down/to-go/ball-on at pos 20-24: down(1) togo(2) ballon(2).
    dtb = f"{g['down']}{g['to_go']:02d}{g['ball_on']:02d}"
    # Field widths chosen so HOME lands at 11-12, VISITOR at 14-15,
    # timeouts at 18-19, down/dist at 20-24, quarter at 25.
    return (
        f"02{clock}  25 {g['home']:>2} {g['guest']:>2}  33{dtb}{g['quarter']}"
        f"Home    Visitor R:S {chk}"
    )


def _demo_scoreconnect_live():
    """Lightweight live-poll demo data — mirrors Get-ScoreConnectLive.ps1."""
    return {
        "reachable": True,
        "rawData": _demo_raw_data(),
        "dataStatus": "Data is present and in the correct format",
        "ts": datetime.now().isoformat(),
        "error": None,
    }


def _demo_scoreconnect():
    """Generate consistent ScoreConnect demo data.

    Simulates ScoreConnect III (web-based, raw RTD data only — no parsed
    scores).  SC II (web-based, has parsed data) and SC I (.exe, has parsed
    data) are different products with different API surfaces.

    Bot number is intentionally included but is notoriously stale on real
    hardware — SC III often reports a previous unit's number until reset.
    """
    has_data = True
    data_status = "Data is present and in the correct format"
    raw_data = _demo_raw_data() if has_data else None

    bot_id = str(random.randint(10000, 99999))
    bot_connected = random.choice([True, False])

    return {
        "reachable": True,
        "baseUrl": "http://localhost:5000",
        "version": "1.4.0.10",
        "dataStatus": data_status,
        "rawData": raw_data,
        "networkStatus": "Internet is detected",
        "hasLocalStream": has_data,  # local stream tracks data presence
        "configuration": {
            "vendor": "Daktronics",
            "sport": "Daktronics Football",
            "vendorConfigurationName": "Wireless",
        },
        "botStatus": {
            "isConnected": bot_connected,
            "scoreConnectId": bot_id,
            "botServerAddress": None,
            "lastErrorMessage": None,
        },
        "scoreLinkConnected": True,
        "scoreLinkPort": "COM7",
        "scoreLinkModel": "ScoreLink",
        "scoreLinkStatusLabel": "ScoreLink device connected (COM7)",
        "error": None,
        "sc2": {
            "reachable": True,
            "baseUrl": "http://localhost:1400",
            "version": "2.0.3.11",
            "hardware": "ScoreConnectII",
            "uid": "6C02E069700E",
            "scores": None,
            "teamNames": {
                "visitor": random.choice(["Eagles", "Warriors", "Knights", "Bulldogs"]),
                "home": random.choice(["Tigers", "Panthers", "Hawks", "Bears"]),
            },
            "vendor": "Daktronics Football",
            "sport": 2,
            "botNumber": 54025,
            "license": "07/01/2029",
            "scoreLink": {
                "description": "ScoreLinkII USB",
                "type": "ScoreLinkII",
                "address": "USB",
                "serial": "0000005B13C2",
            },
            "networkIfaces": [
                {"name": "Ethernet 44", "address": "192.168.111.184", "type": "Ethernet"},
                {"name": "Ethernet 55", "address": "169.254.79.80", "type": "Ethernet"},
            ],
            "statusLeds": None,
            "error": None,
        },
    }


DEMO = {
    "Get-SystemIdentity.ps1": lambda **kw: {
        "computerSystem": {"name": _VENUE["hostname"], "manufacturer": "HP", "model": "HP Z2 Tower G9 Workstation Desktop PC"},
        "bios": {"serialNumber": _VENUE["serial"]},
        "uptime": {"formatted": _fmt_uptime(_uptime_secs()), "totalSeconds": _uptime_secs()},
        # LTSC 2019 (1809, build 17763) — EOS Jan 2029, well clear of the EOL
        # warning window so the demo dashboard stays clean. (Older LTSC build
        # 19044 here used to trigger the "OS EOL approaching" finding.)
        "operatingSystem": {"caption": "Microsoft Windows 10 IoT Enterprise LTSC 2019", "version": "10.0.17763", "buildNumber": "17763", "osArchitecture": "64-bit", "installDate": "2024-01-15T08:00:00.0000000-05:00"},
        "pixellot": {
            "version": _VENUE["swVersion"],
            "imageVersion": _VENUE["imageVersion"],
            "vpuName": _VENUE["vpuName"],
            "venueId": _VENUE["venueId"],
        },
        "isNonVpuHost": False,
        "timezone": "(UTC-05:00) Eastern Time (US & Canada)",
        "timezoneId": "Eastern Standard Time",
        "locale": "en-US",
    },
    "Get-Performance.ps1": lambda **kw: {
        "cpu": {"usagePercent": round(28 + random.uniform(-8, 15), 1)},
        "memory": {"usedPercent": round(58 + random.uniform(-5, 10), 1), "totalGB": 16, "usedGB": round(9.3 + random.uniform(-0.5, 1.0), 1)},
        # All-fixed-volumes aggregate (C: ~62% of 465 GB + D: ~25% of 953 GB
        # ≈ 37%). Deliberately differs from C:'s own 62% so the demo reproduces
        # the real-VPU bug: the dashboard gauge must show C: (62%), not this
        # aggregate. See _systemDiskPct() in app.js.
        "disk": {"usedPercent": round(37 + random.uniform(-1, 2), 1)},
        "temperature": {"celsius": round(47 + random.uniform(-3, 8), 0)},
    },
    "Get-Services.ps1": lambda **kw: {
        # Core Pixellot components are PROCESSES in C:\Pixellot\Bin (kind=process),
        # not Windows services — detected by process, no SCM start type.
        # ScoreConnect + LogMeIn are real Windows services (kind=service).
        "services": [
            # ── Demo: Agent deliberately STOPPED to drive a single, narrative-
            # clean CRITICAL finding ("Pixellot Agent process not running").
            # This is the demo's "click finding → jump to tab → one-click
            # restart" moment. Flip back to "Running" if you want a fully-
            # green dashboard.
            {"name": "agent", "displayName": "Pixellot Agent", "status": "Stopped", "startType": None,
             "kind": "process", "pid": None, "path": "C:\\Pixellot\\Bin\\Agent.exe", "memoryMB": None, "watchdog": False},
            {"name": "coordinator", "displayName": "Pixellot Coordinator", "status": "Running", "startType": None,
             "kind": "process", "pid": 10596, "path": "C:\\Pixellot\\Bin\\Coordinator.exe", "memoryMB": 15, "watchdog": False},
            {"name": "vpu", "displayName": "Pixellot VPU", "status": "Running", "startType": None,
             "kind": "process", "pid": 12044, "path": "C:\\Pixellot\\Bin\\vpu.exe", "memoryMB": 240, "watchdog": False},
            {"name": "keepagentup", "displayName": "Pixellot Watchdog (KeepAgentUp)", "status": "Running", "startType": None,
             "kind": "process", "pid": 9940, "path": "C:\\Pixellot\\Bin\\KeepAgentUp.exe", "memoryMB": 9, "watchdog": True},
            {"name": "scoreconnect", "displayName": "ScoreConnect", "status": "Running", "startType": "Automatic",
             "kind": "service", "pid": None, "path": None, "memoryMB": None, "watchdog": False},
            {"name": "LogMeIn", "displayName": "LogMeIn Remote Access", "status": "Running", "startType": "Automatic",
             "kind": "service", "pid": None, "path": None, "memoryMB": None, "watchdog": False},
        ]
    },
    "Get-NicAdapters.ps1": lambda **kw: {
        "ports": [
            {"name": "Ethernet 1", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection", "status": "Up", "linkSpeedMbps": 1000, "fullDuplex": True, "mac": "A4:4C:C8:12:34:01",
             "rxBytes": 82749103726, "txBytes": 5283910234, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": [{"ip": "192.168.10.100", "mac": "00:0E:53:AA:01:01"}, {"ip": "192.168.10.101", "mac": "00:0E:53:AA:01:02"}, {"ip": "192.168.10.102", "mac": "00:0E:53:AA:01:03"}]},
            # Ethernet 2 deliberately negotiated to 100 Mbps with main-camera
            # MACs (00:0E:53 OUI). The new finding logic flags this as
            # degraded — the OCR-OUI heuristic only spares ports where every
            # Pixellot MAC is Dynacolor (00:D0:89).
            {"name": "Ethernet 2", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #2", "status": "Up", "linkSpeedMbps": 100, "fullDuplex": True, "mac": "A4:4C:C8:12:34:02",
             "rxBytes": 18238473625, "txBytes": 1283746281, "rxErrors": 187, "txErrors": 2, "rxPacketErrors": 187, "rxDiscards": 14, "txPacketErrors": 2, "txDiscards": 0,
             "arpEntries": [{"ip": "192.168.11.100", "mac": "00:0E:53:BB:02:01"}, {"ip": "192.168.11.101", "mac": "00:0E:53:BB:02:02"}]},
            # Ethernet 3 is the OCR / scoreboard camera. OCR cameras are
             # natively 100 Mbps, so this is HEALTHY (not degraded). Uses the
             # default-OCR link-local IP convention (169.254.16.52/53/60) so
             # the dashboard correctly identifies it as OCR and skips the
             # "below gigabit" warning for this port.
            {"name": "Ethernet 3", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #3", "status": "Up", "linkSpeedMbps": 100, "fullDuplex": True, "mac": "A4:4C:C8:12:34:03",
             "rxBytes": 1028374, "txBytes": 293847, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": [{"ip": "169.254.16.52", "mac": "00:D0:89:1B:03:01"}]},
            # Port 4 demoed as a dead link (cable unplugged) so the no-link
            # down-port tile + Fault Isolator no-link path are exercisable in
            # demo. status=Disconnected + adminStatus=Up + driver OK →
            # _derive_down_reason() == "no-link".
            {"name": "Ethernet 4 (Uplink)", "interfaceDescription": "Intel(R) I211 Gigabit Network Connection", "status": "Disconnected", "adminStatus": "Up", "mediaConnectionState": "Disconnected", "driverStatus": "OK", "linkSpeedMbps": 0, "fullDuplex": False, "mac": "A4:4C:C8:12:34:04",
             "rxBytes": 129384756012, "txBytes": 98273640182, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": []},
        ]
    },
    "Get-Hardware.ps1": lambda **kw: {
        "processors": [{"name": "Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz", "numberOfCores": 6, "numberOfLogicalProcessors": 12, "maxClockSpeedMHz": 3100}],
        "memory": [
            {"capacityGB": 16, "speedMHz": 3200, "memoryType": "DDR4", "deviceLocator": "DIMM_A1"},
            {"capacityGB": 16, "speedMHz": 3200, "memoryType": "DDR4", "deviceLocator": "DIMM_B1"},
        ],
        "gpus": [
            {"name": "Intel(R) UHD Graphics 630", "adapterRAMMB": 1024, "driverVersion": "27.20.100.8935",
             "adapterCompatibility": "Intel Corporation", "vendor": "Intel", "isDedicated": False},
            # Ampere-arch GPU (RTX 3060) so the Pixellot version × hardware
            # compat check passes — Ampere has no version cap. (Was GTX 1070
            # = Pascal, capped at 5.2.x, which conflicted with the 5.13.x
            # swVersion the demo venues use and produced a CRITICAL finding.)
            {"name": "NVIDIA GeForce RTX 3060", "adapterRAMMB": 12288, "driverVersion": "31.0.15.5212",
             "adapterCompatibility": "NVIDIA", "vendor": "NVIDIA", "isDedicated": True},
        ],
        "diskDrives": [
            {"model": "Samsung SSD 870 EVO 500GB", "sizeGB": 500, "interfaceType": "SATA", "serialNumber": "S3Z8NB0K901234A"}
        ],
    },
    "Get-InstalledSoftware.ps1": lambda **kw: {
        "count": 10,
        "software": [
            {"displayName": "Pixellot VPU Agent", "displayVersion": _VENUE["swVersion"], "publisher": "Pixellot Ltd."},
            {"displayName": "Pixellot VPU Engine", "displayVersion": _VENUE["swVersion"], "publisher": "Pixellot Ltd."},
            {"displayName": "Pixellot Encoder", "displayVersion": "3.8.0", "publisher": "Pixellot Ltd."},
            {"displayName": "Google Chrome", "displayVersion": "120.0.6099.130", "publisher": "Google LLC"},
            {"displayName": "LogMeIn", "displayVersion": "4.1.0.14083", "publisher": "LogMeIn, Inc."},
            {"displayName": "Microsoft Visual C++ 2019 Redistributable (x64)", "displayVersion": "14.29.30139", "publisher": "Microsoft"},
            {"displayName": "Microsoft .NET Runtime - 6.0.25", "displayVersion": "6.0.25", "publisher": "Microsoft"},
            {"displayName": "Intel(R) Network Connections", "displayVersion": "27.2", "publisher": "Intel"},
            {"displayName": "7-Zip 23.01 (x64)", "displayVersion": "23.01", "publisher": "Igor Pavlov"},
            {"displayName": "TightVNC", "displayVersion": "2.8.81", "publisher": "GlavSoft LLC."},
            # ── To exercise the "unsupported security software" or
            # "non-standard remote-access tool" findings, add (e.g.)
            # CrowdStrike Falcon Sensor or TeamViewer here. Kept OUT of the
            # default demo so the dashboard stays narrative-clean.
        ],
    },
    "Get-NetworkConfig.ps1": lambda **kw: {
        "adapters": [
            {"name": "Ethernet 4 (Uplink)", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #4", "status": "Up", "macAddress": "A0-36-9F-11-22-33", "linkSpeed": "1 Gbps", "interfaceIndex": 4},
            {"name": "Ethernet 1", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection", "status": "Up", "macAddress": "A0-36-9F-AA-BB-CC", "linkSpeed": "100 Mbps", "interfaceIndex": 1},
            {"name": "Ethernet 2", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #2", "status": "Up", "macAddress": "A0-36-9F-DD-EE-FF", "linkSpeed": "100 Mbps", "interfaceIndex": 2},
            {"name": "Ethernet 3", "interfaceDescription": "Intel(R) I350 Gigabit Network Connection", "status": "Down", "macAddress": "A0-36-9F-00-11-22", "linkSpeed": "", "interfaceIndex": 3},
        ],
        "ipConfigurations": [
            {"interfaceAlias": "Ethernet 4 (Uplink)", "interfaceIndex": 4, "ipv4Address": [_VENUE["uplinkIp"]], "ipv4DefaultGateway": [_VENUE["gatewayIp"]], "dnsServers": ["8.8.8.8", "8.8.4.4"], "dhcpEnabled": True, "prefixLength": 24},
            {"interfaceAlias": "Ethernet 1", "interfaceIndex": 1, "ipv4Address": ["192.168.10.1"], "ipv4DefaultGateway": [], "dnsServers": [], "dhcpEnabled": False, "prefixLength": 24},
            {"interfaceAlias": "Ethernet 2", "interfaceIndex": 2, "ipv4Address": ["192.168.11.1"], "ipv4DefaultGateway": [], "dnsServers": [], "dhcpEnabled": False, "prefixLength": 24},
            {"interfaceAlias": "Ethernet 3", "interfaceIndex": 3, "ipv4Address": ["192.168.12.1"], "ipv4DefaultGateway": [], "dnsServers": [], "dhcpEnabled": False, "prefixLength": 24},
        ],
        "uplinkAdapter": {"interfaceAlias": "Ethernet 4 (Uplink)", "gateway": _VENUE["gatewayIp"], "interfaceIndex": 4},
        "uplinkStats": {"fullDuplex": True, "rxBytes": 129384756012, "txBytes": 98273640182, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0},
        "internet": {"reachable": True, "testedHost": "8.8.8.8"},
        "ntpSource": "0.us.pool.ntp.org",
    },
    "Test-NetworkDomains.ps1": lambda **kw: {
        "results": [
            {"domain": "nfhsnetwork.com", "resolvedTo": "52.20.181.43", "status": "pass", "resolutionMs": round(random.uniform(8, 25), 1)},
            {"domain": "pixellot.tv", "resolvedTo": "52.20.181.44", "status": "pass", "resolutionMs": round(random.uniform(5, 18), 1)},
            {"domain": "software.pixellot.tv", "resolvedTo": "52.20.181.45", "status": "pass", "resolutionMs": round(random.uniform(6, 20), 1)},
            {"domain": "sportzcast.net", "resolvedTo": "104.26.11.87", "status": "pass", "resolutionMs": round(random.uniform(10, 35), 1)},
            {"domain": "service.singular.live", "resolvedTo": "76.76.21.21", "status": "pass", "resolutionMs": round(random.uniform(12, 40), 1)},
            {"domain": "logmein.com", "resolvedTo": "216.52.233.2", "status": "pass", "resolutionMs": round(random.uniform(5, 15), 1)},
            {"domain": "s3.amazonaws.com", "resolvedTo": "52.217.44.54", "status": "pass", "resolutionMs": round(random.uniform(4, 12), 1)},
            {"domain": "leaf-uploads.s3.amazonaws.com", "resolvedTo": "52.217.44.55", "status": "pass", "resolutionMs": round(random.uniform(6, 18), 1)},
            {"domain": "leaf-downloads.s3.amazonaws.com", "resolvedTo": None, "status": "fail", "resolutionMs": round(random.uniform(2000, 3000), 1)},
        ]
    },
    "Test-NetworkPorts.ps1": lambda **kw: {
        "results": [
            # Required — core Pixellot streaming + cloud services
            {"purpose": "DNS", "host": "8.8.8.8", "port": 53, "protocol": "UDP", "status": "pass", "optional": False},
            {"purpose": "Pixellot", "host": "pixellot.tv", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "Pixellot Echo", "host": "prod-echo.pixellot.tv", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "NFHS Network", "host": "nfhsnetwork.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "AWS S3", "host": "s3.amazonaws.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "Singular Overlay", "host": "service.singular.live", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "LogMeIn", "host": "secure.logmein.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "NTP", "host": "prod-echo.pixellot.tv", "port": 123, "protocol": "UDP", "status": "pass", "optional": False},
            {"purpose": "Zixi QUIC", "host": "prod-echo.pixellot.tv", "port": 443, "protocol": "UDP", "status": "pass", "optional": False},
            # Zixi (UDP 2088) is the streaming control channel. Passing in
            # the demo — flip to "fail" to exercise the required-port finding.
            {"purpose": "Zixi Streaming", "host": "prod-echo.pixellot.tv", "port": 2088, "protocol": "UDP", "status": "pass", "optional": False},
            # Optional — RTMP fallback (legacy ingest)
            {"purpose": "RTMP Ingest", "host": "sportzcast.net", "port": 1935, "protocol": "TCP", "status": "fail", "optional": True},
            # Optional — Sportzcast Scorebot range (ScoreConnect deployments only)
            {"purpose": "Scorebot", "host": "scorebot.sportzcast.net", "port": 1400, "protocol": "TCP", "status": "pass", "optional": True},
            {"purpose": "Scorebot", "host": "scorebot.sportzcast.net", "port": 1401, "protocol": "TCP", "status": "pass", "optional": True},
            {"purpose": "Scorebot", "host": "scorebot.sportzcast.net", "port": 1402, "protocol": "TCP", "status": "pass", "optional": True},
            {"purpose": "Scorebot", "host": "scorebot.sportzcast.net", "port": 1403, "protocol": "TCP", "status": "fail", "optional": True},
            {"purpose": "Scorebot", "host": "scorebot.sportzcast.net", "port": 1404, "protocol": "TCP", "status": "fail", "optional": True},
            {"purpose": "Scorebot", "host": "scorebot.sportzcast.net", "port": 1405, "protocol": "TCP", "status": "fail", "optional": True},
        ]
    },
    "Test-NtpDrift.ps1": lambda **kw: {"offsetSeconds": round(random.uniform(-0.3, 0.5), 3), "status": "ok", "source": "0.us.pool.ntp.org", "configuredSource": "0.us.pool.ntp.org", "networkSynced": True},
    "Get-NtpPeers.ps1": lambda **kw: {
        "status": {
            "source": "0.us.pool.ntp.org",
            "sourceIp": "23.186.168.130",
            "stratum": 2,
            "stratumText": "2 (secondary reference - syncd by (S)NTP)",
            "lastSync": (datetime.now() - timedelta(minutes=12)).strftime("%-m/%-d/%Y %-I:%M:%S %p"),
            "leapIndicator": "0(no warning)",
            "rootDelay": "0.0445007s",
            "rootDispersion": "7.7799853s",
            "pollInterval": "10 (1024s)",
        },
        "peers": [
            {
                "name": "0.us.pool.ntp.org",
                "state": "Active",
                "timeRemaining": "534.1234567s",
                "mode": "3 (Client)",
                "stratum": 2,
                "stratumText": "2 (secondary reference - syncd by (S)NTP)",
                "peerPollInterval": "10 (1024s)",
                "hostPollInterval": "10 (1024s)",
                "lastSyncTimestamp": (datetime.now() - timedelta(minutes=12)).strftime("%-m/%-d/%Y %-I:%M:%S %p"),
            },
        ],
    },
    "Get-WifiAdapters.ps1": lambda **kw: {
        # Realistic wired VPU: a Wi-Fi Direct *virtual* adapter is present and
        # shows "connected" (Windows always carries one), but Ethernet holds
        # the default route. uplinkIsWifi=False, so NO warning fires — this is
        # the false-positive case the finding must not trip on.
        "anyActive": False,
        "activeCount": 0,
        "ethernetHasDefaultRoute": True,
        "uplinkIsWifi": False,
        "adapters": [
            {
                "name": "Local Area Connection* 2",
                "interfaceAlias": "Local Area Connection* 2",
                "interfaceDescription": "Microsoft Wi-Fi Direct Virtual Adapter #2",
                "macAddress": "B8-9A-2A-4C-7D-13",
                "linkSpeed": "0 bps",
                "status": "Up",
                "isUp": True,
                "isVirtual": True,
                "hasDefaultRoute": False,
                "connected": True,
                "ssid": "DIRECT-3a-DESKTOP",
                "networkCategory": "Public",
                "ipv4Connectivity": "NoTraffic",
                "ipv6Connectivity": "NoTraffic",
            },
        ],
    },
    # Raw resolution rows only — the backend (_classify_dns_row) decides what
    # counts as a discrepancy. The pixellot/CDN rows return *different public*
    # IPs (the real screenshot values) which is benign CDN/GeoDNS balancing
    # and must NOT warn; www.pixellot.tv is system-blocked (a real finding).
    "Test-DnsResolution.ps1": lambda **kw: {
        "googleServer": "8.8.8.8",
        "results": [
            {"host": "www.pixellot.tv",
             "system": {"resolvedTo": None,             "status": "fail", "resolutionMs": round(random.uniform(2000, 3000), 1), "error": "No such host is known."},
             "google": {"resolvedTo": "52.1.53.61",     "status": "pass", "resolutionMs": round(random.uniform(8, 20), 1),       "error": None}},
            {"host": "pixellot.tv",
             "system": {"resolvedTo": "52.44.182.199",  "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "52.1.53.61",     "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None}},
            {"host": "software.pixellot.tv",
             "system": {"resolvedTo": "143.204.160.127", "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "143.204.160.99",  "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None}},
            {"host": "nfhsnetwork.com",
             "system": {"resolvedTo": "143.204.160.62",  "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "143.204.160.113", "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None}},
            {"host": "s3.amazonaws.com",
             "system": {"resolvedTo": "16.15.254.35",   "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "52.216.26.198",  "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None}},
        ],
    },
    "Test-LocalNetwork.ps1": lambda **kw: {
        "gateway": {"target": _VENUE["gatewayIp"], "label": "Gateway", "reachable": True, "sent": 4, "received": 4, "lossPercent": 0, "minMs": 1, "avgMs": 2, "maxMs": 4, "status": "pass"},
        "dns": {"target": "8.8.8.8", "label": "DNS Server", "reachable": True, "sent": 4, "received": 4, "lossPercent": 0, "minMs": 8, "avgMs": 12, "maxMs": 18, "status": "pass"},
    },
    "Get-DiskHealth.ps1": lambda **kw: {
        "logicalDisks": [
            {"deviceID": "C:", "freeSpaceGB": 176, "sizeGB": 465, "usedPercent": 62, "fileSystem": "NTFS"},
            {"deviceID": "D:", "freeSpaceGB": 712, "sizeGB": 953, "usedPercent": 25, "fileSystem": "NTFS"},
        ],
        "physicalDisks": [
            {"friendlyName": "Generic HDD", "sizeGB": 500, "mediaType": "HDD", "busType": "SATA", "serialNumber": "S3Z8NB0K901234A", "healthStatus": "Healthy"}
        ],
        "pixellotPaths": [
            {"path": "C:\\Pixellot", "sizeGB": 12.4, "fileCount": 847},
            {"path": "D:\\Recordings", "sizeGB": 198.7, "fileCount": 3241},
            {"path": "D:\\Uploads", "sizeGB": 22.1, "fileCount": 156},
        ],
        "diskEvents": [{"timeCreated": (datetime.now() - timedelta(hours=6)).isoformat(), "level": "Warning", "source": "Ntfs", "eventId": 55, "message": "The file system structure on the disk is corrupt. Run chkdsk on volume D:"}],
    },
    "Get-EventLogs.ps1": lambda **kw: {
        "entries": [
            {"timeCreated": (datetime.now() - timedelta(hours=2)).isoformat(), "level": "Error", "source": "PixellotAgent", "eventId": 1001, "message": "Connection timeout to cloud service api.pixellot.tv — retrying in 30s"},
            {"timeCreated": (datetime.now() - timedelta(hours=3)).isoformat(), "level": "Warning", "source": "PixellotEncoder", "eventId": 2010, "message": "Encoder buffer underrun on Camera1 stream — 2 frames dropped"},
            {"timeCreated": (datetime.now() - timedelta(hours=5)).isoformat(), "level": "Error", "source": "Service Control Manager", "eventId": 7034, "message": "The PixellotWatchdog service terminated unexpectedly."},
            {"timeCreated": (datetime.now() - timedelta(hours=8)).isoformat(), "level": "Info", "source": "PixellotAgent", "eventId": 1000, "message": "Agent connected to cloud service successfully"},
            {"timeCreated": (datetime.now() - timedelta(hours=12)).isoformat(), "level": "Warning", "source": "PixellotVPU", "eventId": 3005, "message": "Camera2 stream quality degraded — switching to fallback bitrate"},
            {"timeCreated": (datetime.now() - timedelta(hours=24)).isoformat(), "level": "Error", "source": "PixellotEncoder", "eventId": 2001, "message": "Hardware encoder init failed — falling back to software encoding"},
        ]
    },
    "Get-ScoreConnectStatus.ps1": lambda **kw: _demo_scoreconnect(),
    "Get-ScoreConnectLive.ps1": lambda **kw: _demo_scoreconnect_live(),
    "Get-ScoreLinkStatus.ps1": lambda **kw: {
        "connected": True, "port": "COM7", "model": "ScoreLink",
        "statusLabel": "ScoreLink device connected (COM7)",
    },
    "Get-PixellotConfig.ps1": lambda **kw: {
        "cameras": [
            {"section": "Camera1", "ip": "192.168.10.100", "mac": "00:0E:53:AA:01:01", "role": "Main"},
            {"section": "Camera2", "ip": "192.168.10.101", "mac": "00:0E:53:AA:01:02", "role": "Panoramic"},
            {"section": "Camera3", "ip": "192.168.10.102", "mac": "00:0E:53:AA:01:03", "role": "Tactical"},
            {"section": "Camera4", "ip": "192.168.11.100", "mac": "00:0E:53:BB:02:01", "role": "Main"},
            {"section": "Camera5", "ip": "192.168.11.101", "mac": "00:0E:53:BB:02:02", "role": "Panoramic"},
            {"section": "OCR", "ip": "192.168.12.50", "mac": "00:D0:89:1B:03:01", "role": "OCR"},
        ],
    },
    # Expected main-camera count from the Coordinator log. Demo box is an
    # S2 (2 main cameras + 1 OCR), matching the Get-PixellotConfig demo.
    # vpuRunning False → idle box, so frame capture is allowed in demo.
    "Get-CameraExpectations.ps1": lambda **kw: {
        "expectedMainCameras": 2,
        "systemType": "S2",
        "vpuRunning": False,
    },
    # JAI S1 camera discovery. The demo box is a standard Dynacolor system,
    # so no S1 cameras — mirror what a non-S1 VPU returns (SDK absent).
    "Get-S1Cameras.ps1": lambda **kw: {
        "available": False,
        "reason": "JAI SDK not found (Jai_FactoryDotNet.dll absent). This VPU is not an S1 system.",
        "count": 0,
        "cameras": [],
    },
    # Single-frame capture. Demo returns plausible per-camera results with
    # placeholder thumbnail frames (one camera intentionally not streaming)
    # so the snapshot UI can be exercised without real ffmpeg.
    "Test-CameraVideo.ps1": lambda **kw: {
        "available": True,
        "results": [
            {"ip": "192.168.10.100", "label": "Main Camera 1", "ok": True,
             "codec": "h264", "frameRate": 30.0, "resolution": "3840x2160",
             "image": _demo_frame("Main Camera 1", "#1f3a5f"), "error": None},
            {"ip": "192.168.11.100", "label": "Main Camera 2", "ok": True,
             "codec": "h264", "frameRate": 30.0, "resolution": "3840x2160",
             "image": _demo_frame("Main Camera 2", "#244a36"), "error": None},
            {"ip": "169.254.16.52", "label": "OCR", "ok": False,
             "codec": None, "frameRate": None, "resolution": None, "image": None,
             "error": "No frame captured (camera not streaming on rtsp://169.254.16.52/stream1)."},
        ],
    },
    "Get-NetworkHealth.ps1": lambda **kw: {
        "tcp": {
            "retransmitsSec": round(random.uniform(0, 3.5), 2),
            "connFailures": random.randint(0, 4),
            "connResets": random.randint(0, 2),
            "established": random.randint(12, 22),
            "segsOutSec": random.randint(800, 3000),
            "segsInSec": random.randint(2000, 8000),
        },
        # Match the real script: no remoteHost (reverse DNS removed for poll-loop speed).
        "connections": [
            {"localPort": 49201, "remoteAddr": "52.20.181.44", "remotePort": 443, "state": "Established", "pid": 4120},
            {"localPort": 49205, "remoteAddr": "52.20.181.45", "remotePort": 443, "state": "Established", "pid": 4120},
            {"localPort": 49210, "remoteAddr": "52.20.181.46", "remotePort": 1935, "state": "Established", "pid": 5230},
            {"localPort": 49215, "remoteAddr": "52.217.44.54", "remotePort": 443, "state": "Established", "pid": 4120},
            {"localPort": 49220, "remoteAddr": "76.76.21.21", "remotePort": 443, "state": "Established", "pid": 6010},
            {"localPort": 49225, "remoteAddr": "216.52.233.2", "remotePort": 443, "state": "TimeWait", "pid": 0},
        ],
        "nics": [
            {"name": "intel[r] i210 gigabit network connection", "queueLen": 0, "rxErrors": 0, "txErrors": 0, "rxPktSec": random.randint(1500, 4000), "txPktSec": random.randint(200, 800)},
            {"name": "intel[r] i210 gigabit network connection _2", "queueLen": 0, "rxErrors": 0, "txErrors": 0, "rxPktSec": random.randint(800, 2000), "txPktSec": random.randint(100, 400)},
            {"name": "intel[r] i211 gigabit network connection", "queueLen": 0, "rxErrors": 0, "txErrors": 0, "rxPktSec": random.randint(400, 1200), "txPktSec": random.randint(1000, 4000)},
        ],
    },
    "Start-NetworkCapture.ps1": lambda **kw: {
        "durationSec": int((kw or {}).get("DurationSec", 30)),
        "totalPackets": random.randint(1800, 4200),
        "droppedPackets": 0,
        "tcpRetransmits": random.randint(0, 6),
        "tcpResets": random.randint(0, 3),
        "tcpSyns": random.randint(40, 120),
        "tcpFins": random.randint(20, 60),
        "components": [
            {"name": "Intel(R) I211 Gigabit Network Connection", "packets": random.randint(1500, 3500), "drops": 0},
            {"name": "Intel(R) I210 Gigabit Network Connection", "packets": random.randint(200, 800), "drops": 0},
        ],
        "topTalkers": [
            {"remoteAddr": "52.20.181.46", "remotePort": 1935, "remoteHost": "live.pixellot.tv", "packets": random.randint(600, 1500)},
            {"remoteAddr": "52.217.44.54", "remotePort": 443, "remoteHost": "s3.amazonaws.com", "packets": random.randint(300, 800)},
            {"remoteAddr": "52.20.181.44", "remotePort": 443, "remoteHost": "api.pixellot.tv", "packets": random.randint(100, 400)},
            {"remoteAddr": "52.20.181.45", "remotePort": 443, "remoteHost": "cloud.pixellot.tv", "packets": random.randint(80, 300)},
            {"remoteAddr": "76.76.21.21", "remotePort": 443, "remoteHost": "service.singular.live", "packets": random.randint(20, 80)},
        ],
        "findings": [
            {"severity": "pass", "title": "No issues detected", "body": "Captured ~3000 packets over 30s with no retransmissions, resets, or drops."},
        ],
    },
    "Test-Traceroute.ps1": lambda **kw: {
        "target": (kw or {}).get("Target", "pixellot.tv"),
        "targetIp": "52.20.181.44",
        "reached": True,
        "hops": [
            {"hop": 1, "ip": _VENUE["gatewayIp"], "hostname": "gateway.local", "rttMs": 1, "status": "transit"},
            {"hop": 2, "ip": "172.16.0.1", "hostname": None, "rttMs": 3, "status": "transit"},
            {"hop": 3, "ip": "10.200.0.1", "hostname": "core-rtr-1.isp.net", "rttMs": 8, "status": "transit"},
            {"hop": 4, "ip": None, "hostname": None, "rttMs": None, "status": "timeout"},
            {"hop": 5, "ip": "72.14.215.85", "hostname": "edge-1.isp.net", "rttMs": 12, "status": "transit"},
            {"hop": 6, "ip": "108.170.248.33", "hostname": None, "rttMs": 15, "status": "transit"},
            {"hop": 7, "ip": "142.251.78.29", "hostname": None, "rttMs": 18, "status": "transit"},
            {"hop": 8, "ip": "52.20.181.44", "hostname": "ec2-52-20-181-44.compute-1.amazonaws.com", "rttMs": 22, "status": "reached"},
        ],
        "hopCount": 8,
    },
    "Restart-Service.ps1": lambda **kw: {"success": True, "message": "Service restarted successfully (demo)"},
    "Search-PixellotLogs.ps1": lambda **kw: {
        "entries": [
            {"file": "vpu_2026-05-27.log", "lineNumber": 1452,
             "level": "restart", "timestamp": "2026-05-27 14:22:11",
             "content": "[2026-05-27 14:22:11] start new log — process restart detected",
             "fileMTime": (datetime.now() - timedelta(hours=6)).isoformat(),
             "depsError": False},
            {"file": "vpu_2026-05-27.log", "lineNumber": 1453,
             "level": "fatal", "timestamp": "2026-05-27 14:22:11",
             "content": "[2026-05-27 14:22:11] FATAL: CUDNN_STATUS_EXECUTION_FAILED at inference step",
             "fileMTime": (datetime.now() - timedelta(hours=6)).isoformat(),
             "depsError": True},
            {"file": "vpu_2026-05-27.log", "lineNumber": 1454,
             "level": "error", "timestamp": "2026-05-27 14:22:12",
             "content": "[2026-05-27 14:22:12] ERROR: TensorFlow runtime initialization failed — falling back",
             "fileMTime": (datetime.now() - timedelta(hours=6)).isoformat(),
             "depsError": True},
            {"file": "agent_vpu2_2026-05-27.log", "lineNumber": 87,
             "level": "error", "timestamp": "2026-05-27 12:08:43",
             "content": "[2026-05-27 12:08:43] ERROR: failed to upload chunk 481 to leaf-uploads.s3.amazonaws.com (HTTP 503)",
             "fileMTime": (datetime.now() - timedelta(hours=8)).isoformat(),
             "depsError": False},
            {"file": "agent_vpu2_2026-05-27.log", "lineNumber": 42,
             "level": "restart", "timestamp": "2026-05-27 09:14:02",
             "content": "[2026-05-27 09:14:02] start new log — agent service initialized",
             "fileMTime": (datetime.now() - timedelta(hours=11)).isoformat(),
             "depsError": False},
        ],
        "stats": {"error": 2, "fatal": 1, "restart": 2, "total": 5},
        "depsErrorDetected": True,
        "scannedFiles": 2,
        "hoursBack": int((kw or {}).get("HoursBack", 24)),
        "truncated": False,
    },
    "Invoke-RepairTool.ps1": lambda **kw: (lambda action: {
        "action": action,
        "success": True,
        "exitCode": 0,
        "timedOut": False,
        "durationMs": {"CheckHealth": 32000, "RestoreHealth": 480000, "SfcScan": 540000, "ChkdskSchedule": 1200}.get(action, 5000),
        "command": {
            "CheckHealth": "dism.exe /Online /Cleanup-Image /CheckHealth",
            "RestoreHealth": "dism.exe /Online /Cleanup-Image /RestoreHealth",
            "SfcScan": "sfc.exe /scannow",
            "ChkdskSchedule": "cmd.exe /c echo Y | chkdsk C: /f /r",
        }.get(action, "?"),
        "stdout": {
            "CheckHealth": "Deployment Image Servicing and Management tool\nVersion: 10.0.19041.844\n\nImage Version: 10.0.19044.4046\n\n[==========================100.0%==========================]\nNo component store corruption detected.\nThe operation completed successfully.",
            "RestoreHealth": "Deployment Image Servicing and Management tool\nVersion: 10.0.19041.844\n\nImage Version: 10.0.19044.4046\n\n[==========================100.0%==========================]\nThe restore operation completed successfully.",
            "SfcScan": "Beginning system scan. This process will take some time.\n\nBeginning verification phase of system scan.\nVerification 100% complete.\n\nWindows Resource Protection did not find any integrity violations.",
            "ChkdskSchedule": "The type of the file system is NTFS.\nCannot lock current drive.\n\nChkdsk cannot run because the volume is in use by another process.\nWould you like to schedule this volume to be checked the next time the system restarts? (Y/N) y\n\nThis volume will be checked the next time the system restarts.",
        }.get(action, ""),
        "stderr": "",
        "cbsTail": [
            "2026-05-27 14:22:01, Info                  CSI    00000001 IAdvancedInstallerAwareStore_ResolvePendingTransactions called (call 1, sequence 3)",
            "2026-05-27 14:22:02, Info                  CSI    00000002@2026/5/27:18:22:02.123 CSI Transaction @0x... initialized for deployment engine with flags 00000001",
            "2026-05-27 14:22:03, Info                  CSI    00000003 Components: Reading installer dependencies (deployment engine 7.4.13)",
            "2026-05-27 14:25:48, Info                  CSI    000000a4 No corrupt component-store payload detected. Image scan completed.",
            "2026-05-27 14:25:48, Info                  CSI    000000a5 Repair operation completed. Result: 0x0",
        ],
        "cbsLogPath": "C:\\Windows\\Logs\\CBS\\CBS.log",
    })((kw or {}).get("Action", "CheckHealth")),
    "Get-GpuInfo.ps1": lambda **kw: {
        # Ampere-arch GPU (RTX 3060) — no Pixellot version cap, so the
        # compat check passes cleanly for the demo. Was a Pascal GTX 1070
        # which conflicted with the demo venues' 5.13.x Pixellot version
        # and produced a noisy CRITICAL finding for the presentation.
        # (Flip to Pascal/GTX 1070 + computeCap 6.1 to exercise the cap.)
        "gpus": [
            {"name": "Intel(R) UHD Graphics 630", "computeCap": None, "architecture": "NotNvidia", "source": "wmi"},
            {"name": "NVIDIA GeForce RTX 3060", "computeCap": "8.6", "architecture": "Ampere/Ada", "source": "nvidia-smi"},
        ],
        "primaryArchitecture": "Ampere/Ada",
        "primaryComputeCap": "8.6",
        "nvidiaSmiAvailable": True,
        "nvidiaSmiError": None,
    },
    "Get-PixellotDependencies.ps1": lambda **kw: {
        # Demo shows an outdated 4.8.0 install so the "outdated" badge state
        # is visible in demo mode. Real VPUs that ran PDF #2's reinstall
        # action would report 5.0.0 → "current".
        "installedVersion": "4.8.0",
        "latestKnownVersion": "5.0.0",
        "status": "outdated",
        "registryKey": "HKLM:\\SOFTWARE\\Pixellot",
        "registryValueName": "dependencies",
        "registryKeyPresent": True,
    },
    "Test-PixellotInstallState.ps1": lambda **kw: {
        "dirExists": True,
        "dir": "C:\\pixellot\\downloadedversion",
        "incomplete": False,
        "rebooting": True,
        "partFiles": [],
        "partCount": 0,
        "log": {
            "path": "C:\\pixellot\\downloadedversion\\install_log_2026-05-26.log",
            "name": "install_log_2026-05-26.log",
            "sizeKB": 42.1,
            "lastWrite": (datetime.now() - timedelta(days=2, hours=3)).isoformat(),
            "lastLine": "Install completed successfully. Rebooting...",
        },
        "message": "Last install completed cleanly. No part files remain.",
    },
    "Install-PixellotDependencies.ps1": lambda **kw: {
        "success": True,
        "targetDir": "C:\\pixellot\\downloadedversion",
        "targetFile": "C:\\pixellot\\downloadedversion\\Pixellot-Installer-Dependencies-5.0.0.exe",
        "installerUrl": "https://software.pixellot.tv/apps/Pixellot-Installer-Dependencies-5.0.0.exe",
        "steps": [
            {"label": "Download installer", "status": "ok",
             "detail": "Downloaded 87.4 MB via curl.exe to C:\\pixellot\\downloadedversion\\Pixellot-Installer-Dependencies-5.0.0.exe",
             "durationMs": 28400, "ts": datetime.now().isoformat()},
            {"label": "Run installer", "status": "ok",
             "detail": "Exit code 0 after 142s",
             "durationMs": 142000, "ts": datetime.now().isoformat()},
        ],
        "message": "Pixellot dependencies installer completed. Reboot recommended.",
    },
    "Restart-PixellotAgent.ps1": lambda **kw: {
        "success": True,
        "exitCode": 0,
        "path": "C:\\pixellot\\bin\\keepagentup.exe",
        "stdout": "Agent service started.\nCoordinator service started.\nAll Pixellot services up.",
        "stderr": "",
        "agentStatus": "Running",
        "coordinatorStatus": "Running",
        "message": "keepagentup.exe completed successfully (demo)",
    },
    "Get-AudioDevices.ps1": lambda **kw: {
        "devices": [
            {
                "id": "{0.0.1.00000000}.{a1b2c3d4-1111-2222-3333-444455556666}",
                "name": "Line In (Realtek High Definition Audio)",
                "dataFlow": "Input",
                "state": "Active",
                "formFactor": "LineLevel",
                "volume": 78,
                "muted": False,
                # Stays clearly above signal threshold (1%) so the "Signal
                # Detected" indicator doesn't flicker between frames.
                "peak": round(random.uniform(12, 32), 1),
            },
            {
                "id": "{0.0.1.00000000}.{a1b2c3d4-1111-2222-3333-444455557777}",
                "name": "Microphone (Realtek High Definition Audio)",
                "dataFlow": "Input",
                "state": "Active",
                "formFactor": "Microphone",
                "volume": 62,
                "muted": True,  # Demonstrates the muted-slider state
                "peak": round(random.uniform(0, 0.8), 1),  # always below threshold
            },
            {
                "id": "{0.0.1.00000000}.{a1b2c3d4-1111-2222-3333-444455558888}",
                "name": "Stereo Mix (Realtek High Definition Audio)",
                "dataFlow": "Input",
                "state": "Disabled",
                "formFactor": "Unknown",
                "volume": None,
                "muted": None,
                "peak": None,
            },
            {
                "id": "{0.0.0.00000000}.{b2c3d4e5-2222-3333-4444-555566667777}",
                "name": "Speakers (Realtek High Definition Audio)",
                "dataFlow": "Output",
                "state": "Active",
                "formFactor": "Speakers",
                "volume": 45,
                "muted": False,
                "peak": round(random.uniform(2, 8), 1),  # clearly above threshold
            },
            {
                "id": "{0.0.0.00000000}.{b2c3d4e5-2222-3333-4444-555566668888}",
                "name": "HDMI Audio (Intel Display Audio)",
                "dataFlow": "Output",
                "state": "Unplugged",
                "formFactor": "DigitalDisplay",
                "volume": None,
                "muted": None,
                "peak": None,
            },
        ],
        "inputCount": 2,
        "outputCount": 1,
    },
    "Set-AudioVolume.ps1": lambda **kw: {"success": True, "deviceId": (kw or {}).get("DeviceId", ""), "volume": int((kw or {}).get("Volume", 50))},
}


def get_demo(script_name, args=None):
    fn = DEMO.get(script_name)
    if fn is None:
        return None
    return fn(**(args or {}))
