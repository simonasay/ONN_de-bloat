# onn 4K de-bloat

Scripts that clean up an **onn 4K Streaming Box (Google TV, Android 14)** from a Mac or Linux computer over Wi-Fi:

- **No ads:** removes the Google TV home screen (with its sponsored rows), the recommendation and partner-promo services, and Android's ad-measurement services. On top of that, an ad-blocking Private DNS covers every app.
- **Projectivy Launcher on boot:** it becomes the home screen, so it opens on power-on and when you press Home.
- **Trackers off:** removes the telemetry, personalization and federated-learning services, and turns off location, background scanning and error reporting.
- **Mic off, typing on:** Google search still works by typing with the remote. The microphone is blocked for Google search/Assistant, Gboard, Cast and Play services, so pressing the mic button does nothing.
- **Kept:** Chromecast, the Play Store, Google search, the keyboard, the remote and Settings.

Nothing is rooted or flashed. Apps are removed only for your user account (`pm uninstall --user 0`) or disabled, so **everything can be undone**. See [Undo](#undo).

---

## 1. Prepare the TV (one time)

1. **Turn on Developer options:** go to *Settings → System → About* and click **Android TV OS build** 7 times, until it says you're a developer.
2. Go to *Settings → System → Developer options* and turn on **USB debugging**.
3. Find the TV's IP address under *Settings → Network & Internet → (your Wi-Fi)*, for example `192.168.1.50`.

## 2. Prepare your computer (one time)

```bash
# Mac
brew install android-platform-tools
```
```bash
# Linux (Debian/Ubuntu)
sudo apt install adb
```
```bash
git clone <this repo> && cd ONN_de-bloat
```

## 3. Connect

```bash
scripts/00-connect.sh 192.168.1.50
```
A prompt appears on the TV: **Allow debugging?** Tick **Always allow** and select OK.

> If the connection is refused, use *Developer options → Wireless debugging* instead. Pair once with the code it shows, then connect to the IP:port it shows:
> ```bash
> scripts/00-connect.sh pair 192.168.1.50:37123
> ```
> ```bash
> scripts/00-connect.sh 192.168.1.50:41234
> ```

## 4. Preview, then run

```bash
./debloat-all.sh --dry-run    # prints every command, changes nothing
```
```bash
./debloat-all.sh              # does it, asking before each step
```

The run goes through these steps:

| Step | Script | What it does |
|---|---|---|
| 1 | `scripts/01-backup.sh` | Saves your package list and settings to `backups/<time>/` (read-only on the TV) |
| 2 | `scripts/02-debloat.sh` | Removes everything in `packages/ads-recommendations.txt`, `telemetry.txt` and `bloat-apps.txt` |
| 3 | `scripts/03-privacy.sh` | Blocks the mic, sets ad-blocking DNS (`dns.adguard-dns.com`), turns off location, scanning and error reports |
| 4 | `scripts/04-launcher.sh` | Opens Projectivy in the Play Store for you to install, makes it home, **checks** it's home, then disables the stock launcher, and offers to reboot |

Useful options for `debloat-all.sh` (each script also takes `--help`):

- `--keep-apps`: keep YouTube, Netflix and the other preinstalled apps.
- `--keep-stock`: make Projectivy home but leave the stock launcher enabled.
- `--apk FILE`: install Projectivy from an APK instead of the Play Store.
- `--dns HOST` / `--no-dns`: pick another DNS (e.g. `dns.nextdns.io`, `family.adguard-dns.com`) or skip DNS.
- `--fast-animations`: snappier menus (0.5x animations).
- `-y`: don't ask between steps.

You can also run any `scripts/0X-*.sh` on its own.

## 5. Finish on the TV

ADB can't change these, so do them with the remote:

- **Projectivy settings → Override current launcher → ON.** This is a backup in case a system update resets the home app.
- Add the Android **Settings** app and **Google search** to a Projectivy row. With the stock launcher gone, that's how you get to them.
- *Settings → Privacy → Ads →* **Delete advertising ID**.
- *Settings → Privacy → Usage & diagnostics →* **Off**.
- *Settings → Privacy → Google Assistant →* turn off personal results.
- On your phone, at myactivity.google.com, pause **Web & App Activity** and **YouTube History**.

---

## Customizing what gets removed

The lists in `packages/` are plain text: one package per line, and `#` starts a comment. Comment out a line to keep that app, or add a package to remove it. Packages that aren't on your box are skipped.

`packages/NEVER-REMOVE.txt` is a guard list. The scripts refuse to touch anything on it, even if it also appears on another list. It covers Settings, the remote, the keyboard, Play services, the Play Store, Cast, search and Projectivy.

To see everything installed on your box, look at `backups/<time>/packages-installed.txt` after step 1.

## Undo

```bash
scripts/restore.sh --from-backup      # put back exactly what the latest backup had
```
```bash
scripts/restore.sh --launcher         # just bring back the stock Google TV home screen
```
```bash
scripts/restore.sh --privacy          # just give the mic back and reset DNS/location
```
For a single app:
```bash
adb shell cmd package install-existing <package>
```
Last resort: *Settings → System → Reset* (factory reset) restores everything.

## After a system update

Updates can re-enable or reinstall some packages, or give the mic back. Run `./debloat-all.sh` again: it's safe to re-run, and it skips anything already removed.

## Testing the scripts without a TV

```bash
tests/run-tests.sh
```
This runs the whole flow against `tests/fake-adb`, a pretend onn box. The tests check:
- dry run changes nothing;
- the kept apps stay;
- the stock launcher is only disabled after Projectivy is confirmed as home;
- restore puts everything back.
