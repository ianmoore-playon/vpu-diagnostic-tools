"""TokenStore — secure-at-rest token storage for the Pixellot Cloud client.

Storage model: Option B (token-only, no password persistence).

The stored blob contains the bearer token AND the email of the signed-in user.
Email is kept alongside the token so the UI can render "Signed in as X" /
"Session expired — sign in again as X" prompts even after the server has
invalidated the token. The email is not a secret; it lives inside the
encrypted blob purely for convenience (one file, one read).

Platform behavior:
  - Windows: DPAPI user-scope (CryptProtectData) with a Pulse-specific
    pOptionalEntropy salt. Blob written to %LOCALAPPDATA%\\Pulse\\token.dat.
    File ACL is tightened to the current user via icacls (best-effort —
    DPAPI already protects contents).
  - macOS / Linux (dev only): plaintext JSON at ~/.config/pulse/token.json
    with 0600 permissions. Production never runs on these platforms.

What DPAPI protects:
  - File copied off the machine: key never leaves the source machine
  - Other Windows user on same VPU: user-scope blob, not decryptable
  - Offline drive theft without the user's Windows password

What it does NOT protect:
  - Code running as the same Windows user (it can call CryptUnprotectData
    itself). This matches Chrome's saved-password posture and is acceptable
    for Pulse's threat model.

Threat-model decision recorded in HANDOFF-pixellot-cloud-integration.md
(Auth model section).
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


# Per-app entropy salt for DPAPI. Not a secret — its purpose is to narrow the
# decryption surface so another process running as the same Windows user can't
# blindly decrypt our blob even if it knows the file path. Bumping the version
# suffix invalidates all existing blobs (forces re-sign-in).
_DPAPI_ENTROPY = b"PulseDiagnosticTools/PixellotCloud/v1"


@dataclass
class StoredCreds:
    token: str
    email: str


class TokenStore:
    """Persistent store for the Pixellot Club bearer token + signed-in email."""

    def __init__(self, path: Optional[Path] = None) -> None:
        self._path = path or _default_path()

    # ---- public API ----

    def get(self) -> Optional[StoredCreds]:
        """Read and decrypt the stored credentials. Returns None if absent
        or undecryptable (e.g., after a Windows admin-forced password reset)."""
        if not self._path.exists():
            return None
        try:
            raw = self._read_blob()
            data = json.loads(raw)
            return StoredCreds(token=data["token"], email=data["email"])
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            return None

    def get_token(self) -> Optional[str]:
        creds = self.get()
        return creds.token if creds else None

    def get_email(self) -> Optional[str]:
        creds = self.get()
        return creds.email if creds else None

    def set(self, token: str, email: str) -> None:
        """Encrypt and persist the token + email."""
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps({"token": token, "email": email}).encode("utf-8")
        self._write_blob(payload)

    def clear(self) -> None:
        """Delete the stored credentials."""
        try:
            self._path.unlink()
        except FileNotFoundError:
            pass

    @property
    def path(self) -> Path:
        return self._path

    # ---- platform dispatch ----

    def _read_blob(self) -> bytes:
        raw = self._path.read_bytes()
        if sys.platform == "win32":
            return _dpapi_unprotect(raw, _DPAPI_ENTROPY)
        return raw

    def _write_blob(self, payload: bytes) -> None:
        if sys.platform == "win32":
            blob = _dpapi_protect(payload, _DPAPI_ENTROPY)
            # Write atomically: write to .tmp then replace
            tmp = self._path.with_suffix(self._path.suffix + ".tmp")
            tmp.write_bytes(blob)
            tmp.replace(self._path)
            _windows_restrict_acl(self._path)
        else:
            tmp = self._path.with_suffix(self._path.suffix + ".tmp")
            # Create with 0600 from the start to avoid a brief world-readable window.
            fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            try:
                with os.fdopen(fd, "wb") as fh:
                    fh.write(payload)
            except Exception:
                os.close(fd) if not fd == -1 else None
                raise
            os.chmod(tmp, 0o600)
            tmp.replace(self._path)


def _default_path() -> Path:
    if sys.platform == "win32":
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            local = str(Path.home() / "AppData" / "Local")
        return Path(local) / "Pulse" / "token.dat"
    return Path.home() / ".config" / "pulse" / "token.json"


# =====================================================================
# Windows DPAPI implementation
# =====================================================================

if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes

    class _DATA_BLOB(ctypes.Structure):
        _fields_ = [
            ("cbData", wintypes.DWORD),
            ("pbData", ctypes.POINTER(ctypes.c_char)),
        ]

    _CRYPTPROTECT_UI_FORBIDDEN = 0x01

    _crypt32 = ctypes.WinDLL("crypt32", use_last_error=True)
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    _crypt32.CryptProtectData.argtypes = [
        ctypes.POINTER(_DATA_BLOB),
        wintypes.LPCWSTR,
        ctypes.POINTER(_DATA_BLOB),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(_DATA_BLOB),
    ]
    _crypt32.CryptProtectData.restype = wintypes.BOOL

    _crypt32.CryptUnprotectData.argtypes = [
        ctypes.POINTER(_DATA_BLOB),
        ctypes.POINTER(wintypes.LPWSTR),
        ctypes.POINTER(_DATA_BLOB),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(_DATA_BLOB),
    ]
    _crypt32.CryptUnprotectData.restype = wintypes.BOOL

    _kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    _kernel32.LocalFree.restype = ctypes.c_void_p

    def _dpapi_protect(plaintext: bytes, entropy: bytes) -> bytes:
        in_buf = ctypes.create_string_buffer(plaintext, len(plaintext))
        ent_buf = ctypes.create_string_buffer(entropy, len(entropy))
        in_blob = _DATA_BLOB(
            len(plaintext),
            ctypes.cast(in_buf, ctypes.POINTER(ctypes.c_char)),
        )
        ent_blob = _DATA_BLOB(
            len(entropy),
            ctypes.cast(ent_buf, ctypes.POINTER(ctypes.c_char)),
        )
        out_blob = _DATA_BLOB()
        ok = _crypt32.CryptProtectData(
            ctypes.byref(in_blob),
            None,
            ctypes.byref(ent_blob),
            None,
            None,
            _CRYPTPROTECT_UI_FORBIDDEN,
            ctypes.byref(out_blob),
        )
        if not ok:
            err = ctypes.get_last_error()
            raise OSError(f"CryptProtectData failed: Windows error {err}")
        try:
            return ctypes.string_at(out_blob.pbData, out_blob.cbData)
        finally:
            _kernel32.LocalFree(out_blob.pbData)

    def _dpapi_unprotect(ciphertext: bytes, entropy: bytes) -> bytes:
        in_buf = ctypes.create_string_buffer(ciphertext, len(ciphertext))
        ent_buf = ctypes.create_string_buffer(entropy, len(entropy))
        in_blob = _DATA_BLOB(
            len(ciphertext),
            ctypes.cast(in_buf, ctypes.POINTER(ctypes.c_char)),
        )
        ent_blob = _DATA_BLOB(
            len(entropy),
            ctypes.cast(ent_buf, ctypes.POINTER(ctypes.c_char)),
        )
        out_blob = _DATA_BLOB()
        ok = _crypt32.CryptUnprotectData(
            ctypes.byref(in_blob),
            None,
            ctypes.byref(ent_blob),
            None,
            None,
            _CRYPTPROTECT_UI_FORBIDDEN,
            ctypes.byref(out_blob),
        )
        if not ok:
            err = ctypes.get_last_error()
            raise OSError(f"CryptUnprotectData failed: Windows error {err}")
        try:
            return ctypes.string_at(out_blob.pbData, out_blob.cbData)
        finally:
            _kernel32.LocalFree(out_blob.pbData)

    def _windows_restrict_acl(path: Path) -> None:
        """Best-effort: restrict file ACL to the current user via icacls.

        The blob is already DPAPI-encrypted; this is belt-and-suspenders for
        defense against accidental world-readable inheritance. Failures are
        silently ignored — they don't change the security posture meaningfully.
        """
        import subprocess
        user = os.environ.get("USERNAME")
        if not user:
            return
        try:
            subprocess.run(
                [
                    "icacls", str(path),
                    "/inheritance:r",
                    "/grant:r", f"{user}:F",
                ],
                capture_output=True,
                timeout=5,
                check=False,
            )
        except (subprocess.SubprocessError, OSError):
            pass

else:
    # Non-Windows: these stubs exist only so the module imports cleanly.
    # They are never called because _read_blob/_write_blob gate on sys.platform.
    def _dpapi_protect(plaintext: bytes, entropy: bytes) -> bytes:  # type: ignore[misc]
        raise NotImplementedError("DPAPI is Windows-only")

    def _dpapi_unprotect(ciphertext: bytes, entropy: bytes) -> bytes:  # type: ignore[misc]
        raise NotImplementedError("DPAPI is Windows-only")

    def _windows_restrict_acl(path: Path) -> None:  # type: ignore[misc]
        pass
