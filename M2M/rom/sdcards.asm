; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Both SD card slots at the same time
;
; M2M-UPSTREAM sd-host (two slots, Megamiga 2026-10-14): qnice.vhd has one SD
; host controller per slot (slot 0 = the bottom tray, slot 1 = the back slot);
; the QNICE SD registers 0xFF20..0xFF26 address the controller that register
; 0xFF27 (M2M$SD_SLOT) selects. Instead of the smart multiplexer that showed
; one card at a time, every card is always reachable:
;
;   * ONE device handle per slot (SDC_DEV0, SDC_DEV1), shared by everybody: the
;     file browser, the settings file, the auto-load ROMs and the core. Its
;     functions select the controller first (_SDC_*), so the FAT32 library
;     needs no change. One handle per controller also means that the FAT32
;     library tracks the owner of the controller's sector buffer correctly.
;   * A card generation per slot (SDC_GEN), counted up on every debounced
;     card-detect change. A handle mounted at an older generation is mounted
;     again by SDC$MOUNT. Whoever keeps a file open remembers the generation it
;     was opened at and stops using it when the generation changed (that
;     replaces the old SD_CHANGED / active-slot checks).
;   * Code that reads or writes the controller's buffer directly (IO$SD_DATA)
;     selects the controller of its device first: SDC$SELDEV.
;
; done by the Megamiga fork in 2026 and licensed under GPL v3
; ****************************************************************************

SDC_DEBOUNCE    .EQU    77                      ; IO$CYC_MID ticks: ~100 ms

; ----------------------------------------------------------------------------
; SDC$INIT: called once at the start of the Shell. No handle is mounted, the
; cards that are in the slots now count as present (no debounce at start).
; All registers preserved.
; ----------------------------------------------------------------------------

SDC$INIT        INCRB
                MOVE    SDC_DEV0, R0
                MOVE    0, @R0
                MOVE    SDC_DEV1, R0
                MOVE    0, @R0
                MOVE    SDC_GEN, R0
                MOVE    1, @R0++
                MOVE    1, @R0
                MOVE    SDC_MGEN, R0
                MOVE    0, @R0++
                MOVE    0, @R0
                MOVE    SDC_HOME, R0            ; no settings file (yet)
                MOVE    0xFFFF, @R0
                XOR     R8, R8
                RSUB    _SDC_RAW, 1
                MOVE    SDC_PRES, R0
                MOVE    R9, @R0++
                MOVE    SDC_RAW, R1
                MOVE    R9, @R1++
                MOVE    1, R8
                RSUB    _SDC_RAW, 1
                MOVE    R9, @R0
                MOVE    R9, @R1
                MOVE    M2M$SD_SLOT, R0
                MOVE    0, @R0
                DECRB
                RET

; _SDC_RAW: R8 = slot -> R9 = 1 if its card-detect reports a card. R8 kept.
_SDC_RAW        MOVE    M2M$CSR, R9
                MOVE    @R9, R9
                CMP     0, R8
                RBRA    _SDCR_1, !Z
                AND     M2M$CSR_SD_DET_INT, R9
                RBRA    _SDCR_N, Z
                MOVE    1, R9
                RET
_SDCR_1         AND     M2M$CSR_SD_DET_EXT, R9
                RBRA    _SDCR_N, Z
                MOVE    1, R9
                RET
_SDCR_N         XOR     R9, R9
                RET

; ----------------------------------------------------------------------------
; SDC$POLL: called in every HANDLE_IO. A card-detect level counts once it
; held for SDC_DEBOUNCE; then the slot gets a new generation. All registers
; preserved.
; ----------------------------------------------------------------------------

SDC$POLL        INCRB
                MOVE    R8, R6
                MOVE    R9, R7
                XOR     R8, R8                  ; R8: slot
_SDCP_L         RSUB    _SDC_RAW, 1             ; R9: card there
                MOVE    SDC_RAW, R0
                ADD     R8, R0
                MOVE    SDC_RAWT, R1
                ADD     R8, R1
                CMP     @R0, R9
                RBRA    _SDCP_STB, Z
                MOVE    R9, @R0                 ; changed: wait until it holds
                MOVE    IO$CYC_MID, R2
                MOVE    @R2, @R1
                RBRA    _SDCP_N, 1
_SDCP_STB       MOVE    SDC_PRES, R0            ; a new level that held?
                ADD     R8, R0
                CMP     @R0, R9
                RBRA    _SDCP_N, Z
                MOVE    IO$CYC_MID, R2
                MOVE    @R2, R2
                SUB     @R1, R2
                CMP     SDC_DEBOUNCE, R2
                RBRA    _SDCP_N, N              ; (SDC_DEBOUNCE > R2)
                MOVE    R9, @R0
                MOVE    SDC_GEN, R0             ; the next generation
                ADD     R8, R0
                ADD     1, @R0
_SDCP_N         ADD     1, R8
                CMP     2, R8
                RBRA    _SDCP_L, !Z
                MOVE    R6, R8
                MOVE    R7, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; SDC$DEV: R8 = slot -> R8 = its device handle. Other registers preserved.
; SDC$SLOT: R8 = a device handle on one of the two controllers -> R8 = the
; slot (its block read function tells; also for a copy of a handle, e.g. the
; shared folder's). Other registers preserved.
; SDC$GEN: R8 = slot -> R8 = its card generation. Other registers preserved.
; ----------------------------------------------------------------------------

SDC$DEV         CMP     0, R8
                RBRA    _SDCD_1, !Z
                MOVE    SDC_DEV0, R8
                RET
_SDCD_1         MOVE    SDC_DEV1, R8
                RET

SDC$SLOT        ADD     FAT32$DEV_BLOCK_READ, R8
                CMP     _SDC_RB1, @R8
                RBRA    _SDCS_1, Z
                XOR     R8, R8
                RET
_SDCS_1         MOVE    1, R8
                RET

SDC$GEN         ADD     SDC_GEN, R8
                MOVE    @R8, R8
                RET

; ----------------------------------------------------------------------------
; SDC$SELDEV: select the controller of device handle R8 for a direct access
; to its sector buffer (IO$SD_DATA_POS, IO$SD_DATA). SDC$SEL: the same for
; slot R8. All registers preserved.
; ----------------------------------------------------------------------------

SDC$SELDEV      MOVE    R8, @--SP
                RSUB    SDC$SLOT, 1
                RSUB    SDC$SEL, 1
                MOVE    @SP++, R8
                RET

SDC$SEL         MOVE    R9, @--SP
                MOVE    M2M$SD_SLOT, R9
                MOVE    R8, @R9
                MOVE    @SP++, R9
                RET

; ----------------------------------------------------------------------------
; SDC$PRESENT: R8 = slot. C=1 if a card is in it (debounced), else C=0.
; All registers preserved.
; ----------------------------------------------------------------------------

SDC$PRESENT     MOVE    R8, @--SP
                ADD     SDC_PRES, R8
                CMP     0, @R8
                RBRA    _SDCPR_0, Z
                MOVE    @SP++, R8
                OR      0x0004, SR              ; C=1 (after the MOVE: it
                RET                             ; changes Z and N, not C)
_SDCPR_0        MOVE    @SP++, R8
                AND     0xFFFB, SR              ; C=0
                RET

; ----------------------------------------------------------------------------
; SDC$MOUNT: mount the card in slot R8 (partition 1) on its device handle,
; unless it is mounted already at the current card generation.
; Output: R8 = the device handle, R9 = 0 if mounted, else an error code
; (SD$ERR_NO_CARD without a card). Other registers preserved.
; ----------------------------------------------------------------------------

SDC$MOUNT       INCRB
                MOVE    R8, R0                  ; R0: slot
                RSUB    SDC$DEV, 1
                MOVE    R8, R1                  ; R1: the device handle
                MOVE    SDC_GEN, R2
                ADD     R0, R2
                MOVE    SDC_MGEN, R3
                ADD     R0, R3
                MOVE    SDC_PRES, R4
                ADD     R0, R4
                CMP     0, @R4
                RBRA    _SDCM_NOC, Z
                CMP     0, @R1                  ; mounted at this generation?
                RBRA    _SDCM_DO, Z
                CMP     @R2, @R3
                RBRA    _SDCM_OK, Z
_SDCM_DO        MOVE    _SDC_FN, R4             ; the functions of this slot
                CMP     0, R0
                RBRA    _SDCM_F, Z
                ADD     5, R4
_SDCM_F         MOVE    R1, R5
                MOVE    @R4++, @R5++            ; DEV_RESET .. DEV_BYTE_WRITE
                MOVE    @R4++, @R5++
                MOVE    @R4++, @R5++
                MOVE    @R4++, @R5++
                MOVE    @R4, @R5++
                MOVE    1, @R5                  ; DEV_PARTITION: partition 1
                MOVE    R1, R8
                RSUB    FAT32$MOUNT, 1          ; R9: 0 or the error
                CMP     0, R9
                RBRA    _SDCM_ERR, !Z
                MOVE    @R2, @R3                ; mounted at this generation
                RBRA    _SDCM_RET, 1
_SDCM_NOC       MOVE    SD$ERR_NO_CARD, R9
_SDCM_ERR       MOVE    0, @R1                  ; not mounted
                RBRA    _SDCM_RET, 1
_SDCM_OK        XOR     R9, R9
_SDCM_RET       MOVE    R1, R8
                DECRB
                RET

; ----------------------------------------------------------------------------
; SDC$HOMEDEV: the device handle of the card the settings file came from (or
; is to come from), mounted. Output: R8 = the device handle, R9 = 0 if
; mounted, else an error code. Other registers preserved.
; ----------------------------------------------------------------------------

SDC$HOMEDEV     MOVE    SDC_HOME, R8
                MOVE    @R8, R8
                CMP     0xFFFF, R8              ; no settings file: the back
                RBRA    _SDCH_M, !Z             ; card if there is one, else
                MOVE    1, R8                   ; the tray
                RSUB    SDC$PRESENT, 1
                RBRA    _SDCH_M, C
                XOR     R8, R8
_SDCH_M         RBRA    SDC$MOUNT, 1

; ----------------------------------------------------------------------------
; The device functions of the two slots: select the controller, then the
; function of sd_library.asm (which returns to the caller of the stub).
; ----------------------------------------------------------------------------

_SDC_FN         .DW     _SDC_RST0, _SDC_RB0, _SDC_WB0, _SDC_RY0, _SDC_WY0
                .DW     _SDC_RST1, _SDC_RB1, _SDC_WB1, _SDC_RY1, _SDC_WY1

_SDC_RST0       RSUB    _SDC_S0, 1
                RBRA    SD$RESET, 1
_SDC_RB0        RSUB    _SDC_S0, 1
                RBRA    SD$READ_BLOCK, 1
_SDC_WB0        RSUB    _SDC_S0, 1
                RBRA    SD$WRITE_BLOCK, 1
_SDC_RY0        RSUB    _SDC_S0, 1
                RBRA    SD$READ_BYTE, 1
_SDC_WY0        RSUB    _SDC_S0, 1
                RBRA    SD$WRITE_BYTE, 1
_SDC_RST1       RSUB    _SDC_S1, 1
                RBRA    SD$RESET, 1
_SDC_RB1        RSUB    _SDC_S1, 1
                RBRA    SD$READ_BLOCK, 1
_SDC_WB1        RSUB    _SDC_S1, 1
                RBRA    SD$WRITE_BLOCK, 1
_SDC_RY1        RSUB    _SDC_S1, 1
                RBRA    SD$READ_BYTE, 1
_SDC_WY1        RSUB    _SDC_S1, 1
                RBRA    SD$WRITE_BYTE, 1

_SDC_S0         MOVE    R8, @--SP
                MOVE    M2M$SD_SLOT, R8
                MOVE    0, @R8
                MOVE    @SP++, R8
                RET
_SDC_S1         MOVE    R8, @--SP
                MOVE    M2M$SD_SLOT, R8
                MOVE    1, @R8
                MOVE    @SP++, R8
                RET
