Megamiga shared folder (MegamigaFS)
===================================

The folder /amiga of the MEGA65's SD card as an Amiga volume, "SDCard:" (the
device is "SD:"). Read-only for now: copy files from it, not to it.

Install (Kickstart 2.0 and later)
---------------------------------
  Copy L/MegamigaFS              to  L:
  Copy Devs/dummy.device         to  DEVS:
  Copy Devs/DOSDrivers/SD        to  DEVS:DOSDrivers/

The volume is there after the next boot. To use it right away, without a
reboot:  Mount SD:

Kickstart 1.3
-------------
Copy L/MegamigaFS to L: and Devs/dummy.device to DEVS:, add the entry from
Devs/MountList to DEVS:MountList and run "Mount SD:" (add it to
S:Startup-Sequence to have it at every boot).

Using it
--------
- SDCard: shows the folder /amiga of the SD card that is active in the MEGA65
  (the card in the bottom tray or the one in the back slot). Hidden files and
  files outside /amiga are not visible.
- It behaves like a disk in a drive: when you pull the SD card, the volume goes
  away; when you insert a card, it comes back after a second (Workbench shows
  the icon again). Switching the SD card in the core's file browser (F1/F3)
  changes the volume, too.
- Long file names work; names longer than 106 characters are cut there.
- Do not run programs that write to the card's files while the core uses the
  same file as a disk (HDF, ADF): the volume is read-only, so the shared folder
  itself cannot do that.

The protocol is MiSTer's shared folder protocol, so MiSTer's own
MiSTerFileSystem works too (as SHARE:, volume MiSTer:), but without the
removable volume.

Credits: MiSTerFileSystem by Alexey Melnikov, based on a314fs by Niklas
Ekstrom. Megamiga changes licensed under GPL v3.
