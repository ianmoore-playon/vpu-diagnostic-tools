# Dev SSH access to the test VPU

Hardened SSH for Pulse development: the VPU is reachable **only over Tailscale**
(outbound-only overlay network — no inbound port on the venue LAN or internet),
auth is **key-only** (no passwords), logins are limited to **one account**, and
the key on the Mac is **passphrase-protected** via the Apple keychain.

This fixes every concern that got the June 2026 raw-SSH setup removed:
admin shell exposed to Any → tailnet-only firewall; password auth → disabled;
passphraseless key → keychain-managed passphrase.

## One-time setup

### Mac (1 of 2) — key + Tailscale

```bash
# 1. Generate a passphrase-protected key (pick a passphrase; Keychain remembers it)
ssh-keygen -t ed25519 -f ~/.ssh/vpu_test -C "ian.moore vpu-test"

# 2. Store it in the agent + keychain
ssh-add --apple-use-keychain ~/.ssh/vpu_test

# 3. Install + log in to Tailscale (same account you'll use on the VPU).
#    The pkg installer will prompt for your macOS password.
brew install --cask tailscale-app   # or https://tailscale.com/download
open -a Tailscale                   # finish login in the menu bar app

# 4. Copy the PUBLIC key — you'll paste it into the VPU script
cat ~/.ssh/vpu_test.pub | pbcopy
```

### VPU (2 of 2) — run the setup script

Copy `Setup-DevSsh.ps1` to the VPU, then in an **elevated** PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Setup-DevSsh.ps1 -PublicKey "ssh-ed25519 AAAA... ian.moore vpu-test"
tailscale up          # if the script says Tailscale isn't logged in
tailscale ip -4       # note the 100.x.y.z address
```

### Back on the Mac — point the config at the VPU

`~/.ssh/config` already has a `vpu-test` entry; replace the `HostName`
placeholder with the address from `tailscale ip -4` (and `User` if the VPU
account isn't the default), then:

```bash
ssh vpu-test 'hostname; whoami'
```

## Optional hardening (Tailscale admin console)

In the tailnet ACLs, restrict so only the Mac can reach the VPU on port 22.
For a two-device personal tailnet the default "all devices see each other"
is acceptable; add this if other devices join later.

## Notes

- Re-running `Setup-DevSsh.ps1` is safe (idempotent).
- The SSH shell is PowerShell, running as the allowed (admin) account — full
  capability for Pulse collectors, WMI/CIM, event logs, service control.
- To revoke access: `Stop-Service sshd; Set-Service sshd -StartupType Disabled`
  on the VPU, or just remove the VPU from the tailnet.
- Test VPUs only. Production/field VPUs get remote access via the Cloudflare
  Tunnel track, not this.
