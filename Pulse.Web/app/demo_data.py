"""Mock data for non-Windows demo mode."""

import random
import time
from datetime import datetime, timedelta

# ── Demo venue identity ──────────────────────────────────────
# Picked once at module load so all scripts return consistent data
# for a single Pulse session. Each session re-imports → fresh pick.
# The pool is small + curated so demos look like real Pixellot
# venues without ever showing actual customer data.
_DEMO_VENUES = [
    {
        "hostname":     "PXLS2-31402",
        "vpuName":      "PXLS2_31402 Westfield Academy (TX) - Gymnasium",
        "serial":       "CZC8847PQR",
        "city":         "Houston",
        "state":        "TX",
        "uplinkIp":     "10.40.16.50",
        "gatewayIp":    "10.40.16.1",
        "swVersion":    "5.13.6",
        "imageVersion": "26.04.001",
    },
    {
        "hostname":     "PXLS2-22158",
        "vpuName":      "PXLS2_22158 Roosevelt High School (CA) - Main Court",
        "serial":       "CZC7235HXM",
        "city":         "Riverside",
        "state":        "CA",
        "uplinkIp":     "10.22.8.50",
        "gatewayIp":    "10.22.8.1",
        "swVersion":    "5.13.6",
        "imageVersion": "26.04.001",
    },
    {
        "hostname":     "PXLS2-19844",
        "vpuName":      "PXLS2_19844 Lincoln Memorial (FL) - Sports Complex",
        "serial":       "CZC9912NTL",
        "city":         "Orlando",
        "state":        "FL",
        "uplinkIp":     "10.18.4.50",
        "gatewayIp":    "10.18.4.1",
        "swVersion":    "5.13.4",
        "imageVersion": "26.02.003",
    },
    {
        "hostname":     "PXLS2-27619",
        "vpuName":      "PXLS2_27619 Northridge Prep (IL) - Fieldhouse",
        "serial":       "CZC8104WBQ",
        "city":         "Chicago",
        "state":        "IL",
        "uplinkIp":     "10.31.12.50",
        "gatewayIp":    "10.31.12.1",
        "swVersion":    "5.13.6",
        "imageVersion": "26.04.001",
    },
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


DEMO = {
    "Get-SystemIdentity.ps1": lambda **kw: {
        "computerSystem": {"name": _VENUE["hostname"], "manufacturer": "HP", "model": "HP Z2 Tower G9 Workstation Desktop PC"},
        "bios": {"serialNumber": _VENUE["serial"]},
        "uptime": {"formatted": _fmt_uptime(_uptime_secs()), "totalSeconds": _uptime_secs()},
        "operatingSystem": {"caption": "Microsoft Windows 10 IoT Enterprise LTSC", "version": "10.0.19044", "buildNumber": "19044", "osArchitecture": "64-bit"},
        "pixellot": {
            "version": _VENUE["swVersion"],
            "imageVersion": _VENUE["imageVersion"],
            "vpuName": _VENUE["vpuName"],
        },
        "isNonVpuHost": False,
        "timezone": "(UTC-05:00) Eastern Time (US & Canada)",
        "timezoneId": "Eastern Standard Time",
    },
    "Get-Performance.ps1": lambda **kw: {
        "cpu": {"usagePercent": round(28 + random.uniform(-8, 15), 1)},
        "memory": {"usedPercent": round(58 + random.uniform(-5, 10), 1), "totalGB": 16, "usedGB": round(9.3 + random.uniform(-0.5, 1.0), 1)},
        "disk": {"usedPercent": round(62 + random.uniform(-1, 2), 1)},
        "temperature": {"celsius": round(47 + random.uniform(-3, 8), 0)},
    },
    "Get-Services.ps1": lambda **kw: {
        "services": [
            {"name": "agent", "displayName": "Pixellot Agent", "status": "Running", "startType": "Automatic"},
            {"name": "coordinator", "displayName": "Pixellot Coordinator", "status": "Running", "startType": "Automatic"},
            {"name": "vpu", "displayName": "Pixellot VPU", "status": "Running", "startType": "Automatic"},
            {"name": "scoreconnect", "displayName": "ScoreConnect", "status": "Running", "startType": "Automatic"},
            {"name": "LogMeIn", "displayName": "LogMeIn Remote Access", "status": "Stopped", "startType": "Manual"},
        ]
    },
    "Get-NicAdapters.ps1": lambda **kw: {
        "ports": [
            {"name": "Ethernet 1", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection", "status": "Up", "linkSpeedMbps": 1000, "fullDuplex": True, "mac": "A4:4C:C8:12:34:01",
             "rxBytes": 82749103726, "txBytes": 5283910234, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": [{"ip": "192.168.10.100", "mac": "00:0E:53:AA:01:01"}, {"ip": "192.168.10.101", "mac": "00:0E:53:AA:01:02"}, {"ip": "192.168.10.102", "mac": "00:0E:53:AA:01:03"}]},
            {"name": "Ethernet 2", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #2", "status": "Up", "linkSpeedMbps": 1000, "fullDuplex": True, "mac": "A4:4C:C8:12:34:02",
             "rxBytes": 41029384756, "txBytes": 2938475610, "rxErrors": 3, "txErrors": 0, "rxPacketErrors": 3, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": [{"ip": "192.168.11.100", "mac": "00:0E:53:BB:02:01"}, {"ip": "192.168.11.101", "mac": "00:0E:53:BB:02:02"}]},
            {"name": "Ethernet 3", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #3", "status": "Up", "linkSpeedMbps": 100, "fullDuplex": True, "mac": "A4:4C:C8:12:34:03",
             "rxBytes": 1028374, "txBytes": 293847, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": [{"ip": "192.168.12.50", "mac": "00:D0:89:1B:03:01"}]},
            {"name": "Ethernet 4 (Uplink)", "interfaceDescription": "Intel(R) I211 Gigabit Network Connection", "status": "Up", "linkSpeedMbps": 1000, "fullDuplex": True, "mac": "A4:4C:C8:12:34:04",
             "rxBytes": 129384756012, "txBytes": 98273640182, "rxErrors": 0, "txErrors": 0, "rxPacketErrors": 0, "rxDiscards": 0, "txPacketErrors": 0, "txDiscards": 0,
             "arpEntries": [{"ip": _VENUE["gatewayIp"], "mac": "00:1A:2B:3C:4D:5E"}]},
        ]
    },
    "Get-Hardware.ps1": lambda **kw: {
        "processors": [{"name": "Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz", "numberOfCores": 6, "numberOfLogicalProcessors": 12, "maxClockSpeedMHz": 3100}],
        "memory": [
            {"capacityGB": 16, "speedMHz": 3200, "memoryType": "DDR4", "deviceLocator": "DIMM_A1"},
            {"capacityGB": 16, "speedMHz": 3200, "memoryType": "DDR4", "deviceLocator": "DIMM_B1"},
        ],
        "gpus": [
            {"name": "Intel(R) UHD Graphics 630", "adapterRAMMB": 1024, "driverVersion": "27.20.100.8935"},
            {"name": "NVIDIA GeForce GTX 1650", "adapterRAMMB": 4096, "driverVersion": "32.0.15.7628"},
        ],
        "diskDrives": [
            {"model": "Samsung SSD 870 EVO 500GB", "sizeGB": 500, "interfaceType": "SATA", "serialNumber": "S3Z8NB0K901234A"}
        ],
    },
    "Get-InstalledSoftware.ps1": lambda **kw: {
        "count": 18,
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
            # Triggers PDF #11 banned-AV finding on the dashboard.
            {"displayName": "CrowdStrike Falcon Sensor", "displayVersion": "7.18.16805.0", "publisher": "CrowdStrike, Inc."},
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
        "ntpSource": "time.windows.com",
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
            # Required
            {"purpose": "DNS", "host": "8.8.8.8", "port": 53, "protocol": "UDP", "status": "pass", "optional": False},
            {"purpose": "Pixellot", "host": "pixellot.tv", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "NFHS Network", "host": "nfhsnetwork.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "AWS S3", "host": "s3.amazonaws.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "Singular Overlay", "host": "service.singular.live", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "LogMeIn", "host": "logmein.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "NTP", "host": "prod-echo.pixellot.tv", "port": 123, "protocol": "UDP", "status": "pass", "optional": False},
            {"purpose": "Zixi Streaming", "host": "pixellot.tv", "port": 2088, "protocol": "UDP", "status": "pass", "optional": False},
            # Optional
            {"purpose": "RTMP Ingest", "host": "sportzcast.net", "port": 1935, "protocol": "TCP", "status": "fail", "optional": True},
            {"purpose": "SportzCast", "host": "sportzcast.net", "port": 1402, "protocol": "TCP", "status": "fail", "optional": True},
        ]
    },
    "Test-NtpDrift.ps1": lambda **kw: {"offsetSeconds": round(random.uniform(-0.3, 0.5), 3), "status": "ok", "source": "time.windows.com"},
    "Get-NtpPeers.ps1": lambda **kw: {
        "status": {
            "source": "time.windows.com",
            "sourceIp": "13.86.101.172",
            "stratum": 3,
            "stratumText": "3 (secondary reference - syncd by (S)NTP)",
            "lastSync": (datetime.now() - timedelta(minutes=12)).strftime("%-m/%-d/%Y %-I:%M:%S %p"),
            "leapIndicator": "0(no warning)",
            "rootDelay": "0.0445007s",
            "rootDispersion": "7.7799853s",
            "pollInterval": "10 (1024s)",
        },
        "peers": [
            {
                "name": "time.windows.com",
                "state": "Active",
                "timeRemaining": "534.1234567s",
                "mode": "3 (Client)",
                "stratum": 3,
                "stratumText": "3 (secondary reference - syncd by (S)NTP)",
                "peerPollInterval": "10 (1024s)",
                "hostPollInterval": "10 (1024s)",
                "lastSyncTimestamp": (datetime.now() - timedelta(minutes=12)).strftime("%-m/%-d/%Y %-I:%M:%S %p"),
            },
        ],
    },
    "Test-DnsResolution.ps1": lambda **kw: {
        "googleServer": "8.8.8.8",
        "systemBlockedCount": 1,
        "mismatchCount": 0,
        "results": [
            # Hostname that intentionally trips the system-blocked case so the
            # finding + UI variant are visible in demo mode.
            {"host": "www.pixellot.tv",
             "system": {"resolvedTo": None,           "status": "fail", "resolutionMs": round(random.uniform(2000, 3000), 1), "error": "No such host is known."},
             "google": {"resolvedTo": "52.20.181.44", "status": "pass", "resolutionMs": round(random.uniform(8, 20), 1),       "error": None},
             "discrepancy": "system-blocked"},
            {"host": "pixellot.tv",
             "system": {"resolvedTo": "52.20.181.44", "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "52.20.181.44", "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None},
             "discrepancy": None},
            {"host": "software.pixellot.tv",
             "system": {"resolvedTo": "52.20.181.45", "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "52.20.181.45", "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None},
             "discrepancy": None},
            {"host": "nfhsnetwork.com",
             "system": {"resolvedTo": "52.20.181.43", "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "52.20.181.43", "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None},
             "discrepancy": None},
            {"host": "s3.amazonaws.com",
             "system": {"resolvedTo": "52.217.44.54", "status": "pass", "resolutionMs": round(random.uniform(6, 14), 1),  "error": None},
             "google": {"resolvedTo": "52.217.44.54", "status": "pass", "resolutionMs": round(random.uniform(8, 16), 1),  "error": None},
             "discrepancy": None},
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
    "Get-ScoreConnectStatus.ps1": lambda **kw: {
        "reachable": True,
        "baseUrl": "http://localhost:5000",
        "version": "2.4.1",
        "status": {"version": "2.4.1", "uptime": "12d 7h 42m", "isDetected": True},
        "configuration": {
            "vendor": "Daktronics",
            "sport": "Basketball",
            "vendorConfigurationName": "RTD-1702",
            "serialPort": "COM4",
            "firmware": "v3.11",
            "eventType": "Game",
        },
        "botStatus": {
            "isConnected": True,
            "scoreConnectId": "84721",
            "botServerAddress": "botserver.sportzcast.com",
            "lastErrorMessage": None,
        },
        "liveScoreData": {
            "homeTeam": random.choice(["Eagles", "Wildcats", "Lions", "Hawks", "Tigers", "Cougars"]),
            "awayTeam": random.choice(["Panthers", "Bears", "Falcons", "Spartans", "Knights", "Bulldogs"]),
            "homeScore": random.randint(18, 72),
            "awayScore": random.randint(18, 72),
            "period": random.choice(["Q2", "Q3", "Q4", "H2"]),
            "clock": f"{random.randint(0, 9):02d}:{random.randint(0, 59):02d}",
        },
        "scoreLinkConnected": True,
        "scoreLinkPort": "COM4",
        "scoreLinkModel": "ScoreLinkII",
        "scoreLinkStatusLabel": "ScoreLinkII device connected (COM4)",
        "error": None,
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
    "Test-PixellotInstallState.ps1": lambda **kw: {
        "dirExists": True,
        "dir": "C:\\pixellot\\downloadedversion",
        "incomplete": True,
        "rebooting": False,
        "partFiles": [
            {"name": "Pixellot-5.2.1.part_1", "sizeMB": 487.3, "lastWrite": (datetime.now() - timedelta(hours=14)).isoformat()},
            {"name": "Pixellot-5.2.1.part_2", "sizeMB": 487.3, "lastWrite": (datetime.now() - timedelta(hours=14)).isoformat()},
            {"name": "Pixellot-5.2.1.part_3", "sizeMB": 192.7, "lastWrite": (datetime.now() - timedelta(hours=14)).isoformat()},
        ],
        "partCount": 3,
        "log": {
            "path": "C:\\pixellot\\downloadedversion\\install_log_2026-05-26.log",
            "name": "install_log_2026-05-26.log",
            "sizeKB": 38.6,
            "lastWrite": (datetime.now() - timedelta(hours=14)).isoformat(),
            "lastLine": "Verifying part_3 integrity — 47% complete",
        },
        "message": "Half-finished install: 3 part file(s) present and log does not end with 'Rebooting...'.",
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
