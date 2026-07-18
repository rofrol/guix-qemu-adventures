# guix-qemu-adventures

My adventures running qcow2 image on macos.

## Run

`brew install qemu`

Download qcow2 image from https://guix.gnu.org/en/download/.

You may want to generate ssh key:

`ssh-keygen -t ed25519 -C you@example.com -f ~/.ssh/guix_guest_ed25519`.

Then replace hardcoded pub key in `config.scm` in openssh-configuration from `~/.ssh/guix_guest_ed25519.pub`.

`./qemu.sh`

There is also `./qemu-vnc.sh` if you want to run GUI on official qcow2 image.

`ssh -i ~/.ssh/guix_guest_ed25519 -p 2222 root@localhost`

Or add to `~/.ssh/config`:

```
Host localhost
    HostName localhost
    Port 2222
    User root
    IdentityFile ~/.ssh/guix_guest_ed25519
    IdentitiesOnly yes
```

`ssh -p 2222 root@localhost`

## Log

### Mount local directory into qemu instance

qemu param:

`-virtfs local,path=$PWD,security_model=mapped,id=share,mount_tag=guixshare`

inside guest

```
mkdir -p /mnt/shared
mount -t 9p -o trans=virtio guixshare /mnt/shared
```

### Format guile file

```
guix style --whole-file config.scm
```

I have made guile script that connects to qemu guest and formats it remotely and gets back result back:

https://github.com/rofrol/dotfiles/blob/master/scripts/guix-style.scm

Configuration for ki editor https://github.com/rofrol/dotfiles/blob/master/.config/ki/config.json

- https://guix.gnu.org/manual/1.5.0/en/html_node/Formatting-Code.html
- https://guix.gnu.org/manual/1.5.0/en/html_node/Invoking-guix-style.html

## build

Below can take 18 minues:

```
time guix system image -t qcow2-gpt --save-provenance --image-size=20G /mnt/shared/config.scm
```

I also saw this command to move or cp after success:

```
mv "$(guix system image -t qcow2-gpt --save-provenance --image-size=20G /mnt/shared/config.scm)" /mnt/shared
```

And then conifg is in `/run/current-system/configuration.scm`.

`--image-size` is important because official qcow2 has max 2.6 GB limit. Get this info with `qemu-img info image.qcow2`.

## Enlarge qcow2

Image get full with `guix pull` and `guix gc` did not work so I had to delete something.

```
du -xh / --max-depth=2 2>/dev/null | sort -rh | head -30
rm -rf /root/.cache/guix
```

Still too little space for `git pull` but I thankfully managed to install parted.

```
$ qemu-img info guix-system-vm-image-1.5.0.aarch64-linux.qcow2
image: guix-system-vm-image-1.5.0.aarch64-linux.qcow2
file format: qcow2
virtual size: 2.6 GiB (2792493056 bytes)
disk size: 1.19 GiB
cluster_size: 65536
Format specific information:
    compat: 1.1
    compression type: zstd
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
    extended l2: false
Child node '/file':
    filename: guix-system-vm-image-1.5.0.aarch64-linux.qcow2
    protocol type: file
    file length: 1.18 GiB (1265827840 bytes)
    disk size: 1.19 GiB
$ qemu-img resize guix-system-vm-image-1.5.0.aarch64-linux.qcow2 +15G
$ qemu-img info guix-system-vm-image-1.5.0.aarch64-linux.qcow2
image: guix-system-vm-image-1.5.0.aarch64-linux.qcow2
file format: qcow2
virtual size: 17.6 GiB (18898620416 bytes)
disk size: 1.22 GiB
cluster_size: 65536
Format specific information:
    compat: 1.1
    compression type: zstd
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
    extended l2: false
Child node '/file':
    filename: guix-system-vm-image-1.5.0.aarch64-linux.qcow2
    protocol type: file
    file length: 1.21 GiB (1295384576 bytes)
    disk size: 1.22 GiB
```

guest:

```
# du -xh / --max-depth=2 2>/dev/null | sort -rh | head -30
2.5G    /
1.9G    /gnu/store
1.9G    /gnu
548M    /root/.cache
548M    /root
9.0M    /var
8.3M    /var/guix
3.9M    /run
3.4M    /run/privileged
512K    /run/udev
452K    /var/db
164K    /var/log
88K     /etc
44K     /var/run
36K     /etc/ssh
24K     /root/.config
16K     /lost+found
12K     /usr
12K     /etc/guix
12K     /boot
8.0K    /var/lib
8.0K    /usr/bin
8.0K    /boot/grub
8.0K    /bin
4.0K    /var/tmp
4.0K    /var/lock
4.0K    /var/empty
4.0K    /tmp
4.0K    /run/setuid-programs
4.0K    /mnt
# rm -rf /root/.cache/guix
# guix install parted
# parted /dev/vda print
Warning: Not all of the space available to /dev/vda appears to be used, you can
fix the GPT to use all of the space (an extra 31457280 blocks) or continue with
the current setting?
Fix/Ignore? fix
Model: Virtio Block Device (virtblk)
Disk /dev/vda: 18.9GB
Sector size (logical/physical): 512B/512B
Partition Table: gpt
Disk Flags:

Number  Start   End     Size    File system  Name        Flags
 1      1049kB  43.0MB  41.9MB  fat16        GNU-ESP     boot, esp
 2      43.0MB  2792MB  2749MB  ext4         Guix_image  legacy_boot

# parted /dev/vda resizepart 2 100%
# resize2fs /dev/vda2
# df -H
Filesystem      Size  Used Avail Use% Mounted on
none            4.2G     0  4.2G   0% /dev
/dev/vda2        21G  2.0G   18G  10% /
/dev/vda1        42M   11M   31M  26% /boot/efi
guixshare       495G  452G   44G  92% /mnt/shared
tmpfs           4.2G     0  4.2G   0% /dev/shm
efivarfs        263k  2.1k  261k   1% /sys/firmware/efi/efivars
```

## Clipboard, copy and paste

Works with `-nographic`. Does not work with GUI.

## ssh and Host key verification failed

Fingerprint of guest changed, so I am removing entries from `~/.ssh/known_hosts`:

```
ssh-keygen -R '[localhost]:2222'; ssh-keygen -R '[127.0.0.1]:2222'
```

- https://stackoverflow.com/questions/21383806/how-can-i-force-ssh-to-accept-a-new-host-fingerprint-from-the-command-line/53672867#53672867

## Error during guix pull

I have submitted https://codeberg.org/guix/guix/issues/9996

Workaround is to add `--substitute-urls`.

```guile
(substitute-urls '("https://bordeaux.guix.gnu.org"))
```

## shutdown and reboot

Just run `shutdown` or `reboot`.

## reconfigure

```
time guix system reconfigure /mnt/shared/config.scm
```

Needed `--skip-check` for `9p`:

```
time guix system reconfigure --skip-checks /mnt/shared/config.scm
```

## Boot into older generations

`reboot` and choose in grub menu `GNU system, old configurations..`

## Shrink qcow2

You need to add `discard=unmap,detect-zeroes=unmap` to qemu params:

`-drive file=guix-system-vm-image-1.5.0.aarch64-linux.qcow2,media=disk,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap`

on guest:

```
du -sxh /
du -xh / --max-depth=2 2>/dev/null | sort -rh | head -30
guix system delete-generations
guix package --delete-generations
fstrim -av
rm -rf /root/.cache
40  guix gc
du -sxh /
time guix system image -t qcow2-gpt --save-provenance --image-size=20G /mnt/shared/config.scm
shutdown
```

on host:

`qemu-img convert -O qcow2 -c guix-system-vm-image-1.5.0.aarch64-linux.qcow2 shrinked.qcow2`

## Spice on macos from homebrew

qemu from homebrew does not support Spice. Even when build from source with `brew install --build-from-source qemu`. It does not have spice server, only spice protocol.
