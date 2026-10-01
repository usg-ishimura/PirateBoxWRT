# PirateBox for OpenWrt

File sharing, forum and live chat: anonymous, local and offline. Lightweight static frontend (light/dark theme saved in the browser), backend written in ucode running on `uhttpd`. No IP or request logging.

Requires OpenWrt 22.03 or later with `opkg` (up to 24.10), including GL.iNet firmware based on 22.03. Depends on `ucode`, `ucode-mod-fs` and `uhttpd`.

## Build

```sh
./build.sh                                            # dist/piratebox_1.0.0-1_all.ipk
ARCH=mips_24kc RELEASE=22.03.4 ./build.sh --offline   # dist/piratebox-offline_1.0.0-1_mips_24kc.tar.gz
```

The `--offline` bundle (needs `curl` on your computer) contains the `.ipk` plus the dependencies downloaded from the official OpenWrt feed and verified with SHA256, so the router does not need internet access. `ARCH` is the router architecture (`opkg print-architecture`, e.g. `mips_24kc` for the GL-AR300M) and `RELEASE` is the OpenWrt version (`/etc/openwrt_release`).

Alternatively, with the OpenWrt SDK: copy this folder to `package/piratebox` and run `make package/piratebox/compile`.

## Install

**Without internet on the router** (works on GL.iNet and plain OpenWrt):

```sh
scp dist/piratebox-offline_*.tar.gz root@192.168.1.1:/tmp/
ssh -t root@192.168.1.1 "cd /tmp && tar xzf piratebox-offline_*.tar.gz && sh piratebox-offline/install.sh"
```

The script installs only the dependencies that are not already present, then PirateBox.

**With internet on the router:**

```sh
scp dist/piratebox_*.ipk root@192.168.1.1:/tmp/
ssh -t root@192.168.1.1 "opkg update && opkg install /tmp/piratebox_*.ipk"
```

On GL.iNet the router IP is `192.168.8.1`. During installation you are asked for:

1. **Access point SSID** (open network, created on every Wi-Fi radio)
2. **Local hostname** mapped to the router IP (default `pirate.box`)
3. **Path** where files, forum and chat are stored (default `/mnt/sda1/piratebox` if a USB drive is present, otherwise `/srv/piratebox`)

At the end a summary of the values you entered is shown. Then just connect to the SSID and open `http://<hostname>`.

Non-interactive: prefix `PB_SSID="Pirate Net" PB_HOSTNAME=pirate.box PB_PATH=/mnt/sda1/piratebox` to `opkg install` or to `sh piratebox-offline/install.sh`.

## Management

| Action | Command |
| --- | --- |
| Reconfigure | `piratebox-setup` |
| Remove | `opkg remove piratebox` (data stays in the chosen path) |
| Delete a file | `rm <path>/files/<name>` |
| Clear chat / forum | `rm <path>/chat.jsonl*` / `rm <path>/forum/*` |
| LuCI panel | `http://192.168.1.1:8080` (port 80 belongs to PirateBox) |

## Notes

- Use a USB drive for the data: the router flash is small (uploads are rejected when less than 2 MB are free). The per-file limit is `max_upload_mb` in `/etc/config/piratebox` (default 512).
- Every DNS domain points to the router so that phones open the page on their own (captive portal). To disable it: `uci set piratebox.main.captive_dns=0 && piratebox-setup`.
- If port 80 is used by `nginx` (GL.iNet firmware), the setup moves it to 8080 by editing `/etc/nginx/conf.d/gl.conf` (backup in `gl.conf.piratebox`, restored by `opkg remove`): the GL.iNet panel becomes `http://192.168.8.1:8080`. The GL.iNet firmware may rewrite that file at boot, so the PirateBox init script re-applies the change for the first minute after every boot (`piratebox-setup --ports`).
- If Wi-Fi does not start, set the country code in LuCI (Network > Wireless).
- Uploads ending in `.html`, `.svg`, `.js`, `.xml` are renamed to `.txt` so that no code runs in other users' browsers.
- Tapping an image, video, audio, PDF or text file opens a preview in a modal. Audio and video are served by `/cgi-bin/get` (it supports HTTP Range requests, needed on iOS and for seeking); playback depends on the browser codecs (MP4/H.264, WebM, MP3, AAC, OGG).
- The router has no reliable clock: forum and chat times are those of the participants' devices.

## Layout

```
root/                 files installed on the router (web, ucode CGI, init, setup)
control/              .ipk metadata and scripts
offline/install.sh    installer included in the offline bundle
PirateBox-logo.svg    logo (copied into the web app at build time)
build.sh, Makefile    standalone build / OpenWrt SDK
```
