# DNS Changer — switch your system DNS from the Omarchy bar

A faithful Omarchy port of [DNS Changer](https://github.com/DnsChanger)'s CLI
(`dnschanger-cli`): the same connect/disconnect/status behavior, the same
curated server catalog, and the same Linux backend, wired into a bar widget +
panel instead of a terminal command.

## What it does

- **Bar pill** — shows the current DNS state: `DNS Off` (no nameservers set),
  the matching catalog server's name (e.g. `Shecan`), or `DNS Custom` (connected,
  but not to anything in the catalog — mirrors the CLI's `status` command,
  including its "unknown server" case right after a disconnect). Left-click
  opens the panel, middle-click refreshes.
- **Servers** — the full DnsChanger catalog (Shecan, Zeus DNS, Electro Team,
  Cloudflare, Google, Quad9, OpenDNS, gaming and Fivem DNS, anti-sanction DNS,
  ad blockers, ...), sorted by rating, fetched live from the same store the
  desktop app uses and cached locally, with a bundled snapshot as an offline
  fallback. Each row shows a provider icon and its live ping in ms, refreshed
  on open, on a 5-minute timer, or via **Ping all**. For well-known providers
  with a public site (Cloudflare, Google, Quad9, OpenDNS, Yandex, AdGuard,
  Norton, Level3, UltraDNS, CleanBrowsing, ControlD, dns0.eu — see
  `Model.DOMAIN_BY_KEY`) that's their real favicon, fetched at request time
  from DuckDuckGo's icon service — nothing is bundled or redistributed. Every
  other provider (the regional/gaming/niche entries have no identifiable
  official site), and any favicon that fails to load, falls back to a
  generated monogram badge (a deterministic color + initials). Click a row to
  connect — mirrors `d11i connect -n <name>`.
- **Custom server** — type one or two addresses (comma-separated) and connect —
  mirrors `d11i connect -s <ip1>,<ip2>`, including the exact same validation
  and the "unlisted address becomes a `custom-<ip>` entry" behavior.
- **Random** — connect to a random catalog server — mirrors `d11i connect -r`.
- **Disconnect** — resets to the CLI's own Linux defaults
  (`1.1.1.1, 8.8.8.8, 192.168.1.1, 127.0.0.1`) — mirrors `d11i disconnect`
  (aliases `dis` / `d8t`).
- **Flush DNS cache** — exposes the platform's `flushDns()`, which exists in
  the original CLI's codebase but isn't wired to any of its commands; here
  it's a real button.
- **Ping** — not part of the original CLI (it has no latency feature): one
  parallel ICMP echo per unique server address, 1s timeout, shown next to
  each row and refreshed on open, every 5 minutes, or via **Ping all**.
- **Font** — renders in Inter, the same typeface the DnsChanger desktop/web
  app uses (its `index.css`: `body { font-family: Inter }`, Inter-Medium.ttf),
  instead of the shell's bar theme font. Bundled from Google Fonts as a
  variable font (`fonts/Inter.ttf`, SIL Open Font License — `fonts/Inter-OFL.txt`).

## How it works

`scripts/dns-changer` is a small bash helper that mirrors
[`linux.platform.ts`](https://github.com/DnsChanger/dnschanger-cli/blob/main/src/platforms/linux/linux.platform.ts):

- `active` — reads `nameserver` lines from `/etc/resolv.conf` (no privilege needed)
- `connect <ip> [ip2]` / `disconnect` — writes `/etc/resolv.conf` and restarts
  `systemd-networkd`, elevated once via `pkexec` (the Linux equivalent of the
  CLI's `sudo-prompt` dependency)
- `flush` — flushes the resolver cache (`resolvectl` / `systemd-resolve`)
- `fetch-servers` — pulls the live server catalog from the same
  `dnsChanger-desktop` store the CLI/desktop app use
- `ping <ip>...` — one `ping -c 1 -W 1` per address, run in parallel

The panel drives this script via Quickshell's `Process`, and caches the
server list and last-known DNS state under `~/.cache/omarchy-dns-changer/` so
the bar pill restores instantly after a shell reload.

## Install

```sh
omarchy plugin add https://github.com/HACK3RRABBIT/omarchy-dns-changer.git --enable
```

## Requirements

`curl`, `jq`, `pkexec` (polkit), and `ping` (iputils) on the system running the plugin.

## Credits

Ported from [DnsChanger/dnschanger-cli](https://github.com/DnsChanger/dnschanger-cli)
and its [server catalog](https://github.com/DnsChanger/dnsChanger-desktop).
All server entries, defaults, and connect/disconnect/status semantics come
from that project. Font: [Inter](https://github.com/rsms/inter) by The Inter
Project Authors, SIL OFL 1.1.

## License

MIT
