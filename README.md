# PirateBox per OpenWrt

File sharing, forum e chat live: anonimi, locali e offline. Frontend statico leggero (tema chiaro/scuro salvato nel browser), backend in ucode su `uhttpd`. Nessun log di IP o richieste.

Richiede OpenWrt 22.03 o successivo con `opkg` (fino a 24.10), anche nei firmware GL.iNet basati su 22.03. Dipende da `ucode`, `ucode-mod-fs` e `uhttpd`.

## Compilare

```sh
./build.sh                                            # dist/piratebox_1.0.0-1_all.ipk
ARCH=mips_24kc RELEASE=22.03.4 ./build.sh --offline   # dist/piratebox-offline_1.0.0-1_mips_24kc.tar.gz
```

Il bundle `--offline` (serve `curl` sul PC) contiene l'`.ipk` e le dipendenze scaricate dal feed ufficiale OpenWrt e verificate con SHA256, cosi' il router non ha bisogno di internet. `ARCH` e' quella del router (`opkg print-architecture`, ad es. `mips_24kc` per GL-AR300M), `RELEASE` la versione di OpenWrt (`/etc/openwrt_release`).

In alternativa, con l'SDK OpenWrt: copia questa cartella in `package/piratebox` e lancia `make package/piratebox/compile`.

## Installare

**Senza internet sul router** (funziona su GL.iNet e OpenWrt puro):

```sh
scp dist/piratebox-offline_*.tar.gz root@192.168.1.1:/tmp/
ssh -t root@192.168.1.1 "cd /tmp && tar xzf piratebox-offline_*.tar.gz && sh piratebox-offline/install.sh"
```

Lo script installa solo le dipendenze non ancora presenti, poi la PirateBox.

**Con internet sul router:**

```sh
scp dist/piratebox_*.ipk root@192.168.1.1:/tmp/
ssh -t root@192.168.1.1 "opkg update && opkg install /tmp/piratebox_*.ipk"
```

Su GL.iNet l'IP del router e' `192.168.8.1`. Durante l'installazione vengono chiesti:

1. **SSID** dell'access point (rete aperta, creata su tutte le radio Wi-Fi)
2. **Nome host locale** mappato sull'IP del router (default `pirate.box`)
3. **Percorso** dove salvare file, forum e chat (default `/mnt/sda1/piratebox` se c'e' un disco USB, altrimenti `/srv/piratebox`)

A fine installazione viene mostrato un riepilogo dei valori inseriti. Poi basta collegarsi all'SSID e aprire `http://<hostname>`.

Senza domande: anteponi `PB_SSID="Pirate Net" PB_HOSTNAME=pirate.box PB_PATH=/mnt/sda1/piratebox` a `opkg install` o a `sh piratebox-offline/install.sh`.

## Gestione

| Azione | Comando |
| --- | --- |
| Riconfigurare | `piratebox-setup` |
| Rimuovere | `opkg remove piratebox` (i dati restano nel percorso scelto) |
| Eliminare un file | `rm <percorso>/files/<nome>` |
| Svuotare chat / forum | `rm <percorso>/chat.jsonl*` / `rm <percorso>/forum/*` |
| Pannello LuCI | `http://192.168.1.1:8080` (la porta 80 e' della PirateBox) |

## Note

- Usa un disco USB per i dati: la flash del router e' piccola (se mancano meno di 2 MB liberi gli upload vengono rifiutati). Il limite per file e' `max_upload_mb` in `/etc/config/piratebox` (default 512).
- Tutti i domini DNS puntano al router, cosi' il telefono apre la pagina da solo (captive portal). Per disattivarlo: `uci set piratebox.main.captive_dns=0 && piratebox-setup`.
- Se la porta 80 e' occupata da `nginx` (firmware GL.iNet), il setup lo sposta sulla 8080 modificando `/etc/nginx/conf.d/gl.conf` (backup in `gl.conf.piratebox`, ripristinato con `opkg remove`): il pannello GL.iNet diventa `http://192.168.8.1:8080`.
- Se il Wi-Fi non parte, imposta il codice paese in LuCI (Rete > Wireless).
- Gli upload `.html`, `.svg`, `.js`, `.xml` vengono rinominati `.txt` per evitare codice eseguito nel browser degli altri utenti.
- Toccando un file immagine, video, audio, PDF o di testo si apre un'anteprima in un modale. Audio e video passano da `/cgi-bin/get` (supporta gli HTTP Range, necessari su iOS e per spostarsi nel brano); la riproduzione dipende dai codec del browser (MP4/H.264, WebM, MP3, AAC, OGG).
- Il router non ha un orologio affidabile: gli orari di forum e chat sono quelli dei dispositivi dei partecipanti.

## Struttura

```
root/                 file installati sul router (web, CGI ucode, init, setup)
control/              metadati e script dell'.ipk
offline/install.sh    installer incluso nel bundle offline
PirateBox-logo.svg    logo (copiato nell'app web in fase di build)
build.sh, Makefile    build standalone / SDK OpenWrt
```
