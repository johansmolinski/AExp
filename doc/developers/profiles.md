# Profiles as files - design (draft for review, 2026-10-19)

Machine profiles stop being menu items and become files: one file per profile
in `/amiga/profiles`, named by the user. Profile Settings shows ONE set of
options, and they always belong to the active profile.

## Decisions (from the user)

- One file per profile. The file name is the profile name: `A1200.prof` is
  the profile "A1200". Adding a profile = copying a file, naming it = renaming
  it (on a PC, or from the Amiga through `SDCard:`).
- The default profiles (A500, A600, A1200, A4000) are created only when
  `/amiga/profiles` does not exist or holds no profile. Otherwise the user
  deliberately changed the defaults and nothing is created.

## Menu

Main menu: the four profile radio lines become one line that shows the active
profile and opens the file browser in `/amiga/profiles`, and "Save as New
Profile" below it:

```
 Megamiga
 -----------------------
 df0:game.adf
 Mount SDCard
 -----------------------
 Profile: A1200
 Save as New Profile
 -----------------------
 Profile Settings
 Drive Settings
 Settings
 ...
```

Profile Settings: the HDF/Kickstart/AR3 ROM lines as now, then ONE block of
the rows and switches that today exist four times:

```
 Profile Settings
 -----------------------
 HDF 0:work.hdf
 HDF 1:<Load>
 Kickstart:kick31.rom
 AR3 ROM:<Load>
 -----------------------
 CPU
  68000  68020 *68040
 Chipset
  OCS  ECS *AGA
 Hard Disk Controller
  None *Gayle  RIPPLE
 Chip RAM
  512 kB  1 MB *2 MB
 Slow RAM
 *None  512 kB
 Monitor Cartridge
 *None  HRTmon  AR3
 -----------------------
 Zorro Boards
 -----------------------
*Zorro II RAM 8 MB
*Zorro III RAM 16 MB
 Zorro III RAM 32 MB
*Graphics Card
 Network Card
 -----------------------
 Back to main menu
```

The menu shrinks from 252 to about 182 items (3 profile blocks and 3 radio
lines go, "Save as New Profile" comes). Profile Settings stays as it is now
(29 of 29 rows); the main menu has room.

## Profile file

`/amiga/profiles/<name>.prof`, text, one `key=value` per line (LF or CR LF),
keys and values case-insensitive, unknown keys and lines without `=` ignored
(kept? no: a rewrite writes the known keys only), at most 512 characters.

```
cpu=68040            68000 | 68020 | 68040
chipset=AGA          OCS | ECS | AGA
hdc=gayle            none | gayle | ripple
chip=2M              512K | 1M | 2M
slow=none            none | 512K
cart=none            none | hrtmon | ar3
z2ram=on             on | off       Zorro II RAM 8 MB
z3ram16=on           on | off       Zorro III RAM 16 MB
z3ram32=off          on | off       Zorro III RAM 32 MB
gfx=on               on | off       Graphics Card
net=off              on | off       Network Card
kick=SD1:/amiga/kick31.rom
hdf0=SD1:/amiga/disks/work.hdf
hdf1=
```

A missing or invalid value takes the default of the A500 profile (68000, OCS,
RIPPLE, 512 kB Chip, 512 kB Slow, no cartridge, Zorro II RAM on, the rest
off). Names instead of bit positions: a later menu change does not touch the
profiles (only the general settings file is reset, by its signature).

The AR3 ROM stays a session load as today (not remembered per profile).

## Behaviour

- **Boot.** The settings file (text) names the active profile:
  `profile=A1200`. HELP_MENU_INIT/PREP_START: create the defaults if needed
  (below), then load the named profile; if it is gone, the first profile of the
  directory; if there is none (no card, read-only card), the A500 defaults in
  memory (nothing is written). Loading = set the bits of the one block in
  M2M$CFM_DATA / OPTM_IR_STDSEL, then PROFILE_APPLY (Kickstart, HDFs) as today.
- **Default profiles.** On the card of the settings file: `/amiga/profiles`
  missing -> created (FAT32$W_MKDIR) with A500, A600, A1200 and A4000 (today's
  defaults). Present but without any `.prof` file -> the four files. Otherwise
  nothing. ("Empty" = no `.prof` file; other files in the directory do not
  count. To confirm.)
- **Switch.** "Profile: ..." opens the browser in `/amiga/profiles`, showing
  `.prof` files only. A selection loads the file (the line shows its name),
  stores `profile=<name>` in the settings file and cold-boots the Amiga, as the
  radio does today.
- **Changes.** A change in Profile Settings (a row, a switch, a Kickstart or HDF
  chosen or forgotten) marks the profile dirty; it is written back to its file
  when the menu closes, together with the settings file (ROSM_SAVE). The file is
  rewritten whole (FAT32 write layer: W_SETSIZE + write).
- **Save as New Profile.** Writes the current settings to `User 1.prof` (the
  first free `User N`), makes it the active profile and shows its name. Renaming
  is done outside the core.
- **Greying, deselecting, cold boot on topology changes**: as now, on the one
  block.

## Implementation

- `config.vhd`: one block (C_MENU_PROF_BASE, stride gone), the profile line (a
  manual ROM load: browser + PREP_LOAD_IMAGE get the file), "Save as New
  Profile", OPTM_DEP/OPTM_AVAIL for one block, all C_MENU_* behind it renumbered
  (xcheck.py).
- `mega65.vhd`: prof_decode reads the one block (no v_base); the profile index
  is gone from the HDL.
- Firmware (code bank 2, ~1900 words free; the fixed ROM has 60): create the
  defaults, read/parse a profile into the block bits and paths, write a profile,
  "Save as New", the active name in the settings text; PROFILE_APPLY takes the
  paths from the active profile instead of the `a1200.kick`-style keys
  (B2_PROF_* go). Browser start directory and the `.prof` filter: core callbacks
  (FILTER_FILES and the browser's start path - to check).
- Migration: none. The new core resets the old settings file (signature) once;
  the Kickstart/HDF choices of the old profiles are lost once.

## Tests

- Emulator + FAT32 images (like `~/aexp-work/cfgcreate`): defaults created for
  no directory / an empty one / one without `.prof` files, not for one with a
  profile; parse (all keys, missing, invalid, unknown, CR LF, case), write and
  read back, the active profile missing -> the first one, Save as New naming
  (User 1, User 2 with User 1 present), write-back on menu close; mutants.
- config/ghdl: the one block, prof_decode, xcheck of the renumbered constants;
  render of the main menu and Profile Settings (height).
- Hardware: first start (defaults created, profile chosen), switching, editing
  and power cycling, a copied and renamed profile, a hand-edited file.

## Open points

1. "Empty directory" = no `.prof` file (other files ignored)?
2. Should a profile also remember the AR3 ROM?
