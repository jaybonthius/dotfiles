---
name: tplink-router-reboot
description: Reproduce TP-Link router reboot discovery/flow for local routers such as Archer AX50 at 192.168.0.1. Use when asked to reboot, inspect, automate, curl, or document TP-Link router reboot behavior. Always ask for the router password and explicit reboot confirmation; never store credentials.
---

# TP-Link Router Reboot

Use this when the user wants to inspect or reboot a TP-Link home router, especially
`http://192.168.0.1` / Archer AX50 style firmware.

## Safety rules

- **Do not reboot without explicit confirmation immediately before the final action.**
- Reboot will interrupt LAN/Wi-Fi/internet for ~1-3 minutes.
- **Do not put the router password in files, commands shown to the user, or durable notes.**
- Ask the user for the current router password if needed.
- Stop at the confirmation dialog unless the user clearly says to proceed.
- Never click/trigger factory reset; only reboot.

## Known local findings

On this setup, `192.168.0.1` identified as:

- Model: **TP-Link Archer AX50**
- Login page: `http://192.168.0.1/webpages/login.html`
- Newer LuCI-style API base:
  - `/cgi-bin/luci/;stok=<session-token>/...`
- Reboot API path after login:
  - `POST /cgi-bin/luci/;stok=<stok>/admin/system?form=reboot`
- Old/simple TP-Link endpoint did **not** work:
  - `/userRpm/SysRebootRpm.htm?Reboot=Reboot` returned 404.

The reboot API is not a simple password curl. POST data is encrypted/signed by
TP-Link frontend JavaScript (`sign=...&data=...`) using session AES/RSA state via
`$.su.Proxy` / `tpEncrypt`.

## Preferred workflow: agent_browser

1. Open router UI:
   ```text
   agent_browser open http://192.168.0.1
   agent_browser snapshot -i
   ```
2. Ask user for password if not already provided in the current conversation.
3. Fill password and log in.
4. If **Login Conflict** appears, ask/confirm if it is OK to continue and kick out
   the existing session, then click **Continue**.
5. After login, verify the page shows **Wireless Router Archer AX50** and top
   control links including **Reboot**.
6. For dry-run/probe: click **Reboot** only to open the confirmation dialog, then
   report that the next step is **Yes**. Click **No** if stopping.
7. For actual reboot: only after explicit final confirmation, click **Yes**.

## Optional in-page API trigger

After successful login, instead of clicking the UI, the page context can create a
TP-Link proxy using the active session/encryptor. This is equivalent to pressing
Yes and will reboot, so only run after final confirmation:

```js
await new Promise((resolve) => {
  const p = new $.su.Proxy({
    url: $.su.url('/admin/system?form=reboot'),
    autoLoad: false
  });
  p.write({},
    (data) => resolve({ success: true, data }),
    (errorcode, others, data) => resolve({ success: false, errorcode, others, data }),
    (xhr, status, type) => resolve({ success: false, status, type })
  );
});
```

Prefer the visible UI confirmation flow unless the user specifically asks for API
reproduction.

## Curl/API investigation notes

Useful non-rebooting probes:

```bash
python3 - <<'PY'
import urllib.request
for url in ['http://192.168.0.1/', 'http://192.168.0.1/webpages/login.html']:
    with urllib.request.urlopen(url, timeout=5) as r:
        print(url, r.status, r.geturl(), r.headers.get('Content-Type'))
        print(r.read(300).decode('utf-8', 'replace'))
PY
```

Unauthenticated endpoints observed on this firmware:

```text
POST /cgi-bin/luci/;stok=/login?form=keys
POST /cgi-bin/luci/;stok=/login?form=auth
POST /cgi-bin/luci/;stok=/login?form=get_deviceInfo
POST /cgi-bin/luci/;stok=/login?form=check_factory_default
```

with form body:

```text
operation=read
```

Do not expect a direct curl reboot unless you reproduce TP-Link's JS login,
`stok`, `encryptorAES`, `encryptorSeq`, `encryptorHash`, RSA key, and encrypted
`sign/data` generation.
