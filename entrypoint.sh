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

# Remove stale Chromium profile locks. They hold the hostname of the container that
# created them; after a hard stop/crash the new container (new hostname) would refuse
# the profile ("profile appears to be in use by another computer"). No browser is
# running yet at this point, so the locks are always stale here.
for f in SingletonLock SingletonCookie SingletonSocket; do
  rm -f "/home/neko/.config/helium-cdp/$f"
done

# Web Store extension installs.
# Helium only downloads Web Store extensions through its "Helium services" proxy,
# which needs two profile prefs: the services consent (normally set by Helium's
# onboarding page, which --no-first-run skips) and "Allow extension downloads"
# (helium.services.ext_proxy).
#   HELIUM_EXTENSION_INSTALLS=on       (default) switch both on at every start
#   HELIUM_EXTENSION_INSTALLS=off      switch extension downloads off at every start
#   HELIUM_EXTENSION_INSTALLS=default  leave the profile alone; Helium's own settings decide
EXT_MODE="$(printf '%s' "${HELIUM_EXTENSION_INSTALLS:-on}" | tr 'A-Z' 'a-z')"
case "$EXT_MODE" in
  on|off)
    su "${USER:-neko}" -s /bin/sh -c "python3 - /home/neko/.config/helium-cdp/Default/Preferences $EXT_MODE" <<'PY'
import json, os, sys
p, mode = sys.argv[1], sys.argv[2]
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except (FileNotFoundError, ValueError):
    d = {}
svc = d.setdefault("helium", {}).setdefault("services", {})
want = {"user_consented": True, "ext_proxy": True} if mode == "on" else {"ext_proxy": False}
changed = [k for k, v in want.items() if svc.get(k) is not v]
if changed:
    svc.update(want)
    tmp = p + ".tmp"
    json.dump(d, open(tmp, "w"))
    os.replace(tmp, p)
print("[entrypoint] Helium extension installs: %s%s" % (mode, " (changed: " + ", ".join(changed) + ")" if changed else ""))
PY
    ;;
  default)
    echo "[entrypoint] Helium extension installs: default (profile left untouched)"
    ;;
  *)
    echo "[entrypoint] WARNING: unknown HELIUM_EXTENSION_INSTALLS='${HELIUM_EXTENSION_INSTALLS}', use on|off|default; leaving profile untouched"
    ;;
esac

exec /usr/bin/supervisord -c /etc/neko/supervisord.conf
