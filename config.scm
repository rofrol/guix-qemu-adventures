;; -*- mode: scheme -*-

(use-modules (gnu)
             (gnu services networking)
             (gnu services ssh)
             ;; for current-guix
             (gnu packages package-management)
             ;; for refence openssh-sans-x, not package openssh-sans-x
             ;; used in (openssh openssh-sans-x)
             (gnu packages ssh)
             ;; for package-version
             (guix packages))

(operating-system
  (host-name "Guix")
  (locale "en_US.utf8")
  (timezone "Europe/Warsaw")
  (keyboard-layout (keyboard-layout "pl"))

  ;; Label for the GRUB boot menu.
  (label (string-append "GNU Guix "
                        (or (getenv "GUIX_DISPLAYED_VERSION")
                            (package-version guix))))

  ;; On AArch64, support SCSI CDROMs and HDs.
  (initrd-modules (cons* "sd_mod" "sr_mod" %base-initrd-modules))

  (bootloader (bootloader-configuration
                (bootloader grub-efi-bootloader)
                (targets '("/boot/efi"))
                (terminal-outputs '(console))))

  (file-systems (cons* (file-system
                         (mount-point "/")
                         (device (file-system-label "Guix_image"))
                         (type "ext4"))
                       (file-system
                         (mount-point "/boot/efi")
                         (device (file-system-label "GNU-ESP"))
                         (type "vfat"))

                       ;; need to add --skip-check to reconfigure
                       (file-system
                         (mount-point "/mnt/share")
                         (device "guixshare")
                         (type "9p")
                         (options "trans=virtio,version=9p2000.L")
                         ;; will not boot without it
                         (needed-for-boot? #f)
                         (create-mount-point? #t))

                       %base-file-systems))

  ;; Packages installed system-wide.  Users can also install packages
  ;; under their own account: use 'guix search KEYWORD' to search
  ;; for packages and 'guix install PACKAGE' to install a package.
  ;; ncurses needed for tic
  ;; infocmp -x xterm-ghostty | ssh -p 2222 localhost -- tic -x -
  ;; (packages (append (map specification->package (list "neovim" "ncurses")) %base-packages))
  (packages (append (specifications->packages (list "neovim" "ncurses"))
                    %base-packages))
  (services
   (cons* (service dhcpcd-service-type)
          (service openssh-service-type
                   (openssh-configuration (openssh openssh-sans-x)
                                          (port-number 2222)
                                          (password-authentication? #f)
                                          (permit-root-login 'prohibit-password)
                                          ;; /etc/ssh/authorized_keys.d/root
                                          (authorized-keys `(("root" ,(plain-file
                                                                       "authorized_keys"
                                                                       "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkwW6AJsh/haG7pcBZx/aNfSdDPOxaN6JFV3flOEJh3 rofrol@gmail.com"))))))

          ;; Install and run the current Guix rather than an older
          ;; snapshot.
          (modify-services %base-services
            (guix-service-type config =>
                               (guix-configuration (inherit config)
                                                   (guix (current-guix))
                                                   ;; default failed for subsitions on QEMU/aarch64 when guix pull:
                                                   ;; guix/serialization.scm:104:6: In procedure get-bytevector-n*:
                                                   ;; ERROR: 1. &nar-error:file: #f port: #<input-output: file 10>
                                                   ;; https://codeberg.org/guix/guix/issues/9996
                                                   (substitute-urls '("https://bordeaux.guix.gnu.org https://hydra-guix-129.guix.gnu.org")))))))

  (name-service-switch %mdns-host-lookup-nss))
