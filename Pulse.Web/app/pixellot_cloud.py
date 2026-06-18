"""PixellotCloudClient — async HTTP client for the Pixellot Club API.

The canonical endpoint we care about:
    GET https://abe.pixellot.tv/api/v3/venues/{venueId}?include=metrics
    Authorization: Bearer <jwt>

This returns the static venue profile (hardware, camera head, network) plus
the live metrics.values block in a single response — the source of truth per
HANDOFF-pixellot-cloud-integration.md.

Auth model (Option B):
- Sign-in produces a bearer token, stored via TokenStore. No password on disk.
- On 401, the client raises SessionExpired. Caller (CLI / UI) re-prompts for
  the password. No silent re-auth.
- Token TTL appears to be ~24h per Pixellot's pattern; observed live.

Security:
- windowsLicenseSerialNumber is stripped from every payload on ingest. It
  must never reach the UI, logs, or downstream code.
- redact() helper scrubs Bearer tokens from arbitrary strings for safe debug
  output. Never log raw HTTP traffic without it.
"""

from __future__ import annotations

import re
from typing import Any, Optional

import httpx

from token_store import TokenStore

BASE_URL = "https://abe.pixellot.tv"
DEFAULT_TIMEOUT = 15.0

# Sensitive fields stripped from every venue payload before it leaves this
# module. Add new field names here if Pixellot expands the response shape with
# anything that shouldn't be displayed or logged.
_STRIP_FIELDS = frozenset({"windowsLicenseSerialNumber"})

# Bearer redactor patterns. Used by redact() for safe debug output.
_BEARER_RE = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE)
_TOKEN_FIELD_RE = re.compile(r'("token"\s*:\s*")[^"]+(")')


class PixellotCloudError(Exception):
    """Base class for Pixellot Cloud client errors."""


class SessionExpired(PixellotCloudError):
    """Raised on 401. Caller must re-authenticate — no auto re-auth in
    Option B (token-only storage; password is not persisted)."""


class LoginFailed(PixellotCloudError):
    """Raised when /auth/login rejects the supplied credentials."""


class PixellotCloudClient:
    """Async client. Use as a context manager:

        async with PixellotCloudClient(token_store) as client:
            await client.login(email, password)
            venue = await client.fetch_venue(venue_id)
    """

    def __init__(self, token_store: TokenStore, *, timeout: float = DEFAULT_TIMEOUT) -> None:
        self._tokens = token_store
        self._timeout = timeout
        self._client: Optional[httpx.AsyncClient] = None

    async def __aenter__(self) -> "PixellotCloudClient":
        self._client = httpx.AsyncClient(base_url=BASE_URL, timeout=self._timeout)
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    # ---- auth ----

    async def login(self, email: str, password: str) -> dict:
        """Authenticate against Pixellot Club. On success, persists token +
        email via TokenStore and returns the user attributes block (tenants,
        role, permissions, fullName).

        Raises LoginFailed if credentials are rejected."""
        client = self._require_client()
        resp = await client.post(
            "/api/v3/auth/login",
            json={"email": email, "password": password},
            headers={"Content-Type": "application/json"},
        )
        if resp.status_code != 200:
            raise LoginFailed(
                f"Login failed: HTTP {resp.status_code} {resp.reason_phrase}"
            )
        try:
            body = resp.json()
        except ValueError as e:
            raise LoginFailed(f"Login response was not JSON: {e}")

        token = body.get("token")
        if not token:
            raise LoginFailed("Login response missing 'token' field")
        self._tokens.set(token=token, email=email)

        return body.get("data", {}).get("attributes", {})

    def logout(self) -> None:
        """Clear stored token + email. Synchronous — no server-side logout
        endpoint is documented."""
        self._tokens.clear()

    def get_signed_in_email(self) -> Optional[str]:
        return self._tokens.get_email()

    def has_token(self) -> bool:
        return self._tokens.get_token() is not None

    # ---- venues ----

    async def fetch_venue(self, venue_id: str) -> dict:
        """Fetch a venue including its live metrics.

        Returns the unwrapped 'data' object with sensitive fields stripped.
        Raises SessionExpired on 401."""
        payload = await self._get_json(
            f"/api/v3/venues/{venue_id}",
            params={"include": "metrics"},
        )
        return _strip_secrets(payload.get("data", payload))

    async def list_venues(
        self,
        tenant: str,
        *,
        limit: int = 50,
    ) -> list[dict]:
        """List venues visible to the signed-in user, filtered by tenant.

        Returns a list of venue summary objects with sensitive fields stripped.
        Note: the list endpoint may not include all fields that the per-venue
        endpoint does (dongleIdentifier in particular). For MAC-based matching,
        use find_venue_for_macs which fetches each venue individually."""
        payload = await self._get_json(
            "/api/v3/venues",
            params={"tenant": tenant, "limit": limit},
        )
        venues = payload.get("data", [])
        if not isinstance(venues, list):
            return []
        return [_strip_secrets(v) for v in venues]

    async def find_venue_for_macs(
        self,
        macs: list[str],
        *,
        tenant: str,
        limit: int = 100,
    ) -> Optional[str]:
        """Find the venueId whose dongleIdentifier matches one of the given
        MAC addresses. Returns None if no match found.

        Strategy: list venues for the tenant, then fetch each individually
        and compare dongleIdentifier. The list endpoint isn't guaranteed to
        include dongleIdentifier, so we fetch per-venue. This is expensive
        and is intended for first-launch matching only — cache the venueId
        afterward.

        MAC matching is via dongleIdentifier (dashed format) only. Matching
        against poeSerialNumbers (PCI device path) is deferred — those entries
        embed the MAC in a non-trivial encoding and produce noisy matches.
        """
        normalized = {m for m in (_normalize_mac(x) for x in macs) if m}
        if not normalized:
            return None

        venues = await self.list_venues(tenant=tenant, limit=limit)
        for v in venues:
            venue_id = v.get("id")
            if not venue_id:
                continue
            try:
                full = await self.fetch_venue(venue_id)
            except SessionExpired:
                raise
            except PixellotCloudError:
                continue
            if _venue_matches_macs(full, normalized):
                return venue_id
        return None

    # ---- internals ----

    def _require_client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError(
                "PixellotCloudClient must be used as an async context manager"
            )
        return self._client

    async def _get_json(
        self,
        path: str,
        params: Optional[dict] = None,
    ) -> dict:
        client = self._require_client()
        token = self._tokens.get_token()
        if not token:
            raise SessionExpired("No stored token — sign in first")
        resp = await client.get(
            path,
            params=params,
            headers={"Authorization": f"Bearer {token}"},
        )
        if resp.status_code == 401:
            raise SessionExpired("Token rejected by server (HTTP 401)")
        if resp.status_code != 200:
            raise PixellotCloudError(
                f"GET {path} returned HTTP {resp.status_code} {resp.reason_phrase}"
            )
        try:
            return resp.json()
        except ValueError as e:
            raise PixellotCloudError(f"Non-JSON response from {path}: {e}")


# =====================================================================
# helpers
# =====================================================================

def redact(text: str) -> str:
    """Scrub Bearer tokens and JSON 'token' fields from a string. Use before
    logging or printing any raw HTTP traffic / response bodies."""
    text = _BEARER_RE.sub(r"\1[REDACTED]", text)
    text = _TOKEN_FIELD_RE.sub(r"\1[REDACTED]\2", text)
    return text


def _strip_secrets(obj: Any) -> Any:
    """Recursively remove sensitive fields from a venue payload. Run on every
    response before handing data to callers — these fields must never appear
    in logs, UI, or downstream code."""
    if isinstance(obj, dict):
        return {
            k: _strip_secrets(v)
            for k, v in obj.items()
            if k not in _STRIP_FIELDS
        }
    if isinstance(obj, list):
        return [_strip_secrets(item) for item in obj]
    return obj


def _normalize_mac(mac: str) -> str:
    """Lowercase + hex-only. Handles dashed ('00-30-64-...'), colon-separated
    ('00:30:64:...'), and raw-hex forms. Returns '' if no hex chars present."""
    if not mac:
        return ""
    return re.sub(r"[^0-9a-f]", "", mac.lower())


def _venue_matches_macs(venue: dict, normalized_macs: set[str]) -> bool:
    """Check if the venue's dongleIdentifier matches any of the supplied MACs.

    We compare only against dongleIdentifier (the dashed-MAC form). The
    poeSerialNumbers entries embed MACs inside PCI device paths in a
    non-trivial encoding — false-match risk is higher than it's worth for
    Phase 1. Extend here if dongleIdentifier alone proves insufficient.
    """
    dongle = venue.get("dongleIdentifier")
    if not dongle:
        return False
    return _normalize_mac(dongle) in normalized_macs


# =====================================================================
# CLI
# =====================================================================
#
# Usage from Pulse.Web/app/:
#   python pixellot_cloud.py login --email you@example.com
#   python pixellot_cloud.py whoami
#   python pixellot_cloud.py venues --tenant playOnPoly
#   python pixellot_cloud.py venue 603f38150d2eb332be059295
#   python pixellot_cloud.py find-venue --tenant playOnPoly --macs 00-30-64-68-5C-6F
#   python pixellot_cloud.py logout

def _build_arg_parser():
    import argparse
    parser = argparse.ArgumentParser(
        prog="pixellot_cloud",
        description="Pixellot Cloud API CLI (Phase 1 standalone tester).",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_login = sub.add_parser("login", help="Sign in to Pixellot Club")
    p_login.add_argument("--email", required=True, help="Pixellot Club email")

    sub.add_parser("whoami", help="Show signed-in user (from local store)")
    sub.add_parser("logout", help="Clear stored token + email")

    p_venues = sub.add_parser("venues", help="List venues for a tenant")
    p_venues.add_argument("--tenant", required=True)
    p_venues.add_argument("--limit", type=int, default=50)

    p_venue = sub.add_parser("venue", help="Fetch one venue (with live metrics)")
    p_venue.add_argument("venue_id")

    p_find = sub.add_parser(
        "find-venue",
        help="Find venueId whose dongleIdentifier matches a local NIC MAC",
    )
    p_find.add_argument("--tenant", required=True)
    p_find.add_argument(
        "--macs",
        required=True,
        help="Comma-separated MACs (dashed, colon, or raw hex)",
    )
    p_find.add_argument("--limit", type=int, default=100)

    return parser


async def _run_cli(args) -> int:
    import getpass
    import json
    import sys

    store = TokenStore()

    if args.cmd == "logout":
        store.clear()
        print(f"Cleared credentials at {store.path}")
        return 0

    if args.cmd == "whoami":
        email = store.get_email()
        has_token = store.get_token() is not None
        if email and has_token:
            print(f"Signed in as: {email}")
            print(f"Token stored: {store.path}")
        elif email and not has_token:
            print(f"Last signed in as {email}, but no token present.")
        else:
            print("Not signed in.")
        return 0

    async with PixellotCloudClient(store) as client:
        try:
            if args.cmd == "login":
                if not sys.stdin.isatty():
                    print(
                        "ERROR: stdin is not a TTY — refusing to read password.",
                        file=sys.stderr,
                    )
                    return 2
                password = getpass.getpass(f"Password for {args.email}: ")
                if not password:
                    print("ERROR: empty password.", file=sys.stderr)
                    return 2
                attrs = await client.login(args.email, password)
                print(f"Signed in as {args.email}")
                print(f"  fullName : {attrs.get('fullName')}")
                print(f"  role     : {attrs.get('role')}")
                print(f"  tenants  : {attrs.get('tenants')}")
                perms = attrs.get("permissions") or {}
                if perms:
                    print(f"  perms    : {json.dumps(perms, sort_keys=True)}")
                return 0

            if args.cmd == "venues":
                venues = await client.list_venues(
                    tenant=args.tenant, limit=args.limit
                )
                print(f"{len(venues)} venue(s) for tenant={args.tenant}:")
                for v in venues:
                    vid = v.get("id", "?")
                    name = v.get("name", "?")
                    sys_type = v.get("systemType", "?")
                    print(f"  {vid}  [{sys_type}]  {name}")
                return 0

            if args.cmd == "venue":
                venue = await client.fetch_venue(args.venue_id)
                # JSON has already been _strip_secrets'd in fetch_venue.
                print(json.dumps(venue, indent=2, default=str))
                return 0

            if args.cmd == "find-venue":
                macs = [m.strip() for m in args.macs.split(",") if m.strip()]
                if not macs:
                    print("ERROR: --macs was empty.", file=sys.stderr)
                    return 2
                print(f"Scanning {args.tenant} venues for MACs: {macs}")
                venue_id = await client.find_venue_for_macs(
                    macs, tenant=args.tenant, limit=args.limit
                )
                if venue_id:
                    print(f"Matched venueId: {venue_id}")
                    return 0
                print("No match found.")
                return 1

        except LoginFailed as e:
            print(f"Login failed: {e}", file=sys.stderr)
            return 2
        except SessionExpired as e:
            print(
                f"Session expired — run `login` again. ({e})",
                file=sys.stderr,
            )
            return 3
        except PixellotCloudError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 4

    return 1


def _cli_main() -> int:
    import asyncio
    parser = _build_arg_parser()
    args = parser.parse_args()
    return asyncio.run(_run_cli(args))


if __name__ == "__main__":
    raise SystemExit(_cli_main())
