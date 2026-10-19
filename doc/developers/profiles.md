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
- Profiles can be named in the menu by typing on the MEGA65 keyboard (option B
  of 2026-10-19: real typing, not a character picker), with only characters
  FAT32 allows in long file names.

## Menu

Main menu: the four profile radio lines become one line that shows the active
profile and opens the profile selector, and "Rename Profile" below it:

```
 Megamiga
 -----------------------
 df0:game.adf
 Mount SDCard
 -----------------------
 Profile: A1200
 Rename Profile
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

The profile selector (user, 2026-10-19): the profiles, then a separator bar
and "Add New Profile" at the bottom:

```
 A1200
 A4000
 A500
 A600
 Work 040
 -----------------------
 Add New Profile
```

The menu shrinks from 252 to about 182 items (3 profile blocks and 3 radio
lines go, "Rename Profile" comes). Profile Settings stays as it is now
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
- **Add New Profile** (the last entry of the profile selector). Asks for a
  name (the editor below; Return on an empty name takes the first free
  `User N`), writes the settings of the active profile to `<name>.prof` (a
  copy to start from), makes it the active profile and shows its name. This
  replaces the "Save as New Profile" menu line of the first draft.
- **The profile selector** is the firmware's own list, not the file browser:
  the browser keeps one shared position (the next ADF browse would start in
  `/amiga/profiles`), starts in the configured directory and lists extra
  entries only at the top. The selector lists the `.prof` files of
  `/amiga/profiles` (sorted, without the extension), a separator bar and "Add
  New Profile"; Up/Down, Return, Run/Stop. The menu line " Profile: <name>" is
  a momentary item (like "Freeze cartridge") whose name the firmware paints
  in place (OPTM_LIVE_TEXT, as the Hardware Floppy status).
- **Rename Profile.** Asks for a new name (prefilled with the old one) and
  renames the file of the active profile (FAT32$W_RENAME); `profile=` in the
  settings file follows. Renaming outside the core (PC, `SDCard:`) still works.

## Name editor

A one-line editor in the menu window: `Name: Work 040_` with a cursor.

- Typing: the MEGA65 keyboard with Shift (upper case and the shifted symbols).
  Accepted: `A-Z a-z 0-9`, space and `! # $ % & ' ( ) + , - . ; = @ [ ] ^ _ `
  `` ` `` `{ } ~`. Not accepted (nothing happens): `" * / : < > ? \ |` and
  control characters - the characters FAT32 forbids in long names.
- Used by Add New Profile and Rename Profile.
- Keys: Left/Right move the cursor, Delete (backspace) deletes in front of it,
  Return accepts, Run/Stop cancels. At most 24 characters (the menu shows
  "Profile: " + the first 12).
- On Return: leading and trailing spaces and trailing dots are removed (Windows
  refuses them too). Empty -> the default (see above). A name that already
  exists -> "A profile with this name exists" and the editor stays open.
- Hardware: while the menu is open the framework hides the keyboard from the
  core and gives the firmware only its 10 menu keys. New: `m2m_keyb.vhd` also
  exports the UNGATED key status (`key_raw_n_o`, the osm-hotkey pattern of M2M
  exception 4), threaded through `framework.vhd` and the four board tops into the
  core; the core turns key-down events into a QNICE-readable register
  (`{sequence, shift, key number}`, cdc_stable into the QNICE domain), and the
  firmware maps MEGA65 key numbers to characters (a table with and without
  Shift). Needs a full build.
- **Greying, deselecting, cold boot on topology changes**: as now, on the one
  block.

## Implementation

- `config.vhd`: one block (C_MENU_PROF_BASE, stride gone), the profile line
  and "Rename Profile" (momentary items), OPTM_AVAIL for one block, all C_MENU_*
  behind it renumbered (xcheck.py).
- `mega65.vhd`: prof_decode reads the one block (no v_base); the profile index
  is gone from the HDL.
- Keyboard: m2m_keyb.vhd `key_raw_n_o` -> framework -> board tops R3..R6 ->
  mega65.vhd (key-down event register, a QNICE device register).
- Firmware (code bank 2, ~1900 words free, else bank 3; the fixed ROM has 60): create the
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
  (User 1, User 2 with User 1 present), write-back on menu close; the name
  editor (allowed/refused characters, Shift, cursor, delete, trimming, empty,
  an existing name, rename); mutants. ghdl: the key-down event register.
- config/ghdl: the one block, prof_decode, xcheck of the renumbered constants;
  render of the main menu and Profile Settings (height).
- Hardware: first start (defaults created, profile chosen), switching, editing
  and power cycling, a copied and renamed profile, a hand-edited file.

## Open points (proposed answers used unless the user says otherwise)

1. "Empty directory" = no `.prof` file (other files ignored). Proposed: yes.
2. Should a profile also remember the AR3 ROM? Proposed: no (as today).
