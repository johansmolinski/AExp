Megamiga shared folder (MegamigaFS)
===================================

The folder /amiga of the MEGA65's SD card as an Amiga volume, "SDCard:" (the
device is "SD:"). It can be read and written: copy files to it and from it,
create, rename and delete files and drawers.

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
- To eject the volume without touching the card, switch off "SDCard:
  inserted" in the core's main menu (below the floppy drives); switch it on
  again to insert it.
- Long file names work; names longer than 106 characters are cut there.
- Files the core uses itself (a mounted ADF or HDF, the settings file) cannot
  be written, deleted or renamed through SDCard: ("object in use").
- FAT keeps less than an Amiga disk: of the protection bits only "read-only"
  (set when a file must not be written or deleted), no comments, dates to two
  seconds. Names may not contain " * / : < > ? \ | (FAT does not allow them).
- Pull the card only when nothing is being written (like a floppy while its
  light is on).

- C/ShareInfo prints the state of the shared folder: whether the volume is
  there and how often the card was removed, inserted or switched since the
  core started. Useful if the volume came and went without you touching the
  card.

The protocol is MiSTer's shared folder protocol, so MiSTer's own
MiSTerFileSystem works too (as SHARE:, volume MiSTer:), but without the
removable volume.

Credits: MiSTerFileSystem by Alexey Melnikov, based on a314fs by Niklas
Ekstrom. Megamiga changes licensed under GPL v3.
