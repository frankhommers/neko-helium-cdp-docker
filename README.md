# neko-helium-cdp-docker

Docker setup for **Neko + [Helium](https://github.com/imputnet/helium)** with Chrome DevTools Protocol (CDP) access, and the **full uBlock Origin** built in.

This is a variant of [neko-chrome-cdp-docker](https://github.com/frankhommers/neko-chrome-cdp-docker) with Google Chrome swapped for Helium. Everything else is the same: the same browser session is used interactively through Neko's WebRTC UI and programmatically over CDP (Playwright, Puppeteer, custom tooling).

## Why Helium

Google Chrome no longer runs Manifest V2 extensions. The enterprise exception ended with Chrome 139 and the last workarounds with Chrome 150/151, so the full uBlock Origin cannot run in Chrome any more (only the MV3 "Lite" version).

Helium is an open-source Chromium browser based on ungoogled-chromium that keeps Manifest V2 alive and ships the full uBlock Origin as a built-in component:

- CDP works as in Chrome (`/json/version` reports `Chrome/<version>`), so CDP clients need no changes
- full uBlock Origin (MV2, `webRequestBlocking`) is active out of the box, no extension install needed
- no Google account, sync or telemetry

Trade-offs compared to Google Chrome:

- small, pre-1.0 project (imput); updates come from its GitHub releases
- no Google services, sign-in or Widevine (DRM video)
- not the official Chrome build, so sites that detect the exact browser may behave slightly differently

Measured on the same pages, same host, over CDP (requests to well-known ad/tracker hosts that actually loaded):

| site | Chrome (no blocker) | Helium (uBO) |
|---|---|---|
| nu.nl | 1 | 1 |
| telegraaf.nl | 7 | 2 |
| speedtest.net | 9 | 1 |
| theverge.com | 18 | 0 |

## The Solution

- **Neko base image + latest Helium release** (resolved from GitHub at build time; the weekly CI rebuild picks up new versions)
- **socat CDP proxy** forwarding `0.0.0.0:9223` → `127.0.0.1:9222` inside the container
- **Managed policy** in `/etc/chromium/policies/managed/` (Helium reads the Chromium location) with DevTools/CDP enabled

## Upstream

- Neko: <https://github.com/m1k1o/neko> (base image `ghcr.io/m1k1o/neko/base:3`)
- Helium: <https://github.com/imputnet/helium-linux> (`helium-bin` .deb from the releases)
- Chrome variant: <https://github.com/frankhommers/neko-chrome-cdp-docker>
- Client: stripped-down Vue frontend based on Neko's original client

See `UPSTREAM.md` for the Neko client tracking policy and reviewed baseline.

## Architecture

```text
CDP-compatible client (Playwright, Puppeteer, custom tooling)
    │
    └─ CDP ──→ host 127.0.0.1:9222
                  │
                  └─→ container 0.0.0.0:9223 (socat proxy)
                        │
                        └─→ Helium 127.0.0.1:9222 (non-headless)
                              │
                              └─→ Neko WebRTC UI
```

You can watch and interact with the browser session through Neko while automation controls the same Helium instance over CDP.

## Ports

- `9222/tcp` on host localhost only: CDP endpoint for automation clients
- `8080/tcp`: Neko Web UI, intended to be placed behind a reverse proxy
- `52000-52100/udp`: WebRTC media streams

## Quick Start

```bash
cp .env.example .env
# Edit .env with your Neko credentials, domain, and public IP
docker compose build
docker compose up -d
```

### Connect with Playwright

```ts
import { chromium } from "playwright";

const browser = await chromium.connectOverCDP("http://127.0.0.1:9222");
const context = browser.contexts()[0] ?? await browser.newContext();
const page = context.pages()[0] ?? await context.newPage();
await page.goto("https://example.com");
```

### Connect with Puppeteer

```js
import puppeteer from "puppeteer-core";

const browser = await puppeteer.connect({
  browserURL: "http://127.0.0.1:9222",
});

const page = await browser.newPage();
await page.goto("https://example.com");
```

## Prerequisites

- Docker with Compose v2
- A reverse proxy, for example Traefik, on a shared Docker network
- UDP ports `52000-52100` open for WebRTC
- `NEKO_NAT1TO1` / public IP configured so WebRTC can reach the host from outside

## Key Discoveries

These details are easy to miss when combining Neko, a Chromium browser, and CDP.

### Non-headless Chromium always binds CDP to 127.0.0.1

`--remote-debugging-address=0.0.0.0` is ignored in non-headless mode. Helium/Chromium still binds CDP to loopback. The socat proxy is the lightest-weight workaround.

### Neko's DevTools policy blocks CDP

Neko's browser images set `DeveloperToolsAvailability: 2` (disabled). This image ships its own policy in `/etc/chromium/policies/managed/policies.json` with it set to `0`. Helium reads policies from the Chromium location, not `/etc/opt/chrome`.

### Non-default user-data-dir required

Chromium browsers refuse `--remote-debugging-port` with the default profile data directory. The supervisord config uses:

```text
/home/neko/.config/helium-cdp
```

### Automation client compatibility depends on the Chromium/CDP version

Helium tracks Chromium stable closely (e.g. Helium 0.19.2.1 = Chromium 155). The image installs the latest Helium release at build time; pin a version with `--build-arg HELIUM_VERSION=<tag>`.

### Restart clients after rebuilding the browser container

When the Neko container is rebuilt or restarted, existing CDP/WebSocket connections become stale. Restart any automation process connected to the old browser instance.

## Persistent Browser Data

Helium's user data (shortcuts, preferences, cookies, extensions state) is stored in a Docker named volume (`helium-data`) mounted at:

```text
/home/neko/.config/helium-cdp
```

This means:

- `docker compose down` + `docker compose up`: data persists
- `docker compose down -v`: data is wiped because the volume is deleted
- image rebuild: data persists because the volume is independent of the image

### First-time setup

New Tab Page shortcuts cannot reliably be pre-seeded via the Dockerfile. The NTP has its own internal state that updates through the UI. After first deployment, add shortcuts manually via the "Add shortcut" button on the new tab page, or use browser automation through CDP. Once added, they persist in the volume.

## Browser Policy

The Dockerfile installs a clean managed policy (`policies.json`, at `/etc/chromium/policies/managed/`):

- DevTools/CDP enabled
- No bookmarks bar, password manager, autofill, or sync

uBlock Origin needs no policy: Helium ships it as a built-in component (id `blockjmkbacgjkknlgpkjjiijinjdanf`).

## Installing extensions

Besides the built-in uBlock Origin you can install extensions from the Chrome Web Store ("Add to Helium").

Helium downloads Web Store extensions through its own anonymous proxy ("Helium services", `services.helium.imput.net`). That needs two profile settings: the services consent (normally given on Helium's onboarding page, which never shows here because of `--no-first-run`) and **Allow extension downloads** (`helium.services.ext_proxy`).

`HELIUM_EXTENSION_INSTALLS` controls this at every container start:

| Value | Effect |
|---|---|
| `on` (default) | Consent and extension downloads are switched on. A toggle turned off by accident comes back after a restart. |
| `off` | Extension downloads are switched off; "Add to Helium" fails with "Extension downloads are disabled". |
| `default` | The profile is left alone; whatever is set in `helium://settings/privacy/services` applies. |

Other Helium services (filter list updates, spellcheck, bangs) are not touched and can be switched off in `helium://settings/privacy/services`.

## Violentmonkey (userscripts)

[Violentmonkey](https://violentmonkey.github.io/) is installed by default as its **Manifest V2** build, which Helium still supports. MV2 runs userscripts without Chrome's "Allow user scripts" toggle and has the full GM API (including `GM_xmlhttpRequest` and `document-start` timing). The MV2 build is not in the Chrome Web Store: Violentmonkey publishes it on GitHub with its own update manifest (`updates-crx.xml`), and the managed policy (`ExtensionInstallForcelist`) points there, so Helium installs and updates it from GitHub. It cannot be removed in `helium://extensions`.

| `HELIUM_VIOLENTMONKEY` | Effect |
|---|---|
| `on` (default) | Install Violentmonkey MV2. |
| `off` | Don't install it; the policy-installed copy is removed by Helium, including its userscripts. |

The MV2 build has a different extension ID (`fcickoepngcnapddnnmjpkmpekmfmpaa`) than the Web Store MV3 build (`jinjaccalgkegednnccohejagnlnfdag`, the default before). Scripts don't move over by themselves: export them in the old one (Settings → Backup) and import them in the new one.

## Client certificates (mTLS)

For sites or services that require a client certificate (e.g. a self-hosted password manager behind mTLS), mount a directory with your certificates. Helium's certificate store is rebuilt from that directory at every start; it is the single source of truth.

```yaml
volumes:
  - ./config/client-certs:/client-certs:ro
environment:
  CLIENT_CERT_AUTOSELECT: "https://vault.example.com"   # optional
```

| File | Meaning |
|---|---|
| `<name>.p12` / `<name>.pfx` | Client certificate with its private key. |
| `<name>.pass` | Password for `<name>.p12` (one line, no newline needed). Leave it out for an empty password. |
| `<name>.crt` / `<name>.pem` | Extra CA to trust, e.g. the CA that signed a private server certificate. |

- Add, replace or remove files, then restart the container. The log shows what was imported (`client certificate imported: ...`) and why something failed.
- `CLIENT_CERT_AUTOSELECT` (comma-separated URL patterns such as `https://vault.example.com` or `https://[*.]example.org`) makes Helium present the certificate without asking. That's needed for browser extensions and CDP automation, which can't answer the certificate prompt. Without it, Helium asks once per site in the UI.
- Certificates imported by hand in `chrome://certificate-manager` are **not** kept across restarts; put them in the directory instead.
- Keep the directory readable for root only (`chmod 700`, files `600`); the container reads it as root at start.
- Anyone who can control this browser (the Neko host, anything with CDP access) can use the certificate. Prefer a certificate issued for this browser only, so it can be revoked on its own.

## Audio

Audio is force-disabled at two levels, so no `neko.yaml` audio config is needed:

1. Browser flags: `--mute-audio`, `--disable-audio-output`, `--disable-audio-input`
2. PulseAudio disabled: Dockerfile sets `autospawn = no` and `daemon-binary = /bin/true`

## Static-screen CPU: damagegate

Neko captures the screen at a fixed 25 fps and feeds every frame to the encoder, even when nothing changed. A connected viewer on a static 1080p screen costs about half a CPU core.

This image ships a small GStreamer element, `damagegate` (`gst-damagegate/`, compiled in the Dockerfile), placed right after `ximagesrc`. It does not compare pixels: it listens to the X server's **XDamage** events (plus pointer and cursor changes) and drops frames when nothing changed.

- change on screen → frames pass at full framerate, and keep passing for 200 ms after the last change
- static screen → about 1 frame per second, as a keyframe, so joining viewers get a picture quickly
- new viewer → the next frame passes and is forced to be a keyframe
- if X or XDamage is not available it becomes a plain passthrough

It is enabled through the video pipeline in `neko.yaml` (see `neko.yaml.example`); remove `! damagegate` to disable it.

Measured with a connected client, 1080p VP8, same host:

| | neko default | with damagegate |
|---|---|---|
| static screen | ~55% of a core, 25 fps | ~12-17%, ~1.5 fps |
| animation on screen | ~62%, 25 fps | ~65%, 25 fps |
| screen change → visible in client | ~110 ms | ~50 ms (median) |
| viewer joining a static screen | ~1.2 s | ~1.2-1.4 s |

Properties: `max-interval-ms` (heartbeat, default 1000), `keyframe-interval-ms` (default 1000), `hold-ms` (default 200), `track-pointer` (default true), `enabled`.

## Branding (page title and favicon)

The browser tab shows the page title and favicon from `client/public/`. Both are generated from `branding/logo.png` by `scripts/brand.py` (needs ImageMagick):

```bash
python3 scripts/brand.py . "Neko · Helium" "#3b50d8" path/to/logo.png
```

To override only the title at runtime (e.g. to tell several deployments apart), set `PAGE_TITLE`:

```yaml
environment:
  PAGE_TITLE: "Aivy · Helium"
```

## Neko Lite Client

The `client/` directory contains a stripped-down Vue frontend based on Neko's original client. Chat, emotes, file transfer, members list, sidebar, and about dialog are removed. The Dockerfile uses a multi-stage build to compile and serve this client instead of the default Neko UI.

### Viewing controls

Neko keeps capturing and encoding the screen for as long as a viewer is connected, and every connected viewer is one more stream. The settings menu (gear icon) has a **Viewing** section to keep that in check. Settings are stored per browser in `localStorage`.

| Setting | Default | What it does |
|---|---|---|
| One stream at a time | on | When another viewer connects, this stream pauses with a *Take back* button. Taking back pauses the other viewer. |
| Pause when idle | on, 5 min | Pause after N minutes without mouse, keyboard, wheel or touch input (1–60 min). |
| Pause in background | on, 2 min | Pause after the tab has been hidden for N minutes (or directly). Resumes by itself when you return. |
| Max viewing time | off, 60 min | Pause after N minutes of viewing, even while active (15 min – 4 h). |

The toolbar also has a **pause** button. While paused, the WebRTC session is closed so the server stops encoding; the browser and CDP automation keep running. Switch the timers off to passively watch a long automation run.

## Files

```text
├── Dockerfile              # Multi-stage: Vue build + damagegate + Helium + socat + policy
├── docker-compose.yml      # Neko container config + persistent volume
├── docker-compose.yml.example
├── neko.yaml.example       # Neko config template
├── .env.example            # Credentials and deployment settings template
├── policies.json           # Managed policy (DevTools, clean defaults)
├── helium.conf             # Supervisord: Helium with CDP flags + openbox
├── openbox.xml             # Window manager config (Helium window undecorated, maximized)
├── gst-damagegate/         # GStreamer element that drops unchanged frames
├── cdp-proxy.conf          # Supervisord: socat CDP proxy
└── client/                 # Neko Lite Vue frontend (stripped)
```

## License

The project-specific Docker/configuration code is licensed under MIT. Helium and uBlock Origin are installed from their official releases under their own licenses (both GPL-3.0); see `THIRD_PARTY_NOTICES.md`. The Neko-derived client code in `client/` remains under Apache License 2.0; see `THIRD_PARTY_NOTICES.md` and `LICENSES/Apache-2.0.txt`.
