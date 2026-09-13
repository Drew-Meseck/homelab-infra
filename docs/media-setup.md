# Media drive setup — WD Elements 4 TB → Jellyfin

Repurpose the external USB drive as the media library, mount it on the Proxmox
host (`pve`), bind-mount it into the `docker-prod` LXC (VMID 100), and bring up
Jellyfin. Also enables the Intel iGPU for hardware transcoding.

> **Safety gate:** do NOT reformat until the old backups are copied to their new
> home AND you've opened a few files to confirm they're intact. A copy you
> haven't verified is not a backup.

---

## 1. Reformat the drive as ext4  (DESTRUCTIVE — do on the workstation)

Do this while the drive is on the workstation, where it's unambiguously `sdd`
(label `Elements`, 4.5 T). Doing it here avoids any chance of wiping a disk on
`pve` by mistake.

```bash
# CONFIRM the target first — it MUST be the 4.5T Elements drive:
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT

sudo umount /mnt/elements 2>/dev/null
sudo wipefs -a /dev/sdd                                   # clear old NTFS signature
sudo parted -s /dev/sdd mklabel gpt
sudo parted -s /dev/sdd mkpart media ext4 0% 100%
sudo mkfs.ext4 -L media /dev/sdd1                         # ext4, label "media"
```

`/dev/sdd1` is now an empty ext4 filesystem labelled `media`.

---

## 2. Move the drive to the server and mount it  (on `pve`)

Plug it into a USB 3 port on the Proxmox laptop, then:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL          # find the ext4 "media" partition (e.g. sdb1)
blkid /dev/sdX1                          # copy its UUID

mkdir -p /mnt/media

# Mount by UUID so it survives device-letter changes. `nofail` = pve still boots
# if the USB drive is absent.
echo 'UUID=<PASTE-UUID> /mnt/media ext4 defaults,nofail,x-systemd.device-timeout=10 0 2' >> /etc/fstab
mount -a
findmnt /mnt/media                       # confirm it mounted
```

Make it readable by the (unprivileged) container's mapped users. Media is served
read-only, so world-readable is the simplest correct choice:

```bash
chmod -R a+rX /mnt/media
```

---

## 3. Bind-mount media + pass the iGPU into LXC 100  (on `pve`)

Edit `/etc/pve/lxc/100.conf` and add:

```
# bind the media directory into the container (read-write on host so you can add files)
mp0: /mnt/media,mp=/mnt/media

# pass the Intel iGPU through for hardware transcoding
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

Restart the container so the changes take effect:

```bash
pct reboot 100
```

Verify inside the container:

```bash
pct exec 100 -- ls -l /mnt/media          # media dir visible
pct exec 100 -- ls -l /dev/dri            # renderD128 present
pct exec 100 -- stat -c '%g' /dev/dri/renderD128   # <-- the render GID for compose
```

---

## 4. Configure and start Jellyfin  (in the LXC, in ~/homelab-infra)

```bash
cp jellyfin/.env.example jellyfin/.env
# edit jellyfin/.env: MEDIA_ROOT=/mnt/media  and your TZ
```

Set the render GID from step 3 in `jellyfin/compose.yml` under `group_add:`
(replace the `989` placeholder with the number `stat` printed). Then:

```bash
# drop a test file in so the library isn't empty, e.g.:
mkdir -p /mnt/media/movies
# ...copy a sample video into /mnt/media/movies...

(cd jellyfin && docker compose up -d)
docker ps                                  # jellyfin should be Up
```

---

## 5. Reach the Jellyfin web UI

Jellyfin is behind Caddy on the `edge` network (not published directly). Quickest
way to test before local DNS exists — add a hosts entry on the **workstation**:

```bash
echo '10.0.0.11 jellyfin.home.lan' | sudo tee -a /etc/hosts
```

Then browse to **http://jellyfin.home.lan** → run the setup wizard → add a library
pointing at `/media` (that's where the compose maps `/mnt/media`). In
Dashboard → Playback, enable **VAAPI** (or QSV) hardware acceleration.

(Proper LAN-wide names come later with a local DNS resolver; the hosts entry is
just for this first test.)

---

## Notes / gotchas
- **Verify the render GID** — it's whatever owns `/dev/dri/renderD128` in the
  container, found via `stat` in step 3. Guessing it wrong = Jellyfin can't use
  the GPU.
- **Permissions:** if Jellyfin can't see files, re-check `chmod -R a+rX /mnt/media`
  on the host (the container's users are mapped, so files must be world-readable).
- **USB always-on:** keep the drive plugged and powered; `nofail` means pve won't
  hang at boot if it's missing, but Jellyfin's library will be empty until it's back.
