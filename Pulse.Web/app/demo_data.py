"""Mock data for non-Windows demo mode."""

import random
import time
from datetime import datetime, timedelta

_BOOT = time.time() - 4 * 86400 - 7 * 3600


def _uptime_secs():
    return int(time.time() - _BOOT)


def _fmt_uptime(s):
    d, r = divmod(s, 86400)
    h, r = divmod(r, 3600)
    m, _ = divmod(r, 60)
    return f"{d}d {h}h {m}m"


DEMO = {
    "Get-SystemIdentity.ps1": lambda **kw: {
        "computerSystem": {"name": "VPU-DEMO-DATA", "manufacturer": "Demo HP VPU", "model": "TESTING-1-2-3-ABC"},
        "bios": {"serialNumber": "6767676767"},
        "uptime": {"formatted": _fmt_uptime(_uptime_secs()), "totalSeconds": _uptime_secs()},
        "operatingSystem": {"caption": "Microsoft Windows 10 IoT Enterprise", "version": "10.0.19045", "buildNumber": "19045", "osArchitecture": "64-bit"},
        "pixellot": {"version": "5.2.1.3842", "imageVersion": "23.04.002"},
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
             "arpEntries": [{"ip": "10.0.1.1", "mac": "00:1A:2B:3C:4D:5E"}]},
        ]
    },
    "Get-Hardware.ps1": lambda **kw: {
        "processors": [{"name": "Intel(R) Core(TM) i7-8700T CPU @ 2.40GHz", "numberOfCores": 6, "numberOfLogicalProcessors": 12, "maxClockSpeedMHz": 2400}],
        "memory": [
            {"capacityGB": 16, "speedMHz": 2666, "memoryType": "DDR4", "deviceLocator": "DIMM_A1"},
            {"capacityGB": 16, "speedMHz": 2666, "memoryType": "DDR4", "deviceLocator": "DIMM_B1"},
        ],
        "gpus": [{"name": "Intel(R) UHD Graphics 630", "adapterRAMMB": 1024, "driverVersion": "27.20.100.8935"}],
        "diskDrives": [
            {"model": "Generic HDD", "sizeGB": 500, "interfaceType": "SATA", "serialNumber": "S3Z8NB0K901234A"}
        ],
    },
    "Get-InstalledSoftware.ps1": lambda **kw: {
        "count": 18,
        "software": [
            {"displayName": "Pixellot VPU Agent", "displayVersion": "5.2.1.3842", "publisher": "Pixellot Ltd."},
            {"displayName": "Pixellot VPU Engine", "displayVersion": "5.2.1.3842", "publisher": "Pixellot Ltd."},
            {"displayName": "Pixellot Encoder", "displayVersion": "3.8.0", "publisher": "Pixellot Ltd."},
            {"displayName": "Google Chrome", "displayVersion": "120.0.6099.130", "publisher": "Google LLC"},
            {"displayName": "LogMeIn", "displayVersion": "4.1.0.14083", "publisher": "LogMeIn, Inc."},
            {"displayName": "Microsoft Visual C++ 2019 Redistributable (x64)", "displayVersion": "14.29.30139", "publisher": "Microsoft"},
            {"displayName": "Microsoft .NET Runtime - 6.0.25", "displayVersion": "6.0.25", "publisher": "Microsoft"},
            {"displayName": "Intel(R) Network Connections", "displayVersion": "27.2", "publisher": "Intel"},
            {"displayName": "7-Zip 23.01 (x64)", "displayVersion": "23.01", "publisher": "Igor Pavlov"},
            {"displayName": "TightVNC", "displayVersion": "2.8.81", "publisher": "GlavSoft LLC."},
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
            {"interfaceAlias": "Ethernet 4 (Uplink)", "interfaceIndex": 4, "ipv4Address": ["10.0.1.50"], "ipv4DefaultGateway": ["10.0.1.1"], "dnsServers": ["8.8.8.8", "8.8.4.4"], "dhcpEnabled": True, "prefixLength": 24},
            {"interfaceAlias": "Ethernet 1", "interfaceIndex": 1, "ipv4Address": ["192.168.10.1"], "ipv4DefaultGateway": [], "dnsServers": [], "dhcpEnabled": False, "prefixLength": 24},
            {"interfaceAlias": "Ethernet 2", "interfaceIndex": 2, "ipv4Address": ["192.168.11.1"], "ipv4DefaultGateway": [], "dnsServers": [], "dhcpEnabled": False, "prefixLength": 24},
            {"interfaceAlias": "Ethernet 3", "interfaceIndex": 3, "ipv4Address": ["192.168.12.1"], "ipv4DefaultGateway": [], "dnsServers": [], "dhcpEnabled": False, "prefixLength": 24},
        ],
        "uplinkAdapter": {"interfaceAlias": "Ethernet 4 (Uplink)", "gateway": "10.0.1.1", "interfaceIndex": 4},
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
    "Test-LocalNetwork.ps1": lambda **kw: {
        "gateway": {"target": "10.0.1.1", "label": "Gateway", "reachable": True, "sent": 4, "received": 4, "lossPercent": 0, "minMs": 1, "avgMs": 2, "maxMs": 4, "status": "pass"},
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
            "homeTeam": "Eagles",
            "awayTeam": "Panthers",
            "homeScore": 24,
            "awayScore": 17,
            "period": "Q3",
            "clock": "04:22",
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
        "connections": [
            {"localPort": 49201, "remoteAddr": "52.20.181.44", "remotePort": 443, "remoteHost": "api.pixellot.tv", "state": "Established", "pid": 4120},
            {"localPort": 49205, "remoteAddr": "52.20.181.45", "remotePort": 443, "remoteHost": "cloud.pixellot.tv", "state": "Established", "pid": 4120},
            {"localPort": 49210, "remoteAddr": "52.20.181.46", "remotePort": 1935, "remoteHost": "live.pixellot.tv", "state": "Established", "pid": 5230},
            {"localPort": 49215, "remoteAddr": "52.217.44.54", "remotePort": 443, "remoteHost": "s3.amazonaws.com", "state": "Established", "pid": 4120},
            {"localPort": 49220, "remoteAddr": "76.76.21.21", "remotePort": 443, "remoteHost": "service.singular.live", "state": "Established", "pid": 6010},
            {"localPort": 49225, "remoteAddr": "216.52.233.2", "remotePort": 443, "remoteHost": "secure.logmein.com", "state": "TimeWait", "pid": 0},
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
            {"hop": 1, "ip": "10.0.1.1", "hostname": "gateway.local", "rttMs": 1, "status": "transit"},
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
