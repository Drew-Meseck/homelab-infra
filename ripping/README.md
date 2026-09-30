# ripping

Disc-to-Jellyfin pipeline. Runs on the **workstation** (the box with the
Blu-ray drive), not the docker host: rip a disc with MakeMKV, compress with
NVENC HEVC, and rsync the result into the media server's library.

```
insert disc → MakeMKV rip → HandBrake (NVENC HEVC 8-bit) → rsync → server:/mnt/media
                  └ staged under $STAGE, cleaned up after a successful upload ┘
```

## Why these choices

- **NVENC HEVC, 8-bit.** Encodes on the workstation's GPU (near real-time).
  8-bit HEVC direct-plays on most clients; when a client can't, Jellyfin's Intel
  iGPU (QSV) transcodes it cheaply. 10-bit would force transcoding far more often.
- **Original audio + an AAC stereo track.** TVs/apps direct-play the lossless
  original; browsers fall back to AAC without a server audio transcode.
- **MakeMKV only remuxes** (lossless, ~20–40 GB/disc); HandBrake is where the
  size actually comes down.

## Install (on the workstation)

```bash
sudo dnf install -y HandBrake-cli          # native build → reliable NVENC
                                           # (MakeMKV is the com.makemkv.MakeMKV flatpak)
install -m755 ripping/rip ~/.local/bin/rip
mkdir -p ~/.config/rip && cp ripping/config.example ~/.config/rip/config
$EDITOR ~/.config/rip/config               # set SERVER / paths if they differ
ssh-copy-id youruser@your-media-server     # passwordless upload target (match SERVER in config)

# MakeMKV flatpak is sandboxed to ~/Videos by default — let it write the stage dir:
flatpak override --user --filesystem=/mnt/data/rips com.makemkv.MakeMKV
```

## Use

```bash
rip --drives                         # list optical drives / verify the disc is seen
rip "The Matrix (1999)"              # movie: longest title → Movies/The Matrix (1999)/
rip --tv "Andor" --season 1          # tv: all episode-length titles → TV/Andor/Season 01/
rip --tv "Andor" -s 1 -e 4           # tv, numbering starts at episode 4
rip --no-upload "Foo (2020)"         # rip+encode only; inspect before trusting the pipeline
```

Options: `--tv`, `-s/--season N`, `-e/--episode N`, `--drive N`, `--keep`,
`--no-upload`, `--detelecine`, `--drives`, `-h/--help`. Everything else (quality,
thresholds, paths) lives in `~/.config/rip/config`.

## Gotchas

- **TV episode order** follows disc title order — usually broadcast order, not
  always. Do a `--no-upload` run and check a box set before trusting it.
- **DVDs are interlaced.** Adaptive decomb (`--comb-detect --decomb`) is always
  on (harmless on progressive Blu-ray). For film/animation NTSC DVDs (3:2
  telecine), add `--detelecine` to recover clean 23.976p — otherwise motion
  judders. Short-form shows (<20 min/ep) fall under `TV_MIN`; lower it in config.
- **Unmount the disc first.** If the desktop auto-mounts a DVD (e.g. under
  `/run/media/...`), MakeMKV's scan can crawl. `udisksctl unmount -b /dev/sr0`
  (no eject) before ripping.
- **Main-feature pick** is "longest title over `MOVIE_MIN`." A few discs bury the
  feature behind a longer looping/branching title; verify with `--no-upload`.
- This drive (Pioneer BP60NB10) is a standard BD-RE — DVD and 1080p Blu-ray only,
  **no 4K UHD** (those need a UHD-friendly drive with special firmware).
- The `rip` script here is the source of truth; `~/.local/bin/rip` is an installed
  copy. Re-run the `install` line after editing.
