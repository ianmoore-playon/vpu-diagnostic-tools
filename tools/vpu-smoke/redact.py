#!/usr/bin/env python3
"""Redact sensitive values from VPU collector output before it leaves the Mac.

Anything displayed in a Claude session egresses to Anthropic, so every piece
of VPU output that gets *shown* (rather than kept in a local file) must pass
through this filter first:

    python3 tools/vpu-smoke/redact.py < raw.json
    python3 tools/vpu-smoke/redact.py raw.json

What it masks:
  - values of secret-ish JSON keys (password, token, secret, credential, ...)
  - MAC addresses
  - public IPv4 addresses (keeps first octet; private/CGNAT ranges pass through)
  - values of serial-ish JSON keys (serialNumber, serviceTag, uuid, machineGuid)

Private RFC1918 / loopback / link-local / Tailscale CGNAT addresses are left
intact — they're needed for diagnosis and identify nothing outside the bench.
"""

from __future__ import annotations

import ipaddress
import re
import sys

SECRET_KEY_RE = re.compile(
    r'("(?:[^"]*?(?:pass(?:word)?|secret|token|credential|api[_-]?key|'
    r'connectionstring|pwd|bearer|authorization)[^"]*?)"\s*:\s*)"(?:[^"\\]|\\.)*"',
    re.IGNORECASE,
)

SERIAL_KEY_RE = re.compile(
    r'("(?:[^"]*?(?:serial(?:number)?|servicetag|machineguid|biosserial|'
    r'uuid)[^"]*?)"\s*:\s*)"((?:[^"\\]|\\.){4})(?:[^"\\]|\\.)*"',
    re.IGNORECASE,
)

MAC_RE = re.compile(r"\b[0-9A-Fa-f]{2}([:-])(?:[0-9A-Fa-f]{2}\1){4}[0-9A-Fa-f]{2}\b")

IPV4_RE = re.compile(r"\b((?:\d{1,3}\.){3}\d{1,3})\b")


def _mask_ip(match: re.Match) -> str:
    text = match.group(1)
    try:
        ip = ipaddress.IPv4Address(text)
    except ipaddress.AddressValueError:
        return text
    if (
        ip.is_private          # 10/8, 172.16/12, 192.168/16
        or ip.is_loopback
        or ip.is_link_local
        or ip in ipaddress.IPv4Network("100.64.0.0/10")  # Tailscale CGNAT
        or ip.is_multicast
        or ip.is_unspecified
        or text.endswith(".255")
    ):
        return text
    return f"{text.split('.')[0]}.x.x.x"


def redact(text: str) -> str:
    text = SECRET_KEY_RE.sub(r'\1"«REDACTED»"', text)
    text = SERIAL_KEY_RE.sub(r'\1"\2«…»"', text)
    text = MAC_RE.sub("«MAC»", text)
    text = IPV4_RE.sub(_mask_ip, text)
    return text


def main() -> None:
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
            data = fh.read()
    else:
        data = sys.stdin.read()
    sys.stdout.write(redact(data))


if __name__ == "__main__":
    main()
