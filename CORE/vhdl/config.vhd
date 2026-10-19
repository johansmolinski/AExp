----------------------------------------------------------------------------------
-- Amiga 500 for MEGA65 (AExp)
--
-- Configuration data for the Shell
--
-- Based on the MiSTer2MEGA65 framework template, done by sy2002 and MJoergen
-- in 2023 and licensed under GPL v3.
-- Amiga 500 port (AExp) done by sy2002 in 2026.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity config is
port (
   clk_i       : in std_logic;

   -- bits 27 .. 12:    select configuration data block; called "Selector" hereafter
   -- bits 11 downto 0: address the up to 4k the configuration data
   address_i   : in std_logic_vector(27 downto 0);

   -- config data
   data_o      : out std_logic_vector(15 downto 0)
);
end entity config;

architecture beh of config is

--------------------------------------------------------------------------------------------------------------------
-- String and character constants (specific for the Anikki-16x16 font)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant CHR_LINE_1  : character := character'val(196);
constant CHR_LINE_5  : string := CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1;
constant CHR_LINE_10 : string := CHR_LINE_5 & CHR_LINE_5;
constant CHR_LINE_50 : string := CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10;

--------------------------------------------------------------------------------------------------------------------
-- Welcome and Help Screens (Selectors 0x1000 .. 0x1FFF)
--------------------------------------------------------------------------------------------------------------------

-- define the amount of WHS array elements: between 1 and 16
constant WHS_RECORDS   : natural := 2;

-- define the maximum amount of pages per WHS array element: between 1 and 256
-- (this is necessary because Vivado does not support unconstrained arrays in a record)
constant WHS_MAX_PAGES : natural := 7;

 -- !!! DO NOT TOUCH !!!
constant SEL_WHS           : std_logic_vector(15 downto 0) := x"1000";
type WHS_INDEX_TYPE is array (0 to WHS_MAX_PAGES - 1) of natural;
type WHS_RECORD_TYPE is record
   page_count  : natural;
   page_start  : WHS_INDEX_TYPE;
   page_length : WHS_INDEX_TYPE;
end record;
type WHS_RECORD_ARRAY_TYPE is array (0 to WHS_RECORDS - 1) of WHS_RECORD_TYPE;

-- START YOUR CONFIGURATION BELOW THIS LINE

-- The core's version string. Single source of truth (same convention as
-- C64MEGA65, its GitHub issue #182): this constant is used by SCR_WELCOME,
-- HELP_1 through HELP_7 (the welcome and help screens just below), by CORENAME
-- (the serial-terminal banner further down) and by CFG_FILE (the on-SD-card
-- config filename further down). Update this one line when releasing a new
-- version; make_release.py parses it and uses it as the official version
-- string for that release.
constant CORE_VERSION : string := "0.6.4";

constant SCR_WELCOME : string :=

   "Megamiga " & CORE_VERSION & " - A500/A600/A1200/A4000\n" &
   "Based on AExp by sy2002 (Minimig port)\n\n" &

   "Powered by MiSTer2MEGA65 Version 2.0.1,\n" &
   "done by sy2002 and MJoergen\n\n\n" &

   "This core needs a Kickstart ROM on your\n" &
   "SD card (FAT32):\n\n" &
   "    /amiga/kick.rom\n\n" &
   "Raw dump, no byte swapping: 1.3 (256 KB)\n" &
   "or 2.04/3.x for the A500/A600 (512 KB).\n\n\n" &

   "    Key                Amiga 500\n" &
   "    " & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_1 & CHR_LINE_1 & "\n" &
   "    MEGA               Amiga (left)\n" &
   "    Help               Help / Options menu\n\n\n" &

   "\n\n    Press Space to continue.\n\n\n";

constant HELP_1 : string :=

   "\n Megamiga " & CORE_VERSION & " - A500/A600/A1200/A4000\n" &
   " Based on AExp by sy2002 (Minimig port)\n\n" &

   " github.com/johansmolinski/Megamiga\n\n" &

   " MACHINE PROFILES (main menu)\n\n" &

   " A500:  68000, OCS, 512 KB + 512 KB Slow\n" &
   " A600:  68000, ECS, 2 MB Chip\n" &
   " A1200: 68020, AGA, 2 MB Chip\n" &
   " A4000: 68040, AGA, 2 MB Chip, Zorro III\n" &
   " CPU (68000-68040), chipset, RAM (8 MB\n" &
   " Zorro II, 16 and 32 MB Zorro III) are\n" &
   " set in Profile Settings. A profile\n" &
   " keeps the Kickstart (else kick.rom)\n" &
   " and hard disks you load for it.\n\n" &

   " Mouse: Port 1   Joystick: Port 2\n\n" &

   " Up to three floppy drives, but only\n" &
   " df0: is on by default - some games\n" &
   " need that. 880 KB ADF disk images,\n" &
   " and real Amiga disks in the MEGA65\n" &
   " drive, all read and write. Hard disks:\n" &
   " two HDF images (Gayle IDE, or lide.rom)\n" &
   " Space on a mounted HDF line ejects it.\n" &
   " The HDF browser also offers the SD\n" &
   " card partitions of MBR type 0x7F.\n\n" &

   " Not implemented, yet: NTSC, flicker-free\n\n" &

   " Crsr right: Next                (1/7)\n" &
   " Space or Run/Stop: Close";

constant HELP_2 : string :=

   "\n KEYBOARD\n\n" &

   " MEGA65 mode (default):\n\n" &
   " Type what is printed on the keycaps.\n" &
   " MEGA + key types front-face symbols.\n" &
   " Esc, Tab and Caps Lock work normally.\n\n" &

   " MEGA              Left Amiga\n" &
   " RESTORE           Right Amiga\n" &
   " Run/Stop (hold)   Right mouse button\n" &
   " F1,F3,F5,F7,F9    Odd Amiga F-keys\n" &
   " Shift + F-key     Even Amiga F-keys\n\n" &

   " Amiga mode:\n\n" &
   " Keys use original Amiga positions.\n" &
   " Some games need this mode.\n" &
   " The top row from Run/Stop through F11\n" &
   " becomes Esc and F1-F10.\n" &
   " F13 becomes Left Alt.\n" &
   " Hold the up-arrow symbol left of\n" &
   " RESTORE for the right mouse button.\n\n" &

   " Both modes:\n" &
   " Ctrl+MEGA+RESTORE = warm reset\n\n" &
   "\n\n\n" &  -- keep footer at bottom

   " Crsr left/right: Prev/Next      (2/7)\n" &
   " Space or Run/Stop: Close";

constant HELP_3 : string :=

   "\n ADF FLOPPY\n\n" &

   " Select a df0:/df1:/df2: line in the\n" &
   " menu. A drive shows this line only\n" &
   " while Drive Settings has it set to\n" &
   " Disk Image.\n\n" &

   " Empty drive + Space: open file browser\n" &
   " Mounted disk + Space: eject disk\n\n" &

   " File Browser:\n" &
   " Up/Down: select file\n" &
   " Left/Right: previous/next page\n" &
   " Return: mount selected file\n" &
   " Run/Stop: cancel\n" &
   " <..> at the top: the two SD cards\n\n" &

   " Mounted disks boot automatically.\n\n" &

   " ADF files are read/write: saves and\n" &
   " high scores change the file on SD.\n" &
   " This happens in the background.\n\n" &

   " Drive LED: yellow = floppy access,\n" &
   " red = hard disk, orange = both,\n" &
   " green = changes are being saved\n\n" &

   " Before eject, reset or power off,\n" &
   " wait for the LED to stay off a few\n" &
   " seconds - green can briefly return.\n\n" &

   " Crsr left/right: Prev/Next      (3/7)\n" &
   " Space or Run/Stop: Close";

constant HELP_4 : string :=

   "\n MOUSE AND JOYSTICK\n\n" &

   " Amiga mouse: Port 1  Joystick: Port 2\n" &
   " Dual mouse and dual joystick setups work\n\n" &

   " Original tank mouse:\n" &
   " Movement and left button work.\n" &
   " Right/middle buttons cannot be read.\n\n" &

   " Active mice (e.g. Alfa Data, Amitech, and\n" &
   " Amigakit) as well as active adapters (e.g.\n" &
   " Micro Tom, mouSTer, USBAMI) support\n" &
   " all buttons.\n\n" &

   " Keyboard right-button fallback:\n" &
   " MEGA65 mode: hold Run/Stop\n" &
   " Amiga mode:  hold the up-arrow symbol\n" &
   "              left of RESTORE\n\n" &

   " No mouse? In Workbench:\n" &
   " MEGA + cursor keys: move pointer\n" &
   " Add Shift: move faster\n" &
   " MEGA65 mode: MEGA + Alt: left button\n" &
   " Amiga mode:  MEGA + F13: left button\n" &
   " Works in Workbench, not games/demos.\n\n" &

   " C64 1350/1351 mice do not work.\n\n" &
   "\n\n" &  -- keep footer at bottom

   " Crsr left/right: Prev/Next      (4/7)\n" &
   " Space or Run/Stop: Close";

constant HELP_5 : string :=

   "\n VIDEO: HDMI AND ANALOG\n\n" &

   " HDMI: PAL Amiga, so 50 Hz modes only:\n" &
   "       720p 16:9\n" &
   "       576p 4:3 or 5:4\n" &
   " HDMI interlace fixing is automatic.\n\n" &

   " IMPORTANT - HDMI: Flicker-free\n" &
   " ON for HDMI-only use\n" &
   " OFF whenever using VGA/analog video\n\n" &

   " HDMI: DVI (no sound) sends plain DVI,\n" &
   " for displays that stay black on HDMI.\n" &
   " Audio is then on the 3.5 mm jack only.\n\n" &

   " The VGA connector always carries video:\n" &
   " Standard = 31 kHz, 50 Hz\n" &
   " 15 kHz HS/VS = separate sync\n" &
   " 15 kHz CSYNC = CRT / RGB SCART\n" &
   " https://a500.mega65.org/doc/retrotubes\n\n" &

   " VGA Standard does not fix interlace.\n" &
   " A 15 kHz CRT weaves it naturally.\n" &
   " HDMI stays active in every VGA mode.\n\n" &

   " Normal VGA displays cannot show 15 kHz\n" &
   " or its menu. Recover using HDMI.\n" &
   " RTG native resolution: RTG screens get\n" &
   " their own HDMI mode (up to 1080p30).\n\n" &

   " Crsr left/right: Prev/Next      (5/7)\n" &
   " Space or Run/Stop: Close";

constant HELP_6 : string :=

   "\n SCREEN ADJUSTMENT\n\n" &

   " Supplied presets:\n" &
   " aexp_screen.cfg_4_3 & aexp_screen.cfg_16_9\n" &
   " Rename one & save: /amiga/aexp_screen.cfg\n\n" &

   " Use python tool to configure screen:\n" &
   " aexp_screen_cfg.py\n" &
   " https://a500.mega65.org/doc/screen_adjust\n\n" &

   " Menu: Reload Screen Config\n" &
   " applies changes without a reboot.\n\n" &

   " HDMI crop:\n" &
   " Reframes and slightly zooms HDMI only.\n\n" &

   " Analog position:\n" &
   " Moves the complete picture and menu\n" &
   " in all three VGA modes.\n\n" &

   " Analog overscan:\n" &
   " Hides or reveals the border edges.\n\n" &

   " Settings switch for lores, hires and\n" &
   " their interlaced modes automatically.\n\n" &

   " Analog picture size cannot be changed;\n" &
   " use the monitor H/V size controls.\n\n" &
   "\n" &  -- keep footer at bottom

   " Crsr left/right: Prev/Next      (6/7)\n" &
   " Space or Run/Stop: Close";

constant HELP_7 : string :=

   "\n REAL-TIME CLOCK\n\n" &

   " Megamiga reads the MEGA65 battery RTC.\n" &
   " Set date/time on MEGA65, not the Amiga.\n" &
   " Correct time gives files proper dates.\n\n" &

   " Workbench must run SetClock LOAD during\n" &
   " startup. Stock Workbench 1.3 does this.\n" &
   " In a Shell, type: date\n\n" &

   " If the year is stuck at 1978, the old\n" &
   " Workbench SetClock has a Y2K bug.\n" &
   " Replace C:SetClock with version 34.3.\n" &
   " Check with: version c:setclock\n\n" &

   " HDMI Flicker-free makes the running\n" &
   " Amiga clock gain about 6 seconds/hour.\n\n" &

   " The Amiga side can only read the clock;\n" &
   " do not use SetClock SAVE.\n\n" &
   "\n\n\n\n\n\n\n\n\n" &  -- keep footer at bottom

   " Crsr left: Previous             (7/7)\n" &
   " Space or Run/Stop: Close";

-- Concatenate all your Welcome and Help screens into one large string, so that during synthesis one large string ROM can be build.
constant WHS_DATA : string := SCR_WELCOME & HELP_1 & HELP_2 & HELP_3 & HELP_4 & HELP_5 & HELP_6 & HELP_7;

-- The WHS array needs the start address of each page.
constant SCR_WELCOME_START : natural := 0;
constant HELP_1_START      : natural := SCR_WELCOME'length;
constant HELP_2_START      : natural := HELP_1_START + HELP_1'length;
constant HELP_3_START      : natural := HELP_2_START + HELP_2'length;
constant HELP_4_START      : natural := HELP_3_START + HELP_3'length;
constant HELP_5_START      : natural := HELP_4_START + HELP_4'length;
constant HELP_6_START      : natural := HELP_5_START + HELP_5'length;
constant HELP_7_START      : natural := HELP_6_START + HELP_6'length;

-- Fill the WHS array with page start addresses and the length of each page.
-- Make sure that array element 0 is always your Welcome page.
constant WHS : WHS_RECORD_ARRAY_TYPE := (
   --- Welcome Screen
   (page_count    => 1,
    page_start    => (SCR_WELCOME_START,  0, 0, 0, 0, 0, 0),
    page_length   => (SCR_WELCOME'length, 0, 0, 0, 0, 0, 0)),

   --- Help pages
   (page_count    => 7,
    page_start    => (HELP_1_START,  HELP_2_START,  HELP_3_START,  HELP_4_START,
                      HELP_5_START,  HELP_6_START,  HELP_7_START),
    page_length   => (HELP_1'length, HELP_2'length, HELP_3'length, HELP_4'length,
                      HELP_5'length, HELP_6'length, HELP_7'length))
);

--------------------------------------------------------------------------------------------------------------------
-- Set start folder for file browser and specify config file for menu persistence (Selectors 0x0100 and 0x0101)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant SEL_DIR_START     : std_logic_vector(15 downto 0) := x"0100";
constant SEL_CFG_FILE      : std_logic_vector(15 downto 0) := x"0101";

-- START YOUR CONFIGURATION BELOW THIS LINE

constant DIR_START         : string := "/amiga";
constant CFG_FILE          : string := "/amiga/megamiga-" & CORE_VERSION & ".cfg";

--------------------------------------------------------------------------------------------------------------------
-- General configuration settings: Reset, Pause, OSD behavior, Ascal, etc. (Selector 0x0110)
--------------------------------------------------------------------------------------------------------------------

constant SEL_GENERAL       : std_logic_vector(15 downto 0) := x"0110";  -- !!! DO NOT TOUCH !!!

-- START YOUR CONFIGURATION BELOW THIS LINE

-- at a minimum, keep the reset line active for this amount of "QNICE loops" (see gencfg.asm).
-- "0" means: deactivate this feature
constant RESET_COUNTER     : natural := 100;

-- put the core in PAUSE state if any OSD opens
-- IMPORTANT: must stay false for the Amiga core: main.vhd does not implement
-- pause_i yet (minimig has no clean pause point; would need gating of the
-- clk7/c1/c3/cck enables - later milestone)
constant OPTM_PAUSE        : boolean := false;

-- show the welcome screen in general
-- Switched off like in the C64MEGA65 reference: boots straight into the core.
-- The About & Help pages document the SD card setup, so nothing is lost.
-- (SCR_WELCOME stays defined: WHS array position 0 must always exist.)
constant WELCOME_ACTIVE    : boolean := false;

-- shall the welcome screen also be shown after the core is reset?
-- (only relevant if WELCOME_ACTIVE is true)
constant WELCOME_AT_RESET  : boolean := false;

-- keyboard and joystick connection during reset and OSD
constant KEYBOARD_AT_RESET : boolean := false;
constant JOY_1_AT_RESET    : boolean := false;
constant JOY_2_AT_RESET    : boolean := false;

constant KEYBOARD_AT_OSD   : boolean := false;
constant JOY_1_AT_OSD      : boolean := true;   -- mouse (Amiga port 1) stays active while the OSM is
                                                -- open; the keyboard belongs to the OSM (false above)
constant JOY_2_AT_OSD      : boolean := false;

-- Avalon Scaler settings (see ascal.vhd, used for HDMI output only)
-- 0=set ascal mode (via QNICE's ascal_mode_o) to the value of the config.vhd constant ASCAL_MODE
-- 1=do nothing, leave ascal mode alone, custom QNICE assembly code can still change it via M2M$ASCAL_MODE
--               and QNICE's CSR will be set to not automatically sync ascal_mode_i
-- 2=keep ascal mode in sync with the QNICE input register ascal_mode_i:
--   use this if you want to control the ascal mode for example via the Options menu
--   where you would wire the output of certain options menu bits with ascal_mode_i
constant ASCAL_USAGE       : natural := 1;   -- AUSE_CUSTOM, like C64MEGA65 V6: the HDMI Filter dispatcher in
                                             -- CORE/m2m-rom/m2m-rom.asm writes M2M$ASCAL_MODE directly (ASCAL_INIT
                                             -- in M2M/rom/gencfg.asm clears the CSR ascal-autosync bit first)
constant ASCAL_MODE        : natural := 0;   -- ignored when ASCAL_USAGE=1; m2m-rom sets the mode per HDMI Filter
                                             -- selection (No Filter/Sharp Bilinear/Bicubic -> native
                                             -- NEAREST/SBILINEAR/BICUBIC, the other 5 -> POLYPHASE)

-- Save on-screen-display settings if the file specified by CFG_FILE exists and if it has
-- the length of OPTM_SIZE bytes. If the first byte of the file has the value 0xFF then it
-- is considered as "default", i.e. the menu items specified by OPTM_G_STDSEL are selected.
-- If the file does not exists, then settings are not saved and OPTM_G_STDSEL always denotes the standard settings.
constant SAVE_SETTINGS     : boolean := true;

-- Delay in ms between the last write request to a virtual drive from the core and the start of the
-- cache flushing (i.e. writing to the SD card).
constant VD_ANTI_THRASHING_DELAY : natural := 2000;

-- Amount of bytes saved in one iteration of the background saving (buffer flushing) process
constant VD_ITERATION_SIZE       : natural := 100;

--------------------------------------------------------------------------------------------------------------------
-- Name and version of the core  (Selector 0x0200)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant SEL_CORENAME      : std_logic_vector(15 downto 0) := x"0200";

-- START YOUR CONFIGURATION BELOW THIS LINE

-- Currently this is only used in the debug console. Use the welcome screen and the
-- help system to display the name and version of your core to the end user
constant CORENAME          : string := "Megamiga " & CORE_VERSION;

--------------------------------------------------------------------------------------------------------------------
-- "Help" menu / Options menu  (Selectors 0x0300 .. 0x0312): DO NOT TOUCH
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!! Selectors for accessing the menu configuration data
constant SEL_OPTM_ITEMS       : std_logic_vector(15 downto 0) := x"0300";
constant SEL_OPTM_GROUPS      : std_logic_vector(15 downto 0) := x"0301";
constant SEL_OPTM_STDSEL      : std_logic_vector(15 downto 0) := x"0302";
constant SEL_OPTM_LINES       : std_logic_vector(15 downto 0) := x"0303";
constant SEL_OPTM_START       : std_logic_vector(15 downto 0) := x"0304";
constant SEL_OPTM_ICOUNT      : std_logic_vector(15 downto 0) := x"0305";
constant SEL_OPTM_MOUNT_DRV   : std_logic_vector(15 downto 0) := x"0306";
constant SEL_OPTM_SINGLESEL   : std_logic_vector(15 downto 0) := x"0307";
constant SEL_OPTM_MOUNT_STR   : std_logic_vector(15 downto 0) := x"0308";
constant SEL_OPTM_DIMENSIONS  : std_logic_vector(15 downto 0) := x"0309";
constant SEL_OPTM_SAVING_STR  : std_logic_vector(15 downto 0) := x"030A";
constant SEL_OPTM_HELP        : std_logic_vector(15 downto 0) := x"0310";
constant SEL_OPTM_CRTROM      : std_logic_vector(15 downto 0) := x"0311";
constant SEL_OPTM_CRTROM_STR  : std_logic_vector(15 downto 0) := x"0312";
constant SEL_OPTM_DEPS        : std_logic_vector(15 downto 0) := x"0313";   -- M2M-UPSTREAM osm-deps
constant SEL_OPTM_ROWS        : std_logic_vector(15 downto 0) := x"0314";   -- M2M-UPSTREAM menu-rows

-- !!! DO NOT TOUCH !!! Configuration constants for OPTM_GROUPS (shell.asm and menu.asm expect them to be like this)
constant OPTM_G_TEXT       : integer := 16#00000#;         -- text that cannot be selected
constant OPTM_G_CLOSE      : integer := 16#000FF#;        -- menu items that closes menu
constant OPTM_G_STDSEL     : integer := 16#00100#;        -- item within a group that is selected by default
constant OPTM_G_LINE       : integer := 16#00200#;        -- draw a line at this position
constant OPTM_G_START      : integer := 16#00400#;        -- selector / cursor position after startup (only use once!)
                                                          -- 16#00800# is used in OPTM_G_MOUNT_DRV (OPTM_G_SINGLESEL)
constant OPTM_G_HEADLINE   : integer := 16#01000#;        -- like OPTM_G_TEXT but will be shown in a brigher color
                                                          -- 16#02000# is used in OPTM_G_HELP (plus OPTM_G_SINGLESEL)
                                                          -- 16#04000# is used in OPTM_G_SUBMENU
constant OPTM_G_SINGLESEL  : integer := 16#08000#;        -- single select item
constant OPTM_G_MOUNT_DRV  : integer := 16#08800#;        -- line item means: mount drive; first occurance = drive 0, second = drive 1, ...
constant OPTM_G_HELP       : integer := 16#0A000#;        -- line item means: help screen; first occurance = WHS(1), second = WHS(2), ...
constant OPTM_G_SUBMENU    : integer := 16#0C000#;        -- starts/ends a section that is treated as submenu
constant OPTM_G_LOAD_ROM   : integer := 16#18000#;        -- line item means: load ROM; first occurance = rom 0, second = rom 1, ...
constant OPTM_G_DEPENDENT  : integer := 16#20000000#;     -- dependent line (smart dependencies, see OPTM_DEP below): visible only
                                                          -- while one of the mother-group items in a 4-bit item mask is selected (bit 29)

constant OPTM_GTC          : natural := 30;                -- Amount of significant bits in OPTM_G_* constants (max 30: 2**31 overflows
                                                           -- the integer range expression below); was 17 before the smart-dependencies
                                                           -- feature. Raising it is bit-transparent: every existing decoder arm above
                                                           -- indexes bits 0..16 of the widened vector unchanged.

--------------------------------------------------------------------------------------------------------------------
-- "Help" menu / Options menu: START YOUR CONFIGURATION BELOW THIS LINE
--------------------------------------------------------------------------------------------------------------------

-- Strings with which %s will be replaced in case the menu item is of type OPTM_G_MOUNT_DRV
constant OPTM_S_MOUNT      : string := "<Mount Drive>";     -- no disk image mounted, yet
constant OPTM_S_CRTROM     : string := "<Load>";            -- no ROM loaded, yet
constant OPTM_S_SAVING     : string := "<Saving>";          -- the internal write cache is dirty and not yet written back to the SD card

-- Size of menu and menu items
-- CAUTION: 1. End each line (also the last one) with a \n and make sure empty lines / separator lines are only consisting of a "\n"
--             Do use a lower case \n. If you forget one of them or if you use upper case, you will run into undefined behavior.
--          2. Start each line that contains an actual menu item (multi- or single-select) with a Space character,
--             otherwise you will experience visual glitches.
constant OPTM_SIZE         : natural := 252; -- amount of items including empty lines:
                                             -- needs to be equal to the number of lines in OPTM_ITEMS and amount of items in OPTM_GROUPS
                                             -- IMPORTANT: If SAVE_SETTINGS is true and OPTM_SIZE changes: Make sure to re-generate and
                                             -- and re-distribute the config file. You can make a new one using M2M/tools/make_config.sh

-- Net size of the Options menu on the screen in characters (excluding the frame, which is hardcoded to two characters)
-- Without submenus: Use OPTM_SIZE as height, otherwise use the height of the largest menu view: count one line per
-- item that is visible at that level, including one line per submenu label, excluding the contents of submenus.
-- (A submenu view does NOT show its own label line - see _OPTM_STRUCT in M2M/rom/menu.asm.)
--
-- Since the drive lines carry menu dependencies (OPTM_DEP below), OPTM_DY must count
-- the SIMULTANEOUSLY visible lines, not the structural ones: the two twin lines of a
-- drive are mutually exclusive and count once, and the "Off" variant of a drive mode
-- excludes its "Disk Image"/"Hardware Floppy" pair.
-- Both figures below are the WORST CASE over every reachable radio state, not the
-- state the menu boots into: the standard configuration is one drive (see the
-- OPTM_G_STDSEL flags below), which shows a SHORTER main menu, but the user can
-- still switch to three drives and that is what OPTM_DY has to cover.
-- Megamiga 0.6.4 (recounted; the figures here had been stale since the Settings
-- submenu took most of the main page): main menu view = 22 lines with three
-- drives (20 with one), Profile Settings = 27 (one profile block of 18),
-- Drive Settings = 26, Settings = 29, HDMI Settings = 9, HDMI Filter = 12,
-- VGA = 10, OSM Scaling = 13, Volume = 25, Stereo Mix = 8, OSM-open key = 8.
-- The Settings view is the tallest, so OPTM_DY tracks it. The frame has this
-- height in every view and the SD card status is painted on its bottom row
-- (SD_STATUS_STEP), so every row OPTM_DY is too high shows up as empty space
-- between "Close Menu" and the status (34 left 12..14 empty rows).
--
-- CEILING: OPTM_DY + 2 (frame) must not exceed CHARS_DY = VGA_DY / FONT_DY = 36
-- (globals.vhd); the Shell anchors the options OSM at y = 0 (M2M/rom/screen.asm).
constant OPTM_DX           : natural := 23;
constant OPTM_DY           : natural := 29;

-- OSM bit positions (zero-based line numbers) are decoded in mega65.vhd via C_MENU_* constants:
--   lines 13..15: Drives radio (C_MENU_DRIVES_*); how many Amiga units exist,
--                 line 13 (one drive) is the default
--   lines 19/20: df0 mode radio (C_MENU_DF0_IMG / _HW); df0 always exists,
--                 line 19 (Disk Image) is the default
--   lines 24..26: df1 mode radio (C_MENU_DF1_IMG / _HW / _OFF); line 26 default
--   lines 30..32: df2 mode radio (C_MENU_DF2_IMG / _HW / _OFF); line 32 default
--   line 34: HDF mount (manual CRT/ROM 3 into C_DEV_AMIGA_IDE); firmware-only, not decoded here
--   line 36: Drive spin-up delay toggle (C_MENU_DRV_SPINUP), default OFF; the simulated
--            drives keep /RDY inactive for 500 ms after their motor is switched on,
--            like a real drive (main.vhd, paula_floppy.v); off = Minimig's instant ready
--   line 45: 720p 50 Hz 16:9  / 46: 576p 50 4:3  / 47: 576p 50 5:4
--   line 49: DVI (no sound) toggle (C_MENU_HDMI_DVI), default OFF; drives the
--            framework's qnice_dvi input, which makes vga_to_hdmi.vhd emit plain
--            DVI - no audio and no HDMI data islands at all, while the pixels
--            and the timing stay identical. The cure for a display that rejects
--            an HDMI stream and shows nothing (a DVI monitor behind a passive
--            adapter, some scalers and capture boxes).
--   line 65: HDMI Flicker-free toggle (C_MENU_HDMI_FF)
--   line 69: VGA Standard / 73: VGA 15 kHz with HS/VS / 74: VGA 15 kHz with CSYNC
--   lines 180..188: OSM Scaling radio (C_MENU_OSM_SCALING); 100% (180, default) down to 50% (188)
--   lines 195..215: Volume radio (C_MENU_VOLUME); 100% (195, default) down to 0% (215)
--   lines 220..223: Stereo crossfeed radio (C_MENU_STEREO); Full Stereo (220, default) /
--                 Wide Stereo / Narrow Stereo / Mono -> MiSTer aud_mix encoding
--   line 130: A500 Filter toggle (C_MENU_A500FILT), default ON; the fixed
--            4400 Hz low-pass behind Paula's DAC (off = A1200-style brightness)
--   line 131: LED Filter toggle (C_MENU_LEDFILT), default ON; arms the CIA-A PA1
--            power-LED low-pass so it follows the emulated software live
--   line 135: Keyboard "Amiga" radio (C_MENU_KBD_AMIGA); 0 = MEGA65 mode (default)
--   lines 140..143: OSM-open key radio (C_MENU_OSMKEY_*); Help (140, default) / F11 /
--                 F13 / MEGA+Run-Stop -> m2m_keyb's menu-open key (qnice_keys bit 7)
--   line 150: Slow RAM (A501) toggle (C_MENU_SLOWRAM), default ON; disabling it
--            removes the 512 KB at $C00000 from the Amiga memory map (issue #20).
--            The HDL cold-boots only the emulated Amiga on a change, so that
--            amiga_config.vhd replays the userio config while QNICE keeps running.
--   line 151: Fast RAM (8 MB) toggle (C_MENU_FASTRAM), default OFF; enables the
--            8 MB Zorro II Fast RAM at $200000 in the board SDRAM. R4/R5/R6 only:
--            mega65.vhd ignores the bit on R3, which has no SDRAM. A change
--            cold-boots the Amiga like the Slow RAM toggle.
--   line 152: Zorro III RAM (16 MB) toggle (C_MENU_Z3RAM), default OFF; only with the
--            68020: one 16 MB Zorro III board in SDRAM banks 2/3, autoconfig'd by
--            Kickstart 2.0 or newer (1.3 does not know Zorro III - leave it off there)
--   lines 37 / 55 / 73 / 91: per-profile "Zorro III RAM (32 MB)" toggle (Megamiga 0.7,
--            C_PROF_Z3B = 14 in mega65.vhd; the blank line after the 16 MB toggle, so no
--            line moved), default OFF: a second, 32 MB Zorro III board in the upper halves
--            of the SDRAM rows (free since floppy-direct), independent of the 16 MB board;
--            68020/68040 only, R4+ only. With both: 48 MB ($40000000-$42FFFFFF, the 32 MB
--            board first). A change cold-boots the Amiga.
--   lines 154/155: CPU radio (C_MENU_CPU_020 = 155): 68000 (fx68k, cycle-exact, default)
--            or 68020 (TG68K, MiSTer's 68020 mode). Both changes cold-boot the Amiga.
--            [Megamiga: superseded by the per-profile CPU radio, lines 19..21 / 33..35 /
--            47..49: 68000 / 68020 / 68040; the 68040 line took the place of the blank
--            line after the radio, so no line moved and OPTM_SIZE is unchanged.]
--   lines 29 / 47 / 65 / 83: per-profile "Gayle IDE controller" toggle (Megamiga 0.7,
--            C_PROF_GAYLE = 6 in mega65.vhd; the blank line after the chipset radio, so
--            again no line moved): on = the HDFs are on the A600/A1200 Gayle IDE for the
--            Kickstart's own scsi.device, off = on the RIPPLE-compatible Zorro II board
--            with lide.device (/amiga/lide.rom). Default on for A600 and A1200, off for
--            A500 (Kickstart 1.3 has no scsi.device) and A4000 (its Kickstart drives
--            the A4000 IDE at $DD2000, not the Gayle). A change cold-boots the Amiga.
--   lines 157..159: chipset radio (C_MENU_CHIPSET_OCS = 157, C_MENU_CHIPSET_AGA = 159):
--            OCS / ECS (158, default) / AGA -> userio 0xF3 G/E bits (amiga_config.vhd);
--            a change cold-boots the Amiga. AGA = Minimig-AGA with the chip48 wide read.
--   line 161: Kickstart selector (manual CRT/ROM 4 into C_DEV_AMIGA_KICK); firmware-only:
--            PREP_LOAD_IMAGE checks the size (256 or 512 KB) and loads the ROM, the
--            kick device holds the Amiga in reset meanwhile and cold-boots it after.
--            Saved per profile in the settings file (cfg text, PROF_REMEMBER); a profile
--            without one uses /amiga/kick.rom, or holds the Amiga in reset.
--   line 204: Serial port on PMOD toggle (C_MENU_SERIAL), default OFF; Settings > Ports.
--            On = PMOD1 powered, Paula's UART and CIA-B /CTS /RTS on its pins (R4/R5/R6;
--            pin layout in mega65.vhd). Off = every PMOD pin high-Z, headers unpowered.
--   The memory toggles and the Kickstart selector live in the Memory submenu (lines
--   147..163), because the main menu has no room for another line (see the CEILING
--   note above).
-- An OCS PAL Amiga is a 50 Hz machine, so only 50 Hz HDMI modes are offered.
-- Lines 55..62 (HDMI Filter radio) are NOT decoded in mega65.vhd: the firmware
-- dispatcher LOAD_HDMI_FILTER in CORE/m2m-rom/m2m-rom.asm reads them via
-- M2M$GET_SETTING and programs ascal directly (ASCAL_USAGE=1).
--
-- DRIVE LINES 2..7 - the "twin line" pattern, straight from C64MEGA65 (its
-- issue #93). Each Amiga unit owns TWO permanently allocated main-menu lines
-- and a menu dependency (OPTM_DEP below) decides which of them is on screen:
--   * the even line " dfN:%s" is the ADF mount item (manual CRT/ROM load into
--     C_DEV_AMIGA_ADF0/1/2), shown while that drive's mode is "Disk Image";
--   * the odd line " dfN:Hardware Floppy   " is a plain TEXT line showing the
--     real MEGA65 drive, shown while the mode is "Hardware Floppy".
--   * in mode "Off" neither line is shown and the drive vanishes from the menu.
-- Both variants therefore keep their own osm_control bit and their own byte in
-- the settings file; the HDL multiplexes the active variant explicitly. Hiding
-- a mount line does NOT renumber the manual CRT/ROM ids: CRTROM_M_GI counts
-- OPTM_G_LOAD_ROM occurrences in the STATIC array and is blind to visibility.
-- The hardware lines are padded to exactly OPTM_DX characters: that trailing
-- field is where the live drive status goes once the firmware writes it (the
-- C64MEGA65 "8:Internal 1581" pattern), and the fixed width is what lets it be
-- patched in the menu heap in place, without moving the arrays behind the
-- menu-struct pointers.
-- NEVER REORDER the lines (hardware-proven fatal 0x001F): submenu blocks are
-- contiguity-defined and M2M$CFM_DATA bit i is positionally bound to line i.
constant OPTM_ITEMS        : string :=

   " Megamiga\n"            &  --   0: Headline "Megamiga"
   " df0:%s\n"              &  --   1: mount ADF into df0; cursor start
   " df0:Hardware Floppy   \n" & --   2: Text: df0 is the hardware drive
   " df1:%s\n"              &  --   3: mount ADF into df1
   " df1:Hardware Floppy   \n" & --   4: Text: df1 is the hardware drive
   " df2:%s\n"              &  --   5: mount ADF into df2
   " df2:Hardware Floppy   \n" & --   6: Text: df2 is the hardware drive
   " Mount SDCard\n"        &  --   7: Shared folder SDCard: mounted (toggle, default OFF, never saved)
   "\n"                     &  --   8: Line
   " A500 (OCS)\n"          &  --   9: Profile radio: A500 OCS (default)
   " A600 (ECS)\n"          &  --  10: Profile radio: A600 ECS
   " A1200 (AGA)\n"         &  --  11: Profile radio: A1200 AGA
   " A4000 (AGA)\n"         &  --  12: Profile radio: A4000 AGA
   "\n"                     &  --  13: Line
   " Profile Settings\n"    &  --  14: Profile Settings submenu head
   " Profile Settings\n"    &  --  15: Headline "Profile Settings"
   " HDF 0:%s\n"            &  --  16: HDF master (unit 0) into the IDE board (manual CRT/ROM load 3)
   " HDF 1:%s\n"            &  --  17: HDF slave (unit 1) into the IDE board (manual CRT/ROM load 4)
   " Kickstart:%s\n"        &  --  18: Kickstart (manual CRT/ROM load 5)
   " AR3 ROM:%s\n"          &  --  19: Action Replay III ROM (manual CRT/ROM load 6)
   "\n"                     &  --  20: Line
   " CPU: 68000\n"           & --  21: A500: CPU 68000 (row "CPU")
   " 68020\n"                & --  22: A500: CPU 68020
   " 68040\n"                & --  23: A500: CPU 68040
   " Chipset: OCS\n"         & --  24: A500: chipset OCS (row "Chipset")
   " ECS\n"                  & --  25: A500: chipset ECS
   " AGA\n"                  & --  26: A500: chipset AGA
   " Hard Disk Controller: None\n" & --  27: A500: no hard disk controller (row "Hard Disk Controller")
   " Gayle\n"                & --  28: A500: the HDFs on the A600/A1200 Gayle IDE
   " RIPPLE\n"               & --  29: A500: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
   " Chip RAM: 512 kB\n"     & --  30: A500: chip RAM 512 KB (row "Chip RAM")
   " 1 MB\n"                 & --  31: A500: chip RAM 1 MB
   " 2 MB\n"                 & --  32: A500: chip RAM 2 MB
   " Slow RAM: None\n"       & --  33: A500: no Slow RAM (row "Slow RAM")
   " 512 kB\n"               & --  34: A500: Slow RAM 512 KB
   " Monitor Cartridge: None\n" & --  35: A500: no cartridge (row "Monitor Cartridge")
   " HRTmon\n"               & --  36: A500: HRTmon cartridge (not with the 68040: greyed out)
   " AR3\n"                  & --  37: A500: Action Replay III cartridge (68000 only: greyed out)
   " Zorro Boards\n"         & --  38: A500: Headline "Zorro Boards"
   " Zorro II RAM 8 MB\n"    & --  39: A500: Zorro II Fast RAM (8 MB) toggle
   " Zorro III RAM 16 MB\n"  & --  40: A500: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
   " Zorro III RAM 32 MB\n"  & --  41: A500: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
   " Graphics Card\n"        & --  42: A500: RTG graphics card toggle (68020/68040: else greyed out)
   " Network Card\n"         & --  43: A500: network card toggle
   " CPU: 68000\n"           & --  44: A600: CPU 68000 (row "CPU")
   " 68020\n"                & --  45: A600: CPU 68020
   " 68040\n"                & --  46: A600: CPU 68040
   " Chipset: OCS\n"         & --  47: A600: chipset OCS (row "Chipset")
   " ECS\n"                  & --  48: A600: chipset ECS
   " AGA\n"                  & --  49: A600: chipset AGA
   " Hard Disk Controller: None\n" & --  50: A600: no hard disk controller (row "Hard Disk Controller")
   " Gayle\n"                & --  51: A600: the HDFs on the A600/A1200 Gayle IDE
   " RIPPLE\n"               & --  52: A600: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
   " Chip RAM: 512 kB\n"     & --  53: A600: chip RAM 512 KB (row "Chip RAM")
   " 1 MB\n"                 & --  54: A600: chip RAM 1 MB
   " 2 MB\n"                 & --  55: A600: chip RAM 2 MB
   " Slow RAM: None\n"       & --  56: A600: no Slow RAM (row "Slow RAM")
   " 512 kB\n"               & --  57: A600: Slow RAM 512 KB
   " Monitor Cartridge: None\n" & --  58: A600: no cartridge (row "Monitor Cartridge")
   " HRTmon\n"               & --  59: A600: HRTmon cartridge (not with the 68040: greyed out)
   " AR3\n"                  & --  60: A600: Action Replay III cartridge (68000 only: greyed out)
   " Zorro Boards\n"         & --  61: A600: Headline "Zorro Boards"
   " Zorro II RAM 8 MB\n"    & --  62: A600: Zorro II Fast RAM (8 MB) toggle
   " Zorro III RAM 16 MB\n"  & --  63: A600: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
   " Zorro III RAM 32 MB\n"  & --  64: A600: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
   " Graphics Card\n"        & --  65: A600: RTG graphics card toggle (68020/68040: else greyed out)
   " Network Card\n"         & --  66: A600: network card toggle
   " CPU: 68000\n"           & --  67: A1200: CPU 68000 (row "CPU")
   " 68020\n"                & --  68: A1200: CPU 68020
   " 68040\n"                & --  69: A1200: CPU 68040
   " Chipset: OCS\n"         & --  70: A1200: chipset OCS (row "Chipset")
   " ECS\n"                  & --  71: A1200: chipset ECS
   " AGA\n"                  & --  72: A1200: chipset AGA
   " Hard Disk Controller: None\n" & --  73: A1200: no hard disk controller (row "Hard Disk Controller")
   " Gayle\n"                & --  74: A1200: the HDFs on the A600/A1200 Gayle IDE
   " RIPPLE\n"               & --  75: A1200: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
   " Chip RAM: 512 kB\n"     & --  76: A1200: chip RAM 512 KB (row "Chip RAM")
   " 1 MB\n"                 & --  77: A1200: chip RAM 1 MB
   " 2 MB\n"                 & --  78: A1200: chip RAM 2 MB
   " Slow RAM: None\n"       & --  79: A1200: no Slow RAM (row "Slow RAM")
   " 512 kB\n"               & --  80: A1200: Slow RAM 512 KB
   " Monitor Cartridge: None\n" & --  81: A1200: no cartridge (row "Monitor Cartridge")
   " HRTmon\n"               & --  82: A1200: HRTmon cartridge (not with the 68040: greyed out)
   " AR3\n"                  & --  83: A1200: Action Replay III cartridge (68000 only: greyed out)
   " Zorro Boards\n"         & --  84: A1200: Headline "Zorro Boards"
   " Zorro II RAM 8 MB\n"    & --  85: A1200: Zorro II Fast RAM (8 MB) toggle
   " Zorro III RAM 16 MB\n"  & --  86: A1200: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
   " Zorro III RAM 32 MB\n"  & --  87: A1200: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
   " Graphics Card\n"        & --  88: A1200: RTG graphics card toggle (68020/68040: else greyed out)
   " Network Card\n"         & --  89: A1200: network card toggle
   " CPU: 68000\n"           & --  90: A4000: CPU 68000 (row "CPU")
   " 68020\n"                & --  91: A4000: CPU 68020
   " 68040\n"                & --  92: A4000: CPU 68040
   " Chipset: OCS\n"         & --  93: A4000: chipset OCS (row "Chipset")
   " ECS\n"                  & --  94: A4000: chipset ECS
   " AGA\n"                  & --  95: A4000: chipset AGA
   " Hard Disk Controller: None\n" & --  96: A4000: no hard disk controller (row "Hard Disk Controller")
   " Gayle\n"                & --  97: A4000: the HDFs on the A600/A1200 Gayle IDE
   " RIPPLE\n"               & --  98: A4000: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
   " Chip RAM: 512 kB\n"     & --  99: A4000: chip RAM 512 KB (row "Chip RAM")
   " 1 MB\n"                 & -- 100: A4000: chip RAM 1 MB
   " 2 MB\n"                 & -- 101: A4000: chip RAM 2 MB
   " Slow RAM: None\n"       & -- 102: A4000: no Slow RAM (row "Slow RAM")
   " 512 kB\n"               & -- 103: A4000: Slow RAM 512 KB
   " Monitor Cartridge: None\n" & -- 104: A4000: no cartridge (row "Monitor Cartridge")
   " HRTmon\n"               & -- 105: A4000: HRTmon cartridge (not with the 68040: greyed out)
   " AR3\n"                  & -- 106: A4000: Action Replay III cartridge (68000 only: greyed out)
   " Zorro Boards\n"         & -- 107: A4000: Headline "Zorro Boards"
   " Zorro II RAM 8 MB\n"    & -- 108: A4000: Zorro II Fast RAM (8 MB) toggle
   " Zorro III RAM 16 MB\n"  & -- 109: A4000: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
   " Zorro III RAM 32 MB\n"  & -- 110: A4000: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
   " Graphics Card\n"        & -- 111: A4000: RTG graphics card toggle (68020/68040: else greyed out)
   " Network Card\n"         & -- 112: A4000: network card toggle
   "\n"                     &  -- 113: Line
   " Back to main menu\n"   &  -- 114: Close Profile Settings
   " Drive Settings\n"      &  -- 115: Drive Settings submenu head
   " Drive Settings\n"      &  -- 116: Headline "Drive Settings"
   " Drives\n"              &  -- 117: Headline "Drives"
   " 1\n"                   &  -- 118: 1 (default)
   " 2\n"                   &  -- 119: 2
   " 3\n"                   &  -- 120: 3
   "\n"                     &  -- 121: Line
   " Drive df0\n"           &  -- 122: Headline "Drive df0"
   " Disk Image\n"          &  -- 123: df0 Disk Image (default)
   " Hardware Floppy\n"     &  -- 124: df0 Hardware Floppy
   "\n"                     &  -- 125: Line
   " Drive df1\n"           &  -- 126: Headline "Drive df1"
   " Disk Image\n"          &  -- 127: df1 Disk Image
   " Hardware Floppy\n"     &  -- 128: df1 Hardware Floppy
   " Off\n"                 &  -- 129: df1 Off (only while Drives = 1; default)
   "\n"                     &  -- 130: Line
   " Drive df2\n"           &  -- 131: Headline "Drive df2"
   " Disk Image\n"          &  -- 132: df2 Disk Image
   " Hardware Floppy\n"     &  -- 133: df2 Hardware Floppy
   " Off\n"                 &  -- 134: df2 Off (while Drives = 1 or 2; default)
   "\n"                     &  -- 135: Line
   " Drive spin-up delay\n" &  -- 136: Drive spin-up delay (single-select, default OFF)
   " Virtual Drive Sound: On\n" &  -- 137: Virtual Drive Sound: On (row; the internal drive sounds the disk image drives, default)
   " Noclick\n"              &  -- 138: Virtual Drive Sound: Noclick (only with a motor on: no click of an empty drive)
   " Off\n"                  &  -- 139: Virtual Drive Sound: Off
   "\n"                     &  -- 140: Line
   " Back to main menu\n"   &  -- 141: Close submenu / back to main menu
   " Settings\n"            &  -- 142: Settings submenu head (Display / Audio / Keyboard)
   " Settings\n"            &  -- 143: Headline "Settings"
   " Display\n"             &  -- 144: Headline "Display"
   " HDMI: %s\n"            &  -- 145: HDMI submenu block: "HDMI: %s"
   " HDMI Settings\n"       &  -- 146: Headline "HDMI Settings"
   " 720p 50 Hz 16:9\n"     &  -- 147: 720p 50 Hz 16:9, default
   " 576p 50 Hz 4:3\n"      &  -- 148: 576p 50 Hz 4:3
   " 576p 50 Hz 5:4\n"      &  -- 149: 576p 50 Hz 5:4
   "\n"                     &  -- 150: Line
   " DVI (no sound)\n"      &  -- 151: DVI (no sound) (single-select, default OFF)
   " RTG native resolution\n" & -- 152: RTG native resolution (single-select, default ON; was a Line)
   " Back to Settings\n"    &  -- 153: Close submenu / back to Settings
   " HDMI: %s\n"            &  -- 154: HDMI Filter submenu block: "HDMI: %s"
   " HDMI Filter\n"         &  -- 155: Headline "HDMI Filter"
   " No Filter\n"           &  -- 156: No Filter
   " Sharp Bilinear\n"      &  -- 157: Sharp Bilinear
   " Bicubic\n"             &  -- 158: Bicubic
   " Smooth\n"              &  -- 159: Smooth
   " Lanczos\n"             &  -- 160: Lanczos (default)
   " Scanlines\n"           &  -- 161: Scanlines
   " CRT (S-Video)\n"       &  -- 162: CRT (S-Video)
   " CRT (Composite)\n"     &  -- 163: CRT (Composite)
   "\n"                     &  -- 164: Line
   " Back to Settings\n"    &  -- 165: Close submenu / back to Settings
   " HDMI: Flicker-free\n"  &  -- 166: HDMI: Flicker-free (single-select, default ON)
   " VGA: %s\n"             &  -- 167: VGA submenu block: "VGA: %s"
   " VGA Display Mode\n"    &  -- 168: Headline "VGA Display Mode"
   " Standard\n"            &  -- 169: Standard (default)
   "\n"                     &  -- 170: Line
   " Retro 15 kHz mode\n"   &  -- 171: Text "Retro 15 kHz mode"
   "\n"                     &  -- 172: Line
   " 15 kHz with HS/VS\n"   &  -- 173: 15 kHz with HS/VS
   " 15 kHz with CSYNC\n"   &  -- 174: 15 kHz with CSYNC
   "\n"                     &  -- 175: Line
   " Back to Settings\n"    &  -- 176: Close submenu / back to Settings
   " Reload Screen Config\n" & -- 177: Reload screen cfg (momentary action)
   " OSM: %s\n"             &  -- 178: OSM Scaling submenu block: "OSM: %s"
   " OSM Scaling\n"         &  -- 179: Headline "OSM Scaling"
   " 100%\n"                &  -- 180: 100% (default)
   " 94%\n"                 &  -- 181: 94%
   " 88%\n"                 &  -- 182: 88%
   " 81%\n"                 &  -- 183: 81%
   " 75%\n"                 &  -- 184: 75%
   " 69%\n"                 &  -- 185: 69%
   " 63%\n"                 &  -- 186: 63%
   " 56%\n"                 &  -- 187: 56%
   " 50%\n"                 &  -- 188: 50%
   "\n"                     &  -- 189: Line
   " Back to Settings\n"    &  -- 190: Close submenu / back to Settings
   "\n"                     &  -- 191: Line
   " Audio\n"               &  -- 192: Headline "Audio"
   " Volume: %s\n"          &  -- 193: Volume submenu block: "Volume: %s"
   " Volume Control\n"      &  -- 194: Headline "Volume Control"
   " 100%\n"                &  -- 195: 100% (default)
   " 95%\n"                 &  -- 196: 95%
   " 90%\n"                 &  -- 197: 90%
   " 85%\n"                 &  -- 198: 85%
   " 80%\n"                 &  -- 199: 80%
   " 75%\n"                 &  -- 200: 75%
   " 70%\n"                 &  -- 201: 70%
   " 65%\n"                 &  -- 202: 65%
   " 60%\n"                 &  -- 203: 60%
   " 55%\n"                 &  -- 204: 55%
   " 50%\n"                 &  -- 205: 50%
   " 45%\n"                 &  -- 206: 45%
   " 40%\n"                 &  -- 207: 40%
   " 35%\n"                 &  -- 208: 35%
   " 30%\n"                 &  -- 209: 30%
   " 25%\n"                 &  -- 210: 25%
   " 20%\n"                 &  -- 211: 20%
   " 15%\n"                 &  -- 212: 15%
   " 10%\n"                 &  -- 213: 10%
   " 5%\n"                  &  -- 214: 5%
   " 0%\n"                  &  -- 215: 0% (mute)
   "\n"                     &  -- 216: Line
   " Back to Settings\n"    &  -- 217: Close submenu / back to Settings
   " Stereo: %s\n"          &  -- 218: Stereo Mix submenu block: "Stereo: %s"
   " Stereo Mix\n"          &  -- 219: Headline "Stereo Mix"
   " Full Stereo\n"         &  -- 220: Full Stereo (default)
   " Wide Stereo\n"         &  -- 221: Wide Stereo
   " Narrow Stereo\n"       &  -- 222: Narrow Stereo
   " Mono\n"                &  -- 223: Mono
   "\n"                     &  -- 224: Line
   " Back to Settings\n"    &  -- 225: Close submenu / back to Settings
   " A500 Filter\n"         &  -- 226: A500 Filter (single-select, default ON)
   " LED Filter\n"          &  -- 227: LED Filter (single-select, default ON)
   "\n"                     &  -- 228: Line
   " Keyboard\n"            &  -- 229: Headline "Keyboard"
   " Amiga\n"               &  -- 230: Amiga (pure positional)
   " MEGA65\n"              &  -- 231: MEGA65 (semantic; default)
   " OSM: %s\n"             &  -- 232: OSM-open key submenu block: "OSM: %s"
   " Key to open the menu\n" & -- 233: Headline "Key to open the menu"
   " Help\n"                &  -- 234: Help (default opener)
   " F11\n"                 &  -- 235: F11
   " F13\n"                 &  -- 236: F13
   " MEGA + Run/Stop\n"     &  -- 237: MEGA + Run/Stop
   "\n"                     &  -- 238: Line
   " Back to Settings\n"    &  -- 239: Close submenu / back to Settings
   "\n"                     &  -- 240: Line
   " Ports\n"               &  -- 241: Headline "Ports"
   " Serial port on PMOD\n" &  -- 242: Serial port on PMOD1 (single-select, default OFF)
   "\n"                     &  -- 243: Line
   " Back to main menu\n"   &  -- 244: Close Settings
   "\n"                     &  -- 245: Line
   " Freeze cartridge\n"    &  -- 246: Freeze: the cartridge button (momentary)
   "\n"                     &  -- 247: Line
   " About & Help\n"        &  -- 248: About & Help (WHS(1))
   " Close Menu\n"          &  -- 249: Close Menu (was 212; the Line moved below it)
   "\n"                     &  -- 250: Line
   " \n" ;                     -- 251: Text: empty; SD_STATUS_STEP (m2m-rom.asm) paints the live status of both SD cards on the bottom row of the main menu
-- also make sure that your group numbers are monotonic increasing (e.g. 1, 2, 3, 4, ...)
-- single-select items and therefore also drive mount items need to have unique identifiers
constant OPTM_G_ADF0       : integer := 1;   -- mount ADF for df0 (manual CRT/ROM load 0)
constant OPTM_G_HDMI       : integer := 2;
constant OPTM_G_FILTER     : integer := 3;   -- HDMI Filter radio; mirrored as OPTM_G_FLT in CORE/m2m-rom/m2m-rom.asm
constant OPTM_G_VGA        : integer := 4;   -- VGA/analog output mode radio (Standard / 15 kHz HS+VS / 15 kHz CSYNC)
constant OPTM_G_About      : integer := 5;
constant OPTM_G_SCRRELOAD  : integer := 6;   -- momentary: re-read /amiga/screen_*.bin
constant OPTM_G_HDMIFF     : integer := 7;   -- HDMI flicker-free toggle (issue #12); read in HDL (mega65.vhd)
constant OPTM_G_KBD        : integer := 8;   -- keyboard mapping mode radio (issue #6): Amiga / MEGA65; read in HDL (mega65.vhd)
constant OPTM_G_OSMKEY     : integer := 9;   -- OSM-open key radio (issue #8): Help / F11 / F13 / MEGA+Run-Stop; read in HDL (mega65.vhd)
constant OPTM_G_OSM_MODE   : integer := 10;  -- OSM Scaling radio; read in HDL (mega65.vhd)
constant OPTM_G_VOLUME     : integer := 12;  -- master volume radio (5% steps); read in HDL (mega65.vhd), attenuation applied in main.vhd
constant OPTM_G_STEREO     : integer := 13;  -- stereo crossfeed radio (MiSTer aud_mix blends); read in HDL (mega65.vhd), applied in audio_filters.vhd
constant OPTM_G_A500FILT   : integer := 14;  -- A500 Filter toggle (fixed 4400 Hz low-pass); read in HDL (mega65.vhd)
constant OPTM_G_LEDFILT    : integer := 15;  -- LED Filter toggle (CIA-A PA1 power-LED low-pass); read in HDL (mega65.vhd)

-- Floppy drives. Every unit that can ever be a simulated ADF drive needs its OWN
-- mount group, because a manual CRT/ROM line is bound to its id by its position in
-- the static array (see the DRIVE LINES comment above).
constant OPTM_G_ADF1       : integer := 16;  -- mount ADF for df1 (manual CRT/ROM load 1)
constant OPTM_G_ADF2       : integer := 17;  -- mount ADF for df2 (manual CRT/ROM load 2)
constant OPTM_G_DRIVES     : integer := 18;  -- how many Amiga units exist (1 / 2 / 3); read in HDL (mega65.vhd)
constant OPTM_G_DF0MODE    : integer := 19;  -- df0 mode radio: Disk Image / Hardware Floppy
constant OPTM_G_DF1MODE    : integer := 20;  -- df1 mode radio: Disk Image / Hardware Floppy / Off
constant OPTM_G_DF2MODE    : integer := 21;  -- df2 mode radio: Disk Image / Hardware Floppy / Off

-- Group numbers must be monotonic increasing, so a later feature lands at the
-- end of the list even when it belongs to an earlier section of the menu.
constant OPTM_G_HDMIDVI    : integer := 22;  -- DVI (no sound) toggle; read in HDL (mega65.vhd)
constant OPTM_G_HDF        : integer := 24;  -- HDF master (unit 0) into the IDE board (manual CRT/ROM load 3)
constant OPTM_G_KICK       : integer := 25;  -- load a Kickstart ROM into C_DEV_AMIGA_KICK and cold-boot (manual CRT/ROM load 5)
constant OPTM_G_SPINUP     : integer := 26;  -- Drive spin-up delay toggle; read in HDL (mega65.vhd -> main.vhd)
constant OPTM_G_PROFILE    : integer := 30;  -- machine profile radio A500 / A600 / A1200 / A4000 (main page); read in HDL, firmware loads the profile's Kickstart/HDF
constant OPTM_G_P1CPU      : integer := 31;  -- A500 profile: CPU radio 68000 / 68020 / 68040
constant OPTM_G_P1CS       : integer := 32;  -- A500 profile: chipset radio OCS / ECS / AGA
constant OPTM_G_P1CHIP     : integer := 33;  -- A500 profile: chip RAM radio 512 KB / 1 MB / 2 MB
constant OPTM_G_P1SLOW     : integer := 34;  -- A500 profile: Slow RAM radio None / 512 KB (a row; was a toggle)
constant OPTM_G_P1FAST     : integer := 35;  -- A500 profile: Zorro II Fast RAM toggle
constant OPTM_G_P1Z3       : integer := 36;  -- A500 profile: Zorro III RAM toggle
constant OPTM_G_P2CPU      : integer := 37;  -- A600 profile: CPU radio 68000 / 68020 / 68040
constant OPTM_G_P2CS       : integer := 38;  -- A600 profile: chipset radio OCS / ECS / AGA
constant OPTM_G_P2CHIP     : integer := 39;  -- A600 profile: chip RAM radio 512 KB / 1 MB / 2 MB
constant OPTM_G_P2SLOW     : integer := 40;  -- A600 profile: Slow RAM radio None / 512 KB (a row; was a toggle)
constant OPTM_G_P2FAST     : integer := 41;  -- A600 profile: Zorro II Fast RAM toggle
constant OPTM_G_P2Z3       : integer := 42;  -- A600 profile: Zorro III RAM toggle
constant OPTM_G_P3CPU      : integer := 43;  -- A1200 profile: CPU radio 68000 / 68020 / 68040
constant OPTM_G_P3CS       : integer := 44;  -- A1200 profile: chipset radio OCS / ECS / AGA
constant OPTM_G_P3CHIP     : integer := 45;  -- A1200 profile: chip RAM radio 512 KB / 1 MB / 2 MB
constant OPTM_G_P3SLOW     : integer := 46;  -- A1200 profile: Slow RAM radio None / 512 KB (a row; was a toggle)
constant OPTM_G_P3FAST     : integer := 47;  -- A1200 profile: Zorro II Fast RAM toggle
constant OPTM_G_P3Z3       : integer := 48;  -- A1200 profile: Zorro III RAM toggle
constant OPTM_G_HDF1       : integer := 49;  -- HDF slave (unit 1) into the IDE board (manual CRT/ROM load 4)
constant OPTM_G_SERIAL     : integer := 50;  -- Serial port on PMOD toggle; read in HDL (mega65.vhd drives the PMOD1 pins)
constant OPTM_G_SHARE      : integer := 51;  -- Shared folder "Mount SDCard" toggle; read by the firmware (SHARE_STEP), forced off at start (PREP_START)
constant OPTM_G_P1CART     : integer := 52;  -- A500 profile: cartridge radio None / HRTmon / Action Replay III
constant OPTM_G_P2CART     : integer := 53;  -- A600 profile: cartridge radio None / HRTmon / Action Replay III
constant OPTM_G_P3CART     : integer := 54;  -- A1200 profile: cartridge radio None / HRTmon / Action Replay III
constant OPTM_G_AR3ROM     : integer := 55;  -- Action Replay III ROM (manual CRT/ROM load 6, C_DEV_AMIGA_AR3)
constant OPTM_G_FREEZE     : integer := 56;  -- Freeze cartridge: momentary, handled by the firmware (OSM_SEL_POST)
constant OPTM_G_RTGNATIVE  : integer := 57;  -- RTG native resolution toggle: HDMI follows the RTG screenmode; read in HDL (mega65.vhd)
constant OPTM_G_P4CPU      : integer := 58;  -- A4000 profile: CPU radio 68000 / 68020 / 68040
constant OPTM_G_P4CS       : integer := 59;  -- A4000 profile: chipset radio OCS / ECS / AGA
constant OPTM_G_P4CHIP     : integer := 60;  -- A4000 profile: chip RAM radio 512 KB / 1 MB / 2 MB
constant OPTM_G_P4SLOW     : integer := 61;  -- A4000 profile: Slow RAM radio None / 512 KB (a row; was a toggle)
constant OPTM_G_P4FAST     : integer := 62;  -- A4000 profile: Zorro II Fast RAM toggle
constant OPTM_G_P4Z3       : integer := 63;  -- A4000 profile: Zorro III RAM toggle
constant OPTM_G_P4CART     : integer := 64;  -- A4000 profile: cartridge radio None / HRTmon / Action Replay III
constant OPTM_G_P1HDC      : integer := 65;  -- A500 profile: hard disk controller radio None / Gayle / RIPPLE (a row; was the Gayle toggle)
constant OPTM_G_P2HDC      : integer := 66;  -- A600 profile: hard disk controller radio None / Gayle / RIPPLE (a row; was the Gayle toggle)
constant OPTM_G_P3HDC      : integer := 67;  -- A1200 profile: hard disk controller radio None / Gayle / RIPPLE (a row; was the Gayle toggle)
constant OPTM_G_P4HDC      : integer := 68;  -- A4000 profile: hard disk controller radio None / Gayle / RIPPLE (a row; was the Gayle toggle)
constant OPTM_G_P1Z3B      : integer := 69;  -- A500 profile: Zorro III RAM (32 MB) toggle (Megamiga 0.7)
constant OPTM_G_P2Z3B      : integer := 70;  -- A600 profile: Zorro III RAM (32 MB) toggle
constant OPTM_G_P3Z3B      : integer := 71;  -- A1200 profile: Zorro III RAM (32 MB) toggle
constant OPTM_G_P4Z3B      : integer := 72;  -- A4000 profile: Zorro III RAM (32 MB) toggle
constant OPTM_G_P1GFX      : integer := 73;  -- A500 profile: graphics card (RTG, Zorro III) toggle (Megamiga 0.7)
constant OPTM_G_P2GFX      : integer := 74;  -- A600 profile: graphics card (RTG, Zorro III) toggle (Megamiga 0.7)
constant OPTM_G_P3GFX      : integer := 75;  -- A1200 profile: graphics card (RTG, Zorro III) toggle (Megamiga 0.7)
constant OPTM_G_P4GFX      : integer := 76;  -- A4000 profile: graphics card (RTG, Zorro III) toggle (Megamiga 0.7)
constant OPTM_G_P1NET      : integer := 77;  -- A500 profile: network card (Zorro II) toggle (Megamiga 0.7)
constant OPTM_G_P2NET      : integer := 78;  -- A600 profile: network card (Zorro II) toggle (Megamiga 0.7)
constant OPTM_G_P3NET      : integer := 79;  -- A1200 profile: network card (Zorro II) toggle (Megamiga 0.7)
constant OPTM_G_P4NET      : integer := 80;  -- A4000 profile: network card (Zorro II) toggle (Megamiga 0.7)
constant OPTM_G_DRVSOUND   : integer := 81;  -- Drive Settings: Virtual Drive Sound radio On / Off (a row); read in HDL (mega65.vhd)

-- Smart dependencies (M2M-UPSTREAM osm-deps): tag a line so that it is only visible
-- while one of the items of a "mother" group is selected. This is a pure VISIBILITY
-- layer - a dependent line keeps its own osm_control bit, its own saved config-file
-- byte and its own default state, so nothing about the C_MENU_* mapping in mega65.vhd
-- or about osm_const.asm changes.
--
-- OPTM_DEP(m, i)         visible while item i of mother group m is selected
-- OPTM_DEP2(m, i, j)     visible while item i OR item j of mother group m is selected
--
-- Items 0..3 ONLY: the item selector is a 4-bit mask (bits 28..25) and item 4 would
-- collide with OPTM_G_DEPENDENT itself and overflow the integer range below. For a
-- single-select mother, item 0 means "while it is off" and item 1 "while it is on".
--
-- The drive block below uses two constructs that C64MEGA65 does not, and both are
-- covered by the boot validator in M2M/rom/optm_deps.asm (its class 2 and class 3
-- were relaxed accordingly, see the M2M-UPSTREAM note there):
--   * a PARTIALLY VISIBLE radio group - the members of OPTM_G_DF1MODE / DF2MODE
--     carry different masks, so the count radio swaps "Disk Image + Hardware
--     Floppy" against "Off". The masks of one group must reference the same
--     mother and must together cover every mother item, so exactly one variant
--     is on screen in every state.
--   * a two-level CHAIN - those mode radios are dependent themselves AND are the
--     mothers of the main-menu twins. That is sound because visibility is derived
--     from the SELECTED item only, never from another line's visibility, and the
--     firmware keeps the selected mode item inside the visible variant.
function OPTM_DEP(mother : natural; item : natural) return natural is
begin
   return OPTM_G_DEPENDENT + ((2 ** item) * 16#02000000#) + (mother * 16#00020000#);
end function OPTM_DEP;
function OPTM_DEP2(mother : natural; item_a : natural; item_b : natural) return natural is
begin
   return OPTM_G_DEPENDENT + ((2 ** item_a + 2 ** item_b) * 16#02000000#) + (mother * 16#00020000#);
end function OPTM_DEP2;

-- Rows (M2M-UPSTREAM menu-rows, M2M/rom/menu_rows.asm): the radio groups listed here
-- are drawn side by side on one line, under a label line of their own:
--
--    CPU
--     *68000  68020  68040
--
-- The label is the text before ": " in the group's FIRST item ("CPU: 68000"), the
-- other items only carry their option (" 68020"); a first item without ": " gives a
-- row without a label line (the Drives row under its headline). Left/right move the
-- cursor between the options, Return/Space select. Every option stays its own menu
-- item. The items of a row group must be consecutive, a row group is a radio group (no
-- OPTM_G_SINGLESEL), and the row must fit inside the frame (OPTM_DX - 2 columns).
type OPTM_RTYPE is array (natural range <>) of natural;
constant OPTM_ROWS : OPTM_RTYPE := (
   OPTM_G_P1CPU, OPTM_G_P1CS, OPTM_G_P1HDC, OPTM_G_P1CHIP, OPTM_G_P1SLOW, OPTM_G_P1CART,
   OPTM_G_P2CPU, OPTM_G_P2CS, OPTM_G_P2HDC, OPTM_G_P2CHIP, OPTM_G_P2SLOW, OPTM_G_P2CART,
   OPTM_G_P3CPU, OPTM_G_P3CS, OPTM_G_P3HDC, OPTM_G_P3CHIP, OPTM_G_P3SLOW, OPTM_G_P3CART,
   OPTM_G_P4CPU, OPTM_G_P4CS, OPTM_G_P4HDC, OPTM_G_P4CHIP, OPTM_G_P4SLOW, OPTM_G_P4CART,
   OPTM_G_DRIVES, OPTM_G_DRVSOUND
);

-- Greyed out (M2M-UPSTREAM menu-rows): an item of group "grp" whose position in the
-- group is in the bit mask "items" (bit 0 = the group's first item; single-select: 1)
-- is drawn dimmed and the cursor skips it unless an item in the bit mask "mask" of the
-- radio group "mother" is selected (items 0..3). The setting itself is kept; mega65.vhd
-- ignores it in that state (the HDL rules this mirrors are in prof_decode).
type OPTM_AREC is record
   grp, items, mother, mask : natural;
end record;
type OPTM_ATYPE is array (natural range <>) of OPTM_AREC;
constant OPTM_AVAIL : OPTM_ATYPE := (
   -- the Zorro III boards and the graphics card need a 68020 or 68040
   (OPTM_G_P1Z3, 1, OPTM_G_P1CPU, 6), (OPTM_G_P1Z3B, 1, OPTM_G_P1CPU, 6), (OPTM_G_P1GFX, 1, OPTM_G_P1CPU, 6),
   (OPTM_G_P2Z3, 1, OPTM_G_P2CPU, 6), (OPTM_G_P2Z3B, 1, OPTM_G_P2CPU, 6), (OPTM_G_P2GFX, 1, OPTM_G_P2CPU, 6),
   (OPTM_G_P3Z3, 1, OPTM_G_P3CPU, 6), (OPTM_G_P3Z3B, 1, OPTM_G_P3CPU, 6), (OPTM_G_P3GFX, 1, OPTM_G_P3CPU, 6),
   (OPTM_G_P4Z3, 1, OPTM_G_P4CPU, 6), (OPTM_G_P4Z3B, 1, OPTM_G_P4CPU, 6), (OPTM_G_P4GFX, 1, OPTM_G_P4CPU, 6),
   -- HRTmon: 68000 and 68020; the Action Replay III: 68000 only
   (OPTM_G_P1CART, 2, OPTM_G_P1CPU, 3), (OPTM_G_P1CART, 4, OPTM_G_P1CPU, 1),
   (OPTM_G_P2CART, 2, OPTM_G_P2CPU, 3), (OPTM_G_P2CART, 4, OPTM_G_P2CPU, 1),
   (OPTM_G_P3CART, 2, OPTM_G_P3CPU, 3), (OPTM_G_P3CART, 4, OPTM_G_P3CPU, 1),
   (OPTM_G_P4CART, 2, OPTM_G_P4CPU, 3), (OPTM_G_P4CART, 4, OPTM_G_P4CPU, 1)
);

-- A headline gets a separator line drawn below it (M2M-UPSTREAM menu-rows): the
-- separator is no menu item of its own, which saves an item per headline.
constant OPTM_HEADLINE_LINE : boolean := true;

-- !!! DO NOT TOUCH !!!
type OPTM_GTYPE is array (0 to OPTM_SIZE - 1) of integer range 0 to 2**OPTM_GTC- 1;

-- define your menu groups: which menu items are belonging together to form a group?
-- where are separator lines? which items should be selected by default?
-- make sure that you have exactly the same amount of entries here than in OPTM_ITEMS and defined by OPTM_SIZE
-- NOTE: the structure is fully STATIC in every drive configuration - three
-- mount/hardware twin pairs at 2..7, Drive Settings submenu at 8..34. Only the
-- VISIBILITY of the twins follows the drive modes (OPTM_DEP), and only the
-- status text of the hardware lines is firmware-rewritten in place.
constant OPTM_GROUPS       : OPTM_GTYPE := ( OPTM_G_TEXT + OPTM_G_HEADLINE, --   0: Headline "Megamiga"
                                              OPTM_G_ADF0 + OPTM_G_LOAD_ROM + OPTM_G_START + OPTM_DEP(OPTM_G_DF0MODE, 0), --   1: mount ADF into df0; cursor start
                                              OPTM_G_TEXT + OPTM_DEP(OPTM_G_DF0MODE, 1),               --   2: Text: df0 is the hardware drive
                                              OPTM_G_ADF1 + OPTM_G_LOAD_ROM + OPTM_DEP(OPTM_G_DF1MODE, 0), --   3: mount ADF into df1
                                              OPTM_G_TEXT + OPTM_DEP(OPTM_G_DF1MODE, 1),               --   4: Text: df1 is the hardware drive
                                              OPTM_G_ADF2 + OPTM_G_LOAD_ROM + OPTM_DEP(OPTM_G_DF2MODE, 0), --   5: mount ADF into df2
                                              OPTM_G_TEXT + OPTM_DEP(OPTM_G_DF2MODE, 1),               --   6: Text: df2 is the hardware drive
                                              OPTM_G_SHARE + OPTM_G_SINGLESEL,                         --   7: Shared folder SDCard: mounted (toggle, default OFF)
                                              OPTM_G_LINE,                                             --   8: Line
                                              OPTM_G_PROFILE + OPTM_G_STDSEL,                          --   9: Profile radio: A500 OCS (default)
                                              OPTM_G_PROFILE,                                          --  10: Profile radio: A600 ECS
                                              OPTM_G_PROFILE,                                          --  11: Profile radio: A1200 AGA
                                              OPTM_G_PROFILE,                                          --  12: Profile radio: A4000 AGA
                                              OPTM_G_LINE,                                             --  13: Line
                                              OPTM_G_SUBMENU,                                          --  14: Profile Settings submenu head
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           --  15: Headline "Profile Settings"
                                              OPTM_G_HDF + OPTM_G_LOAD_ROM,                            --  16: HDF master (unit 0) into the IDE board (manual CRT/ROM load 3)
                                              OPTM_G_HDF1 + OPTM_G_LOAD_ROM,                           --  17: HDF slave (unit 1) into the IDE board (manual CRT/ROM load 4)
                                              OPTM_G_KICK + OPTM_G_LOAD_ROM,                           --  18: Kickstart (manual CRT/ROM load 5)
                                              OPTM_G_AR3ROM + OPTM_G_LOAD_ROM,                         --  19: Action Replay III ROM (manual CRT/ROM load 6)
                                              OPTM_G_LINE,                                             --  20: Line
                                              OPTM_G_P1CPU + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  21: A500: CPU 68000 (row "CPU")
                                              OPTM_G_P1CPU + OPTM_DEP(OPTM_G_PROFILE, 0),              --  22: A500: CPU 68020
                                              OPTM_G_P1CPU + OPTM_DEP(OPTM_G_PROFILE, 0),              --  23: A500: CPU 68040
                                              OPTM_G_P1CS + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  24: A500: chipset OCS (row "Chipset")
                                              OPTM_G_P1CS + OPTM_DEP(OPTM_G_PROFILE, 0),               --  25: A500: chipset ECS
                                              OPTM_G_P1CS + OPTM_DEP(OPTM_G_PROFILE, 0),               --  26: A500: chipset AGA
                                              OPTM_G_P1HDC + OPTM_DEP(OPTM_G_PROFILE, 0),              --  27: A500: no hard disk controller (row "Hard Disk Controller")
                                              OPTM_G_P1HDC + OPTM_DEP(OPTM_G_PROFILE, 0),              --  28: A500: the HDFs on the A600/A1200 Gayle IDE
                                              OPTM_G_P1HDC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  29: A500: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
                                              OPTM_G_P1CHIP + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  30: A500: chip RAM 512 KB (row "Chip RAM")
                                              OPTM_G_P1CHIP + OPTM_DEP(OPTM_G_PROFILE, 0),             --  31: A500: chip RAM 1 MB
                                              OPTM_G_P1CHIP + OPTM_DEP(OPTM_G_PROFILE, 0),             --  32: A500: chip RAM 2 MB
                                              OPTM_G_P1SLOW + OPTM_DEP(OPTM_G_PROFILE, 0),             --  33: A500: no Slow RAM (row "Slow RAM")
                                              OPTM_G_P1SLOW + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  34: A500: Slow RAM 512 KB
                                              OPTM_G_P1CART + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  35: A500: no cartridge (row "Monitor Cartridge")
                                              OPTM_G_P1CART + OPTM_DEP(OPTM_G_PROFILE, 0),             --  36: A500: HRTmon cartridge (not with the 68040: greyed out)
                                              OPTM_G_P1CART + OPTM_DEP(OPTM_G_PROFILE, 0),             --  37: A500: Action Replay III cartridge (68000 only: greyed out)
                                              OPTM_G_TEXT + OPTM_G_HEADLINE + OPTM_DEP(OPTM_G_PROFILE, 0), --  38: A500: Headline "Zorro Boards"
                                              OPTM_G_P1FAST + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  39: A500: Zorro II Fast RAM (8 MB) toggle
                                              OPTM_G_P1Z3 + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  40: A500: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P1Z3B + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  41: A500: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P1GFX + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  42: A500: RTG graphics card toggle (68020/68040: else greyed out)
                                              OPTM_G_P1NET + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 0), --  43: A500: network card toggle
                                              OPTM_G_P2CPU + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  44: A600: CPU 68000 (row "CPU")
                                              OPTM_G_P2CPU + OPTM_DEP(OPTM_G_PROFILE, 1),              --  45: A600: CPU 68020
                                              OPTM_G_P2CPU + OPTM_DEP(OPTM_G_PROFILE, 1),              --  46: A600: CPU 68040
                                              OPTM_G_P2CS + OPTM_DEP(OPTM_G_PROFILE, 1),               --  47: A600: chipset OCS (row "Chipset")
                                              OPTM_G_P2CS + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  48: A600: chipset ECS
                                              OPTM_G_P2CS + OPTM_DEP(OPTM_G_PROFILE, 1),               --  49: A600: chipset AGA
                                              OPTM_G_P2HDC + OPTM_DEP(OPTM_G_PROFILE, 1),              --  50: A600: no hard disk controller (row "Hard Disk Controller")
                                              OPTM_G_P2HDC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  51: A600: the HDFs on the A600/A1200 Gayle IDE
                                              OPTM_G_P2HDC + OPTM_DEP(OPTM_G_PROFILE, 1),              --  52: A600: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
                                              OPTM_G_P2CHIP + OPTM_DEP(OPTM_G_PROFILE, 1),             --  53: A600: chip RAM 512 KB (row "Chip RAM")
                                              OPTM_G_P2CHIP + OPTM_DEP(OPTM_G_PROFILE, 1),             --  54: A600: chip RAM 1 MB
                                              OPTM_G_P2CHIP + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  55: A600: chip RAM 2 MB
                                              OPTM_G_P2SLOW + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  56: A600: no Slow RAM (row "Slow RAM")
                                              OPTM_G_P2SLOW + OPTM_DEP(OPTM_G_PROFILE, 1),             --  57: A600: Slow RAM 512 KB
                                              OPTM_G_P2CART + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  58: A600: no cartridge (row "Monitor Cartridge")
                                              OPTM_G_P2CART + OPTM_DEP(OPTM_G_PROFILE, 1),             --  59: A600: HRTmon cartridge (not with the 68040: greyed out)
                                              OPTM_G_P2CART + OPTM_DEP(OPTM_G_PROFILE, 1),             --  60: A600: Action Replay III cartridge (68000 only: greyed out)
                                              OPTM_G_TEXT + OPTM_G_HEADLINE + OPTM_DEP(OPTM_G_PROFILE, 1), --  61: A600: Headline "Zorro Boards"
                                              OPTM_G_P2FAST + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  62: A600: Zorro II Fast RAM (8 MB) toggle
                                              OPTM_G_P2Z3 + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  63: A600: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P2Z3B + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  64: A600: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P2GFX + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  65: A600: RTG graphics card toggle (68020/68040: else greyed out)
                                              OPTM_G_P2NET + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 1), --  66: A600: network card toggle
                                              OPTM_G_P3CPU + OPTM_DEP(OPTM_G_PROFILE, 2),              --  67: A1200: CPU 68000 (row "CPU")
                                              OPTM_G_P3CPU + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  68: A1200: CPU 68020
                                              OPTM_G_P3CPU + OPTM_DEP(OPTM_G_PROFILE, 2),              --  69: A1200: CPU 68040
                                              OPTM_G_P3CS + OPTM_DEP(OPTM_G_PROFILE, 2),               --  70: A1200: chipset OCS (row "Chipset")
                                              OPTM_G_P3CS + OPTM_DEP(OPTM_G_PROFILE, 2),               --  71: A1200: chipset ECS
                                              OPTM_G_P3CS + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  72: A1200: chipset AGA
                                              OPTM_G_P3HDC + OPTM_DEP(OPTM_G_PROFILE, 2),              --  73: A1200: no hard disk controller (row "Hard Disk Controller")
                                              OPTM_G_P3HDC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  74: A1200: the HDFs on the A600/A1200 Gayle IDE
                                              OPTM_G_P3HDC + OPTM_DEP(OPTM_G_PROFILE, 2),              --  75: A1200: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
                                              OPTM_G_P3CHIP + OPTM_DEP(OPTM_G_PROFILE, 2),             --  76: A1200: chip RAM 512 KB (row "Chip RAM")
                                              OPTM_G_P3CHIP + OPTM_DEP(OPTM_G_PROFILE, 2),             --  77: A1200: chip RAM 1 MB
                                              OPTM_G_P3CHIP + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  78: A1200: chip RAM 2 MB
                                              OPTM_G_P3SLOW + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  79: A1200: no Slow RAM (row "Slow RAM")
                                              OPTM_G_P3SLOW + OPTM_DEP(OPTM_G_PROFILE, 2),             --  80: A1200: Slow RAM 512 KB
                                              OPTM_G_P3CART + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  81: A1200: no cartridge (row "Monitor Cartridge")
                                              OPTM_G_P3CART + OPTM_DEP(OPTM_G_PROFILE, 2),             --  82: A1200: HRTmon cartridge (not with the 68040: greyed out)
                                              OPTM_G_P3CART + OPTM_DEP(OPTM_G_PROFILE, 2),             --  83: A1200: Action Replay III cartridge (68000 only: greyed out)
                                              OPTM_G_TEXT + OPTM_G_HEADLINE + OPTM_DEP(OPTM_G_PROFILE, 2), --  84: A1200: Headline "Zorro Boards"
                                              OPTM_G_P3FAST + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  85: A1200: Zorro II Fast RAM (8 MB) toggle
                                              OPTM_G_P3Z3 + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  86: A1200: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P3Z3B + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  87: A1200: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P3GFX + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  88: A1200: RTG graphics card toggle (68020/68040: else greyed out)
                                              OPTM_G_P3NET + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 2), --  89: A1200: network card toggle
                                              OPTM_G_P4CPU + OPTM_DEP(OPTM_G_PROFILE, 3),              --  90: A4000: CPU 68000 (row "CPU")
                                              OPTM_G_P4CPU + OPTM_DEP(OPTM_G_PROFILE, 3),              --  91: A4000: CPU 68020
                                              OPTM_G_P4CPU + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), --  92: A4000: CPU 68040
                                              OPTM_G_P4CS + OPTM_DEP(OPTM_G_PROFILE, 3),               --  93: A4000: chipset OCS (row "Chipset")
                                              OPTM_G_P4CS + OPTM_DEP(OPTM_G_PROFILE, 3),               --  94: A4000: chipset ECS
                                              OPTM_G_P4CS + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), --  95: A4000: chipset AGA
                                              OPTM_G_P4HDC + OPTM_DEP(OPTM_G_PROFILE, 3),              --  96: A4000: no hard disk controller (row "Hard Disk Controller")
                                              OPTM_G_P4HDC + OPTM_DEP(OPTM_G_PROFILE, 3),              --  97: A4000: the HDFs on the A600/A1200 Gayle IDE
                                              OPTM_G_P4HDC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), --  98: A4000: the HDFs on the RIPPLE-compatible Zorro II IDE board (lide.device)
                                              OPTM_G_P4CHIP + OPTM_DEP(OPTM_G_PROFILE, 3),             --  99: A4000: chip RAM 512 KB (row "Chip RAM")
                                              OPTM_G_P4CHIP + OPTM_DEP(OPTM_G_PROFILE, 3),             -- 100: A4000: chip RAM 1 MB
                                              OPTM_G_P4CHIP + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 101: A4000: chip RAM 2 MB
                                              OPTM_G_P4SLOW + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 102: A4000: no Slow RAM (row "Slow RAM")
                                              OPTM_G_P4SLOW + OPTM_DEP(OPTM_G_PROFILE, 3),             -- 103: A4000: Slow RAM 512 KB
                                              OPTM_G_P4CART + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 104: A4000: no cartridge (row "Monitor Cartridge")
                                              OPTM_G_P4CART + OPTM_DEP(OPTM_G_PROFILE, 3),             -- 105: A4000: HRTmon cartridge (not with the 68040: greyed out)
                                              OPTM_G_P4CART + OPTM_DEP(OPTM_G_PROFILE, 3),             -- 106: A4000: Action Replay III cartridge (68000 only: greyed out)
                                              OPTM_G_TEXT + OPTM_G_HEADLINE + OPTM_DEP(OPTM_G_PROFILE, 3), -- 107: A4000: Headline "Zorro Boards"
                                              OPTM_G_P4FAST + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 108: A4000: Zorro II Fast RAM (8 MB) toggle
                                              OPTM_G_P4Z3 + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 109: A4000: Zorro III RAM (16 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P4Z3B + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 110: A4000: Zorro III RAM (32 MB) toggle (68020/68040: else greyed out)
                                              OPTM_G_P4GFX + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 111: A4000: RTG graphics card toggle (68020/68040: else greyed out)
                                              OPTM_G_P4NET + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_PROFILE, 3), -- 112: A4000: network card toggle
                                              OPTM_G_LINE,                                             -- 113: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 114: Close Profile Settings
                                              OPTM_G_SUBMENU,                                          -- 115: Drive Settings submenu head
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 116: Headline "Drive Settings"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 117: Headline "Drives"
                                              OPTM_G_DRIVES + OPTM_G_STDSEL,                           -- 118: 1 (default)
                                              OPTM_G_DRIVES,                                           -- 119: 2
                                              OPTM_G_DRIVES,                                           -- 120: 3
                                              OPTM_G_LINE,                                             -- 121: Line
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 122: Headline "Drive df0"
                                              OPTM_G_DF0MODE + OPTM_G_STDSEL,                          -- 123: df0 Disk Image (default)
                                              OPTM_G_DF0MODE,                                          -- 124: df0 Hardware Floppy
                                              OPTM_G_LINE,                                             -- 125: Line
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 126: Headline "Drive df1"
                                              OPTM_G_DF1MODE + OPTM_DEP2(OPTM_G_DRIVES, 1, 2),         -- 127: df1 Disk Image
                                              OPTM_G_DF1MODE + OPTM_DEP2(OPTM_G_DRIVES, 1, 2),         -- 128: df1 Hardware Floppy
                                              OPTM_G_DF1MODE + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_DRIVES, 0), -- 129: df1 Off (only while Drives = 1; default)
                                              OPTM_G_LINE,                                             -- 130: Line
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 131: Headline "Drive df2"
                                              OPTM_G_DF2MODE + OPTM_DEP(OPTM_G_DRIVES, 2),             -- 132: df2 Disk Image
                                              OPTM_G_DF2MODE + OPTM_DEP(OPTM_G_DRIVES, 2),             -- 133: df2 Hardware Floppy
                                              OPTM_G_DF2MODE + OPTM_G_STDSEL + OPTM_DEP2(OPTM_G_DRIVES, 0, 1), -- 134: df2 Off (while Drives = 1 or 2; default)
                                              OPTM_G_LINE,                                             -- 135: Line
                                              OPTM_G_SPINUP + OPTM_G_SINGLESEL,                        -- 136: Drive spin-up delay (single-select, default OFF)
                                              OPTM_G_DRVSOUND + OPTM_G_STDSEL,                         -- 137: Virtual Drive Sound: On (row; the internal drive sounds the disk image drives, default)
                                              OPTM_G_DRVSOUND,                                         -- 138: Virtual Drive Sound: Noclick (only with a motor on: no click of an empty drive)
                                              OPTM_G_DRVSOUND,                                         -- 139: Virtual Drive Sound: Off
                                              OPTM_G_LINE,                                             -- 140: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 141: Close submenu / back to main menu
                                              OPTM_G_SUBMENU,                                          -- 142: Settings submenu head (Display / Audio / Keyboard)
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 143: Headline "Settings"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 144: Headline "Display"
                                              OPTM_G_SUBMENU,                                          -- 145: HDMI submenu block: "HDMI: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 146: Headline "HDMI Settings"
                                              OPTM_G_HDMI + OPTM_G_STDSEL,                             -- 147: 720p 50 Hz 16:9, default
                                              OPTM_G_HDMI,                                             -- 148: 576p 50 Hz 4:3
                                              OPTM_G_HDMI,                                             -- 149: 576p 50 Hz 5:4
                                              OPTM_G_LINE,                                             -- 150: Line
                                              OPTM_G_HDMIDVI + OPTM_G_SINGLESEL,                       -- 151: DVI (no sound) (single-select, default OFF)
                                              OPTM_G_RTGNATIVE + OPTM_G_SINGLESEL + OPTM_G_STDSEL,     -- 152: RTG native resolution (single-select, default ON; was a Line)
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 153: Close submenu / back to Settings
                                              OPTM_G_SUBMENU,                                          -- 154: HDMI Filter submenu block: "HDMI: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 155: Headline "HDMI Filter"
                                              OPTM_G_FILTER,                                           -- 156: No Filter
                                              OPTM_G_FILTER,                                           -- 157: Sharp Bilinear
                                              OPTM_G_FILTER,                                           -- 158: Bicubic
                                              OPTM_G_FILTER,                                           -- 159: Smooth
                                              OPTM_G_FILTER + OPTM_G_STDSEL,                           -- 160: Lanczos (default)
                                              OPTM_G_FILTER,                                           -- 161: Scanlines
                                              OPTM_G_FILTER,                                           -- 162: CRT (S-Video)
                                              OPTM_G_FILTER,                                           -- 163: CRT (Composite)
                                              OPTM_G_LINE,                                             -- 164: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 165: Close submenu / back to Settings
                                              OPTM_G_HDMIFF + OPTM_G_SINGLESEL + OPTM_G_STDSEL,        -- 166: HDMI: Flicker-free (single-select, default ON)
                                              OPTM_G_SUBMENU,                                          -- 167: VGA submenu block: "VGA: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 168: Headline "VGA Display Mode"
                                              OPTM_G_VGA + OPTM_G_STDSEL,                              -- 169: Standard (default)
                                              OPTM_G_LINE,                                             -- 170: Line
                                              OPTM_G_TEXT,                                             -- 171: Text "Retro 15 kHz mode"
                                              OPTM_G_LINE,                                             -- 172: Line
                                              OPTM_G_VGA,                                              -- 173: 15 kHz with HS/VS
                                              OPTM_G_VGA,                                              -- 174: 15 kHz with CSYNC
                                              OPTM_G_LINE,                                             -- 175: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 176: Close submenu / back to Settings
                                              OPTM_G_SCRRELOAD + OPTM_G_SINGLESEL,                     -- 177: Reload screen cfg (momentary action)
                                              OPTM_G_SUBMENU,                                          -- 178: OSM Scaling submenu block: "OSM: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 179: Headline "OSM Scaling"
                                              OPTM_G_OSM_MODE + OPTM_G_STDSEL,                         -- 180: 100% (default)
                                              OPTM_G_OSM_MODE,                                         -- 181: 94%
                                              OPTM_G_OSM_MODE,                                         -- 182: 88%
                                              OPTM_G_OSM_MODE,                                         -- 183: 81%
                                              OPTM_G_OSM_MODE,                                         -- 184: 75%
                                              OPTM_G_OSM_MODE,                                         -- 185: 69%
                                              OPTM_G_OSM_MODE,                                         -- 186: 63%
                                              OPTM_G_OSM_MODE,                                         -- 187: 56%
                                              OPTM_G_OSM_MODE,                                         -- 188: 50%
                                              OPTM_G_LINE,                                             -- 189: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 190: Close submenu / back to Settings
                                              OPTM_G_LINE,                                             -- 191: Line
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 192: Headline "Audio"
                                              OPTM_G_SUBMENU,                                          -- 193: Volume submenu block: "Volume: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 194: Headline "Volume Control"
                                              OPTM_G_VOLUME + OPTM_G_STDSEL,                           -- 195: 100% (default)
                                              OPTM_G_VOLUME,                                           -- 196: 95%
                                              OPTM_G_VOLUME,                                           -- 197: 90%
                                              OPTM_G_VOLUME,                                           -- 198: 85%
                                              OPTM_G_VOLUME,                                           -- 199: 80%
                                              OPTM_G_VOLUME,                                           -- 200: 75%
                                              OPTM_G_VOLUME,                                           -- 201: 70%
                                              OPTM_G_VOLUME,                                           -- 202: 65%
                                              OPTM_G_VOLUME,                                           -- 203: 60%
                                              OPTM_G_VOLUME,                                           -- 204: 55%
                                              OPTM_G_VOLUME,                                           -- 205: 50%
                                              OPTM_G_VOLUME,                                           -- 206: 45%
                                              OPTM_G_VOLUME,                                           -- 207: 40%
                                              OPTM_G_VOLUME,                                           -- 208: 35%
                                              OPTM_G_VOLUME,                                           -- 209: 30%
                                              OPTM_G_VOLUME,                                           -- 210: 25%
                                              OPTM_G_VOLUME,                                           -- 211: 20%
                                              OPTM_G_VOLUME,                                           -- 212: 15%
                                              OPTM_G_VOLUME,                                           -- 213: 10%
                                              OPTM_G_VOLUME,                                           -- 214: 5%
                                              OPTM_G_VOLUME,                                           -- 215: 0% (mute)
                                              OPTM_G_LINE,                                             -- 216: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 217: Close submenu / back to Settings
                                              OPTM_G_SUBMENU,                                          -- 218: Stereo Mix submenu block: "Stereo: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 219: Headline "Stereo Mix"
                                              OPTM_G_STEREO + OPTM_G_STDSEL,                           -- 220: Full Stereo (default)
                                              OPTM_G_STEREO,                                           -- 221: Wide Stereo
                                              OPTM_G_STEREO,                                           -- 222: Narrow Stereo
                                              OPTM_G_STEREO,                                           -- 223: Mono
                                              OPTM_G_LINE,                                             -- 224: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 225: Close submenu / back to Settings
                                              OPTM_G_A500FILT + OPTM_G_SINGLESEL + OPTM_G_STDSEL,      -- 226: A500 Filter (single-select, default ON)
                                              OPTM_G_LEDFILT + OPTM_G_SINGLESEL + OPTM_G_STDSEL,       -- 227: LED Filter (single-select, default ON)
                                              OPTM_G_LINE,                                             -- 228: Line
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 229: Headline "Keyboard"
                                              OPTM_G_KBD,                                              -- 230: Amiga (pure positional)
                                              OPTM_G_KBD + OPTM_G_STDSEL,                              -- 231: MEGA65 (semantic; default)
                                              OPTM_G_SUBMENU,                                          -- 232: OSM-open key submenu block: "OSM: %s"
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 233: Headline "Key to open the menu"
                                              OPTM_G_OSMKEY + OPTM_G_STDSEL,                           -- 234: Help (default opener)
                                              OPTM_G_OSMKEY,                                           -- 235: F11
                                              OPTM_G_OSMKEY,                                           -- 236: F13
                                              OPTM_G_OSMKEY,                                           -- 237: MEGA + Run/Stop
                                              OPTM_G_LINE,                                             -- 238: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 239: Close submenu / back to Settings
                                              OPTM_G_LINE,                                             -- 240: Line
                                              OPTM_G_TEXT + OPTM_G_HEADLINE,                           -- 241: Headline "Ports"
                                              OPTM_G_SERIAL + OPTM_G_SINGLESEL,                        -- 242: Serial port on PMOD1 (single-select, default OFF)
                                              OPTM_G_LINE,                                             -- 243: Line
                                              OPTM_G_CLOSE + OPTM_G_SUBMENU,                           -- 244: Close Settings
                                              OPTM_G_LINE,                                             -- 245: Line
                                              OPTM_G_FREEZE + OPTM_G_SINGLESEL,                        -- 246: Freeze: the cartridge button (momentary)
                                              OPTM_G_LINE,                                             -- 247: Line
                                              OPTM_G_About + OPTM_G_HELP,                              -- 248: About & Help (WHS(1))
                                              OPTM_G_CLOSE,                                            -- 249: Close Menu
                                              OPTM_G_LINE,                                             -- 250: Line
                                              OPTM_G_TEXT                                              -- 251: Text: empty (the SD card status is painted on the bottom row)
                                           );

-- M2M-UPSTREAM menu-rows: the layout word of every item (SEL_OPTM_ROWS):
-- bit 0 = option of a row (OPTM_ROWS), bit 1 = greyed-out rule (OPTM_AVAIL) with
-- bits 5..2 = mother item mask and bits 13..6 = mother group, bit 14 = separator line
-- below the item (a headline, OPTM_HEADLINE_LINE)
type OPTM_LTYPE is array (0 to OPTM_SIZE - 1) of natural;
function optmLayout return OPTM_LTYPE is
   type cnt_t is array (0 to 255) of natural;
   variable cnt : cnt_t := (others => 0);
   variable r   : OPTM_LTYPE := (others => 0);
   variable g   : natural;
begin
   for i in 0 to OPTM_SIZE - 1 loop
      g := OPTM_GROUPS(i) mod 256;
      for k in OPTM_ROWS'range loop
         if g = OPTM_ROWS(k) then
            r(i) := r(i) + 1;
         end if;
      end loop;
      for k in OPTM_AVAIL'range loop
         if g = OPTM_AVAIL(k).grp and (OPTM_AVAIL(k).items / 2 ** cnt(g)) mod 2 = 1 then
            r(i) := r(i) + 2 + OPTM_AVAIL(k).mask * 4 + OPTM_AVAIL(k).mother * 64;
         end if;
      end loop;
      if OPTM_HEADLINE_LINE and (OPTM_GROUPS(i) / 16#1000#) mod 2 = 1 and g = 0 and
         (OPTM_GROUPS(i) / 16#4000#) mod 2 = 0 then
         r(i) := r(i) + 16#4000#;
      end if;
      cnt(g) := cnt(g) + 1;
   end loop;
   return r;
end function optmLayout;
constant OPTM_LAYOUT : OPTM_LTYPE := optmLayout;

--------------------------------------------------------------------------------------------------------------------
-- !!! CAUTION: M2M FRAMEWORK CODE !!! DO NOT TOUCH ANYTHING BELOW THIS LINE !!!
--------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------
-- Address Decoding
--------------------------------------------------------------------------------------------------------------------

begin

addr_decode : process(clk_i)
   -- return ASCII value of given string at the position defined by index (zero-based)
   pure function str2data(str : string; index : integer) return std_logic_vector is
   variable strpos : integer;
   begin
      strpos := index + 1;
      if strpos <= str'length then
         return std_logic_vector(to_unsigned(character'pos(str(strpos)), 16));
      else
         return X"0000"; -- zero terminated strings
      end if;
   end function str2data;

   -- return the dimensions of the Options menu
   pure function getDXDY(dx, dy, index: natural) return std_logic_vector is
   begin
      case index is
         when 0 => return std_logic_vector(to_unsigned(dx + 2, 16));
         when 1 => return std_logic_vector(to_unsigned(dy + 2, 16));
         when others => return X"0000";
      end case;
   end function getDXDY;

   -- convert bool to std_logic_vector
   pure function bool2slv(b: boolean) return std_logic_vector is
   begin
      if b then
         return x"0001";
      else
         return x"0000";
      end if;
   end function bool2slv;

   -- return the General Configuration settings
   function getGenConf(index: natural) return std_logic_vector is
   begin
      case index is
         when 1      => return std_logic_vector(to_unsigned(RESET_COUNTER, 16));
         when 2      => return bool2slv(OPTM_PAUSE);
         when 3      => return bool2slv(WELCOME_ACTIVE);
         when 4      => return bool2slv(WELCOME_AT_RESET);
         when 5      => return bool2slv(KEYBOARD_AT_RESET);
         when 6      => return bool2slv(JOY_1_AT_RESET);
         when 7      => return bool2slv(JOY_2_AT_RESET);
         when 8      => return bool2slv(KEYBOARD_AT_OSD);
         when 9      => return bool2slv(JOY_1_AT_OSD);
         when 10     => return bool2slv(JOY_2_AT_OSD);
         when 11     => return std_logic_vector(to_unsigned(ASCAL_USAGE, 16));
         when 12     => return std_logic_vector(to_unsigned(ASCAL_MODE, 16));
         when 13     => return std_logic_vector(to_unsigned(VD_ANTI_THRASHING_DELAY, 16));
         when 14     => return std_logic_vector(to_unsigned(VD_ITERATION_SIZE, 16));
         when 15     => return bool2slv(SAVE_SETTINGS);
         when others => return x"0000";
      end case;
   end function getGenConf;


   variable index           : integer;
   variable whs_page_index  : integer;
   variable whs_array_index : integer;

begin

   if falling_edge(clk_i) then

      index := to_integer(unsigned(address_i(11 downto 0)));
      whs_page_index  := to_integer(unsigned(address_i(19 downto 12)));
      whs_array_index := to_integer(unsigned(address_i(23 downto 20)));

      data_o <= x"EEEE";

      -----------------------------------------------------------------------------------
      -- Welcome & Help System: upper 4 bits of address equal SEL_WHS' upper 4 bits
      -----------------------------------------------------------------------------------

      if address_i(27 downto 24) = SEL_WHS(15 downto 12) then

         if  whs_array_index < WHS_RECORDS then
            if index = 4095 then
               data_o <= std_logic_vector(to_unsigned(WHS(whs_array_index).page_count, 16));
            else
               if index < WHS(whs_array_index).page_length(whs_page_index) then
                  data_o <= str2data(WHS_DATA, WHS(whs_array_index).page_start(whs_page_index) + index);
               else
                  data_o <= (others => '0'); -- zero-terminated strings
               end if;
            end if;
         end if;

      -----------------------------------------------------------------------------------
      -- All other selectors, which are 16-bit values
      -----------------------------------------------------------------------------------

      else

         case address_i(27 downto 12) is
            when SEL_GENERAL           => data_o <= getGenConf(index);
            when SEL_DIR_START         => data_o <= str2data(DIR_START, index);
            when SEL_CFG_FILE          => data_o <= str2data(CFG_FILE, index);
            when SEL_CORENAME          => data_o <= str2data(CORENAME, index);
            when SEL_OPTM_ITEMS        => data_o <= str2data(OPTM_ITEMS, index);
            when SEL_OPTM_MOUNT_STR    => data_o <= str2data(OPTM_S_MOUNT, index);
            when SEL_OPTM_CRTROM_STR   => data_o <= str2data(OPTM_S_CRTROM, index);
            when SEL_OPTM_SAVING_STR   => data_o <= str2data(OPTM_S_SAVING, index);
            when SEL_OPTM_GROUPS       => data_o <= std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15)) &
                                                    std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(14)) & "0" &
                                                    std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(12)) & "0000" &
                                                    std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(7 downto 0));
            when SEL_OPTM_STDSEL       => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(8));
            when SEL_OPTM_LINES        => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(9));
            when SEL_OPTM_START        => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(10));
            when SEL_OPTM_MOUNT_DRV    => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(11));
            when SEL_OPTM_HELP         => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(13));
            when SEL_OPTM_SINGLESEL    => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15));
            when SEL_OPTM_CRTROM       => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(16));
            when SEL_OPTM_ICOUNT       => data_o <= x"00" & std_logic_vector(to_unsigned(OPTM_SIZE, 8));
            when SEL_OPTM_DIMENSIONS   => data_o <= getDXDY(OPTM_DX, OPTM_DY, index);

            -- Smart dependencies (M2M-UPSTREAM osm-deps). Index 4095 is the feature
            -- probe: a config.vhd without this arm falls through to "when others =>
            -- null" and keeps the x"EEEE" pre-assignment, which OPTM_DEPS_PROBE reads
            -- as "feature not available" - so the firmware stays compatible with an
            -- older core. x"2DEF" selects dependency format 2 (4-bit item mask).
            -- Served word: bit 12 = dependent flag, bits 11-8 = mother item mask,
            -- bits 7-0 = mother group id.
            when SEL_OPTM_DEPS         => if index = 4095 then
                                             data_o <= x"2DEF";
                                          else
                                             data_o <= "000" &
                                                std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(29)) &
                                                std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(28 downto 25)) &
                                                std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(24 downto 17));
                                          end if;

            -- Rows (M2M-UPSTREAM menu-rows): the layout word of the item (OPTM_LAYOUT). Index
            -- 4095 is the feature probe (x"2D52"); without this arm the firmware reads the
            -- x"EEEE" pre-assignment and draws the classic menu.
            when SEL_OPTM_ROWS         => if index = 4095 then
                                             data_o <= x"2D52";
                                          elsif index < OPTM_SIZE then
                                             data_o <= std_logic_vector(to_unsigned(OPTM_LAYOUT(index), 16));
                                          else
                                             data_o <= x"0000";
                                          end if;

            when others                => null;
         end case;
      end if;
   end if;
end process;

end architecture beh;
