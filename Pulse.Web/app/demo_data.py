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
        "timezone": "Eastern Standard Time",
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
            {"name": "Ethernet 1", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection", "status": "Up", "linkSpeedMbps": 1000, "mac": "A4:4C:C8:12:34:01", "rxBytes": 82749103726, "txBytes": 5283910234,
             "arpEntries": [{"ip": "192.168.10.100", "mac": "00:0E:53:AA:01:01"}, {"ip": "192.168.10.101", "mac": "00:0E:53:AA:01:02"}, {"ip": "192.168.10.102", "mac": "00:0E:53:AA:01:03"}]},
            {"name": "Ethernet 2", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #2", "status": "Up", "linkSpeedMbps": 1000, "mac": "A4:4C:C8:12:34:02", "rxBytes": 41029384756, "txBytes": 2938475610,
             "arpEntries": [{"ip": "192.168.11.100", "mac": "00:0E:53:BB:02:01"}, {"ip": "192.168.11.101", "mac": "00:0E:53:BB:02:02"}]},
            {"name": "Ethernet 3", "interfaceDescription": "Intel(R) I210 Gigabit Network Connection #3", "status": "Up", "linkSpeedMbps": 100, "mac": "A4:4C:C8:12:34:03", "rxBytes": 1028374, "txBytes": 293847,
             "arpEntries": [{"ip": "192.168.12.50", "mac": "00:30:53:CC:03:01"}]},
            {"name": "Ethernet 4 (Uplink)", "interfaceDescription": "Intel(R) I211 Gigabit Network Connection", "status": "Up", "linkSpeedMbps": 1000, "mac": "A4:4C:C8:12:34:04", "rxBytes": 129384756012, "txBytes": 98273640182,
             "arpEntries": [{"ip": "10.0.1.1", "mac": "00:1A:2B:3C:4D:5E"}]},
        ]
    },
    "Get-Hardware.ps1": lambda **kw: {
        "processors": [{"name": "Intel(R) Core(TM) i7-8700T CPU @ 2.40GHz", "numberOfCores": 6, "numberOfLogicalProcessors": 12, "maxClockSpeedMHz": 2400}],
        "memory": [
            {"capacityGB": 8, "speedMHz": 2666, "memoryType": "DDR4", "deviceLocator": "DIMM_A1"},
            {"capacityGB": 8, "speedMHz": 2666, "memoryType": "DDR4", "deviceLocator": "DIMM_B1"},
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
        "uplinkAdapter": {"interfaceAlias": "Ethernet 4 (Uplink)", "gateway": "10.0.1.1"},
        "internet": {"reachable": True, "testedHost": "www.google.com"},
        "ntpSource": "time.windows.com",
    },
    "Test-NetworkDomains.ps1": lambda **kw: {
        "results": [
            {"domain": "api.pixellot.tv", "resolvedTo": "52.20.181.43", "status": "pass"},
            {"domain": "cloud.pixellot.tv", "resolvedTo": "52.20.181.44", "status": "pass"},
            {"domain": "updates.pixellot.tv", "resolvedTo": "52.20.181.45", "status": "pass"},
            {"domain": "log.pixellot.tv", "resolvedTo": "52.20.181.46", "status": "pass"},
            {"domain": "ntp.pixellot.tv", "resolvedTo": None, "status": "fail"},
        ]
    },
    "Test-NetworkPorts.ps1": lambda **kw: {
        "results": [
            {"purpose": "Pixellot API", "host": "api.pixellot.tv", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "Pixellot Cloud", "host": "cloud.pixellot.tv", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "Pixellot Updates", "host": "updates.pixellot.tv", "port": 443, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "RTMP Ingest", "host": "live.pixellot.tv", "port": 1935, "protocol": "TCP", "status": "pass", "optional": False},
            {"purpose": "LogMeIn", "host": "secure.logmein.com", "port": 443, "protocol": "TCP", "status": "pass", "optional": True},
            {"purpose": "NTP", "host": "time.windows.com", "port": 123, "protocol": "UDP", "status": "pass", "optional": False},
            {"purpose": "Telemetry", "host": "telemetry.pixellot.tv", "port": 8443, "protocol": "TCP", "status": "fail", "optional": True},
        ]
    },
    "Test-NtpDrift.ps1": lambda **kw: {"offsetSeconds": round(random.uniform(-0.3, 0.5), 3), "status": "ok"},
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
        "status": {"version": "2.4.1", "uptime": "12d 7h 42m", "activeConnections": 3},
        "configuration": {"port": 5000, "autoStart": True, "maxConnections": 10},
    },
    "Get-PixellotConfig.ps1": lambda **kw: {
        "cameras": [
            {"section": "Camera1", "ip": "192.168.10.100", "mac": "00:0E:53:AA:01:01", "role": "Main"},
            {"section": "Camera2", "ip": "192.168.10.101", "mac": "00:0E:53:AA:01:02", "role": "Panoramic"},
            {"section": "Camera3", "ip": "192.168.10.102", "mac": "00:0E:53:AA:01:03", "role": "Tactical"},
            {"section": "Camera4", "ip": "192.168.11.100", "mac": "00:0E:53:BB:02:01", "role": "Main"},
            {"section": "Camera5", "ip": "192.168.11.101", "mac": "00:0E:53:BB:02:02", "role": "Panoramic"},
            {"section": "OCR", "ip": "192.168.12.50", "mac": "00:30:53:CC:03:01", "role": "OCR"},
        ],
    },
    "Restart-Service.ps1": lambda **kw: {"success": True, "message": "Service restarted successfully (demo)"},
}


def get_demo(script_name, args=None):
    fn = DEMO.get(script_name)
    if fn is None:
        return None
    return fn(**(args or {}))
