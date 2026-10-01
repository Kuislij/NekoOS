# Archiso templates used by NekoOS

The BIOS/UEFI boot templates come from the baseline profile of Archiso
90-1, and the mkinitcpio profile/preset from its releng profile.
The signed package is installed from the Arch Linux Archive snapshot
2026/09/29. The upstream project and corresponding template sources are:

- https://gitlab.archlinux.org/archlinux/archiso
- https://github.com/archlinux/archiso/tree/v90/configs
- https://github.com/archlinux/archiso/blob/v90/LICENSE

Archiso is licensed under GPL-3.0-or-later. The ISO includes its authors
list and the GPL text in /usr/share/licenses/nekoos-archiso-templates/.
Other packages retain their own metadata and /usr/share/licenses/ files.

NekoOS modifications, 2026-10-01: branding, a two-second boot timeout,
the serial QA console, a RAM overlay limited to 50% of available memory,
zstd initramfs compression and the separate Xfce Live profile. The changes
are applied by scripts/arch-iso-build-root.sh in the NekoOS repository:
https://github.com/Kuislij/NekoOS

These templates do not imply Arch Linux endorsement of NekoOS.
