# homelab-infra

Declarative deployment for the home server. This repo is the **single source of
truth for what runs on the Proxmox box** — one directory per service, each a
Docker Compose file plus its config. You author here (workstation), push, and
the docker host pulls and runs.

## Mental model

- **Containers are disposable; data is not.** Every stateful service bind-mounts
  its data into a host folder (`./data`, `./config`) — those are gitignored and
  backed up on the host, never committed.
- Each service declares the same four things: **image, storage, config,
  networking.** Once that clicks, adding a service is filling in the same blanks.
- **One front door:** Caddy owns ports 80/443. Web services join the `edge`
  network; Caddy reaches them by container name. Adding a service = one line in
  `caddy/Caddyfile`.
- **One database:** a single Postgres instance on the `data` network, one DB +
  user per app. Never a Postgres per app.

## Layout

```
caddy/         reverse proxy (front door)        → edge
postgres/      shared database                   → data
jellyfin/      media server (Intel iGPU xcode)   → edge
bootstrap.sh   one-time network creation
```

## First-time setup (on the docker host)

```bash
git clone git@github.com:Drew-Meseck/homelab-infra.git
cd homelab-infra
./bootstrap.sh                            # creates the `edge` and `data` networks

# per service: copy the example env, fill in real values
cp postgres/.env.example postgres/.env && $EDITOR postgres/.env
cp jellyfin/.env.example jellyfin/.env && $EDITOR jellyfin/.env

# bring services up
(cd caddy    && docker compose up -d)
(cd postgres && docker compose up -d)
(cd jellyfin && docker compose up -d)
```

## The deploy loop (everything, forever)

```bash
git pull                                  # get the updated declaration
cd <service> && docker compose up -d      # Docker reconciles reality to it
```

- **Update a service:** bump its `image:` tag, commit + push here, `git pull` on
  the host, `docker compose up -d`.
- **Roll back:** `git revert`, pull, `up -d`.

Git history is your changelog and your undo button.

## Secrets roadmap

- **Stage 1 (now):** `.env` files, gitignored. Only `*.env.example` (safe
  placeholders) is committed. Simple, and it makes clear *where* secrets flow —
  into the container as env vars.
- **Stage 2 (next):** SOPS + age — encrypt secret *values* and commit them, so
  the whole repo, secrets included, is reproducible from git. Planned exercise.

## Service notes

### Jellyfin — iGPU passthrough
The compose passes `/dev/dri` into the container, but the **Proxmox LXC must
expose it first**. On the Proxmox host, add to the LXC config
(`/etc/pve/lxc/<id>.conf`):

```
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

Restart the LXC, then set `group_add` in `jellyfin/compose.yml` to the host's
`render` GID (`getent group render | cut -d: -f3`). After first boot, enable
hardware acceleration (VAAPI or QSV) in Jellyfin → Dashboard → Playback.

### Postgres — one database + user per app
Don't reuse the superuser for apps. When a service needs a DB:

```bash
docker compose exec postgres psql -U postgres -c \
  "CREATE ROLE mealie LOGIN PASSWORD '...'; CREATE DATABASE mealie OWNER mealie;"
```

Then add `data` to that app's `networks:` and point it at host `postgres:5432`.

## DNS & TLS

- Point `*.home.lan` (or your chosen base domain) at the docker host's IP via
  your router / Pi-hole / a hosts file.
- Caddy starts on plain HTTP for zero cert friction on the LAN. To upgrade to
  HTTPS with Caddy's own local CA, see the note at the top of `caddy/Caddyfile`.
