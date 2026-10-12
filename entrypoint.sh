#!/bin/bash
# Route all internet traffic via WireGuard (home IP) for sites that block datacenter IPs
# Keep WG endpoint routed directly to avoid routing loop
WG_GW="${WG_GATEWAY:-}"
WG_ENDPOINT="${WG_ENDPOINT:-}"
PROXY_GW="${PROXY_GATEWAY:-}"

if [ -n "$WG_GW" ] && [ -n "$WG_ENDPOINT" ] && [ -n "$PROXY_GW" ]; then
  if ip route show default | grep -q "$WG_GW"; then
    echo "[entrypoint] WG default route already set"
  else
    # Route WG endpoint via proxy network (prevent loop)
    ip route add "$WG_ENDPOINT/32" via "$PROXY_GW" 2>/dev/null || true
    # Switch default route to WireGuard
    ip route replace default via "$WG_GW"
    echo "[entrypoint] Default route set via WG ($WG_GW), endpoint $WG_ENDPOINT via $PROXY_GW"
  fi
else
  echo "[entrypoint] WG routing skipped (set WG_GATEWAY, WG_ENDPOINT, PROXY_GATEWAY to enable)"
fi

# Optional page title override (browser tab + installed web app name)
if [ -n "${PAGE_TITLE:-}" ]; then
  python3 - "$PAGE_TITLE" <<'PY'
import html, json, re, sys
t = sys.argv[1]
p = "/var/www/index.html"; s = open(p).read()
s = re.sub(r"<title>.*?</title>", "<title>" + html.escape(t) + "</title>", s, count=1)
open(p, "w").write(s)
p = "/var/www/site.webmanifest"; m = json.load(open(p))
m["name"] = m["short_name"] = t
json.dump(m, open(p, "w"), indent=4)
PY
  echo "[entrypoint] page title set to: ${PAGE_TITLE}"
fi

# Helium only installs Web Store extensions through its "Helium services" proxy,
# which is gated on a consent the onboarding page normally asks for. That page is
# skipped (--no-first-run), so record the consent in the profile once. Set
# HELIUM_SERVICES_CONSENT=0 to leave it untouched (extension installs then stay off).
if [ "${HELIUM_SERVICES_CONSENT:-1}" = "1" ]; then
  su "${USER:-neko}" -s /bin/sh -c 'python3 - /home/neko/.config/helium-cdp/Default/Preferences' <<'PY'
import json, os, sys
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except (FileNotFoundError, ValueError):
    d = {}
svc = d.setdefault("helium", {}).setdefault("services", {})
if svc.get("user_consented") is not True:
    svc["user_consented"] = True
    tmp = p + ".tmp"
    json.dump(d, open(tmp, "w"))
    os.replace(tmp, p)
    print("[entrypoint] Helium services consent recorded (Web Store installs enabled)")
PY
fi

exec /usr/bin/supervisord -c /etc/neko/supervisord.conf
