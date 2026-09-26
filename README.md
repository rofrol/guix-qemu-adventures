# guix-qemu-adventures

My adventures running a Guix System aarch64 qcow2 image with QEMU on macOS (Apple Silicon).

## Files

| File | What it is |
| --- | --- |
| `qemu.sh` | run VM headless (`-nographic`), ssh on port 2224 |
| `qemu-desktop.sh` | run VM with GUI (cocoa display), ssh on port 2223 |
| `config.scm` | system config for headless VM (sshd on 2224, 9p share at `/mnt/share`, substitute urls) |
| `config-desktop.scm` | system config for desktop VM (sshd on 2223, SPICE) |
| `reconfigure.sh` | run in guest: build and reconfigure system from `/mnt/share/config.scm`, failing instead of compiling packages without substitutes (see [Reconfigure](#reconfigure)) |
| `shrink-guest.sh` | run in guest: delete generations, gc, fstrim (see [Shrink qcow2](#shrink-qcow2)) |
| `shrink-qcow2.sh` | run on host: recompress qcow2 (see [Shrink qcow2](#shrink-qcow2)) |
| `test-mirrors.sh` | measure connect time to substitute servers |

Both `qemu*.sh` run `guix-system-vm-image-1.5.0.aarch64-linux-modified.qcow2`. For me it is a symlink to image built with `config.scm` (see [Build image](#build-image)). For a start you can point it to official image.

## Quick start

```sh
brew install qemu
```

Download qcow2 image from https://guix.gnu.org/en/download/.

Generate ssh key:

```sh
ssh-keygen -t ed25519 -C you@example.com -f ~/.ssh/guix_guest_ed25519
```

Then replace hardcoded public key in `openssh-configuration` in `config.scm` (and `config-desktop.scm`) with content of `~/.ssh/guix_guest_ed25519.pub`.

```sh
./qemu.sh
ssh -i ~/.ssh/guix_guest_ed25519 -p 2224 root@localhost
```

Or add to `~/.ssh/config` (not `Host localhost`, as it would apply to every ssh to localhost):

```
Host guix-vm
    HostName localhost
    Port 2224
    User root
    IdentityFile ~/.ssh/guix_guest_ed25519
    IdentitiesOnly yes
```

and then `ssh guix-vm`.

Clipboard (copy and paste) works with `-nographic` (`qemu.sh`). Does not work with GUI (`qemu-desktop.sh`).

Shutdown and reboot: just run `shutdown` or `reboot` in guest.

## Mount local directory into guest

`qemu*.sh` share current directory with:

```
-virtfs local,path=$PWD,security_model=mapped,id=share,mount_tag=share
```

`config.scm` already mounts it at `/mnt/share`. On official image mount it manually in guest:

```sh
mkdir -p /mnt/share
mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/share
```

## Guest system

### Reconfigure

```sh
time guix system reconfigure --skip-checks /mnt/share/config.scm
```

`--skip-checks` is needed for `9p` file system. Or run `/mnt/share/reconfigure.sh`, which fails instead of compiling packages without substitutes.

`guix weather` can say all substitutes are there and reconfigure still compiles LLVM: it checks package outputs, not inputs of the system's local derivations (e.g. `grub-theme` image is converted from SVG with `guile-rsvg`, which needs librsvg, so Rust, so LLVM). `reconfigure.sh` passes `--max-jobs=0 --no-offload`: the daemon then builds only derivations marked `preferLocalBuild` (config files, profile hooks, grafts, GRUB image) and fails with `unable to start any build` on anything else. This covers grafts too. To see what would be compiled: `guix system build -n --no-grafts --skip-checks /mnt/share/config.scm` (with grafts the dry run lists only downloads).

Current config is then in `/run/current-system/configuration.scm`.

### Boot into older generations

`reboot` and choose in grub menu `GNU system, old configurations...`.

### Build image

Below can take 18 minutes:

```sh
cp "$(time guix system image -t qcow2-gpt --save-provenance --image-size=20G /mnt/share/config.scm)" /mnt/share
```

You cannot `mv`, there would be error like `rm: cannot remove '/gnu/store/p4jlybc6fwmfl70izb1a4wf994rammrp-image.qcow2': Read-only file system`.

`--image-size` is important because official qcow2 has max 2.6 GB. Check it with `qemu-img info image.qcow2`.

### Format guile file

```sh
guix style --whole-file config.scm
```

I have made guile script that connects to qemu guest, formats file remotely and gets result back:

https://github.com/rofrol/dotfiles/blob/master/scripts/guix-style.scm

Configuration for ki editor https://github.com/rofrol/dotfiles/blob/master/.config/ki/config.json

- https://guix.gnu.org/manual/1.5.0/en/html_node/Formatting-Code.html
- https://guix.gnu.org/manual/1.5.0/en/html_node/Invoking-guix-style.html

### Find in what module package is

```sh
guix show ncurses | grep location
guix package -A ncurses
```

## Disk

### Enlarge qcow2

Official image got full after `guix pull`, and `guix gc` did not help, so I had to delete something:

```sh
du -xh / --max-depth=2 2>/dev/null | sort -rh | head -30
rm -rf /root/.cache/guix
```

`/gnu/store` was 1.9G and `/root/.cache` 548M out of 2.5G. Still too little space for `guix pull`, but thankfully I managed to install parted.

On host (with VM stopped):

```sh
qemu-img resize guix-system-vm-image-1.5.0.aarch64-linux.qcow2 +15G
```

Virtual size went from 2.6 GiB to 17.6 GiB, file on disk stays ~1.2 GiB.

In guest:

```
# guix install parted
# parted /dev/vda print
Warning: Not all of the space available to /dev/vda appears to be used, you can
fix the GPT to use all of the space (an extra 31457280 blocks) or continue with
the current setting?
Fix/Ignore? fix
...
Number  Start   End     Size    File system  Name        Flags
 1      1049kB  43.0MB  41.9MB  fat16        GNU-ESP     boot, esp
 2      43.0MB  2792MB  2749MB  ext4         Guix_image  legacy_boot

# parted /dev/vda resizepart 2 100%
# resize2fs /dev/vda2
# df -H
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda2        21G  2.0G   18G  10% /
```

### Shrink qcow2

`qemu*.sh` already have `discard=unmap,detect-zeroes=unmap` in `-drive`. Without it `fstrim` in guest does not free space in qcow2 file:

```
-drive file=guix-system-vm-image-1.5.0.aarch64-linux-modified.qcow2,media=disk,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap
```

1. Start VM with `./qemu.sh`, share should be mounted at `/mnt/share` (see [Mount local directory into guest](#mount-local-directory-into-guest)).
2. In guest run `/mnt/share/shrink-guest.sh` (or from host `ssh -p 2224 root@localhost /mnt/share/shrink-guest.sh`). It does:
   - `guix system delete-generations`, `guix package --delete-generations`, `guix pull --delete-generations`
   - `rm -rf /root/.cache`
   - `guix gc`
   - `sync` and `fstrim -av`, so freed blocks are discarded in qcow2
3. `shutdown` in guest.
4. On host run `./shrink-qcow2.sh`. It writes `<image>-shrinked.qcow2` next to image, original is kept. Or run `./shrink-qcow2.sh --in-place` to replace image (symlink `*-modified.qcow2` still works). Other image: `./shrink-qcow2.sh [--in-place] path/to/image.qcow2`. It does:
   - refuses if image has internal snapshots (convert would drop them)
   - `qemu-img convert -O qcow2 -c -o compression_type=zstd` (default would be zlib)
   - `qemu-img check` on the result
   - keeps permissions of original (600)

Deleting generations is irreversible, there will be no older systems in grub `GNU system, old configurations...`.

Result for me: guest `/` from 28G to 2.4G (`guix gc: freed 46 GiB`), image file from 31G to 915M.

After `fstrim` and `shutdown` image already takes less space on host (qcow2 file becomes sparse, `du -h image.qcow2`), convert compresses it and removes holes. Compression applies only to data written by convert, new writes from VM are not compressed, so image grows again. Then repeat.

## Substitutes

### Error during guix pull

I have submitted https://codeberg.org/guix/guix/issues/9996

Workaround is to set `substitute-urls` (in `config.scm` in `guix-configuration`, or `--substitute-urls` on command line):

```scheme
(substitute-urls '("https://bordeaux.guix.gnu.org"))
```

### Check mirrors

`./test-mirrors.sh` measures connect time. `guix weather` shows how many substitutes are available:

```sh
guix weather --substitute-urls="https://bordeaux.guix.gnu.org"
```

Results for aarch64-linux (import `WARNING`s omitted):

| Server | Substitutes available | Nars (compressed) |
| --- | --- | --- |
| https://bordeaux.guix.gnu.org | 95.2% (36,636 of 38,501) | 94,046.3 MiB |
| https://hydra-guix-129.guix.gnu.org | 95.2% (36,639 of 38,504) | 88,054.0 MiB |

bordeaux also returned `'https://bordeaux.guix.gnu.org/api/queue?nr=1000' returned 502 ("Bad Gateway")`, hydra-guix-129 `(continuous integration information unavailable)`.

- https://libreplanet.org/wiki/Group:Guix/Mirrors

## ssh: Host key verification failed

Fingerprint of guest changed (e.g. after booting new image), so I am removing entries from `~/.ssh/known_hosts`:

```sh
ssh-keygen -R '[localhost]:2224'; ssh-keygen -R '[127.0.0.1]:2224'
```

- https://stackoverflow.com/questions/21383806/how-can-i-force-ssh-to-accept-a-new-host-fingerprint-from-the-command-line/53672867#53672867

## ghostty

To make it work better with ghostty, install `ncurses` package in guest, which gives `tic` program.

Then on host:

```sh
infocmp -x xterm-ghostty | ssh -p 2224 root@localhost -- tic -x -
```

> the terminfo authors have deliberately chosen to ship their own version of the terminfo definition under a different name (ghostty instead of xterm-ghostty), with their own modifications that make it substantially different from our own terminfo definition, so it wouldn't even work out-of-the-box like what we had expected. https://github.com/ghostty-org/ghostty/discussions/8268#discussioncomment-16744849

- https://ghostty.org/docs/help/terminfo

## nginx

Add `(listen '("90"))`, otherwise nginx will also listen on 443, and if you have no certbot set, starting will fail. Look at generated configuration in `/etc/nginx/nginx.conf` whether it listens on 443.

- check configuration: `nginx -t -c /etc/nginx/nginx.conf`
- check if nginx successfully started: `herd status nginx`
- after changing nginx configuration: `herd reload nginx`
- test serving http site: `curl localhost`

Logs:

```sh
cat /var/log/nginx/access.log
cat /var/log/nginx/error.log
```

- https://guix.gnu.org/manual/1.5.0/en/html_node/Web-Services.html

## SPICE on macOS: use UTM

tldr; Use UTM, as it supports SPICE on macOS out-of-the-box. Plain qemu from homebrew does not. SPICE is better than VNC. With UTM you also get directory sharing with VirtFS and clipboard sharing. But you must change from default SPICE WebDAV to VirtFS for directory sharing in VM settings. To change what directory is shared you have to restart VM. Port forwarding works in Emulated mode.

Look at `your vm > Edit > QEMU > Arguments` to see what arguments UTM passes to qemu.

### Directory sharing

`your vm > Edit > Sharing > Directory Share Mode > VirtFS`

then in guest:

```sh
mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600 share /mnt/share
```

- UTM supports SPICE https://github.com/utmapp/UTM/blob/main/patches/spice-0.14.3.patch
- https://docs.getutm.app/guest-support/linux/#macos-virtiofs
- https://docs.getutm.app/settings-qemu/sharing/
- https://docs.getutm.app/guest-support/sharing/directory/
- When using the QEMU backend, VirtFS is used instead, which does not use such a parent folder and requires restarting the VM to change shares iirc. https://news.ycombinator.com/item?id=36845869
- Bind mounts and file sharing: It uses VirtioFS which isn't affected by sshfs consistency issues, plus caching and optimizations to give it an edge. https://news.ycombinator.com/item?id=36675039

### Port forwarding

Set Network Mode to Emulated VLAN (Shared Network) (sometimes labelled as "NAT"). Then a Port Forward option appears below Network.

- https://dev.to/smyekh/completing-your-local-oci-lab-a-guide-to-port-forwarding-in-utm-hgp
- https://docs.getutm.app/settings-qemu/devices/network/port-forwarding/

### Alternatives to UTM with SPICE

- qemu from homebrew does not support SPICE, even when built from source with `brew install --build-from-source qemu`. It has only spice protocol, not spice server. QEMU needs the spice-protocol and spice-server library to compile with SPICE support. While the spice-protocol package is available for macOS, I can't seem to find a precompiled package of spice-server https://stackoverflow.com/questions/59636198/how-to-compile-qemu-with-spice-support-for-macos. There is possibility to have qemu with SPICE without UTM, but I have not tested it: https://github.com/avoidik/homebrew-qemu-spice
  - You need to add a dependency on spice-server to qemu too https://github.com/orgs/Homebrew/discussions/5266#discussioncomment-9033465
- https://github.com/jeffreywildman/homebrew-virt-manager
  - https://stackoverflow.com/questions/3921814/is-there-a-virt-manager-alternative-for-mac-os-x
  - ran brew reinstall gobject-introspection which fixed the issue with the unsupported graphics type https://github.com/jeffreywildman/homebrew-virt-manager/issues/200#issuecomment-1492043260
  - https://www.romanstefko.com/2025/11/connect-to-proxmox-spice-console-virt-viewer-on-macos/
  - Proxmox https://gist.github.com/tomdaley92/789688fc68e77477d468f7b9e59af51c
- virt-manager and virsh https://johnsiu.com/blog/macos-kvm-remote-connect/
- Connect to virtual machines using SPICE https://formulae.brew.sh/cask/remoteviewer
- A homebrew tap for qemu with support for 3d accelerated guests https://github.com/startergo/homebrew-qemu-virgl
