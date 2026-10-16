/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Johan Smolinski */
/*
 * drv_megamiga.c - PrismRTG driver for the Megamiga RTG card (Amiga core for
 * the MEGA65, github.com/johansmolinski/Megamiga).
 *
 * The board: an FPGA framebuffer. 4 MB of board memory in the MEGA65's
 * HyperRAM that the core's scaler (ascal, framebuffer mode) reads and puts on
 * HDMI, scaled to the output or 1:1 when the core's "RTG native resolution"
 * matches the mode. It takes any size: there is no CRTC to program, only the
 * size, the pixel format, the row length and the start address. A blitter
 * (fill, copy, 1-bit template) works in the board memory.
 *
 * Found as an autoconfig Zorro III board (manufacturer 2011, product 102,
 * 8 MB) on the 68020 and 68040 profiles:
 *   +$000000  board memory, 4 MB (repeats above)
 *   +$400100  display registers (16 bit; the page repeats every 4 KB):
 *               $00/$02 ADDRESS  scan-out start, HyperRAM byte address
 *                                ($400000 + VRAM offset)
 *               $04 FORMAT   bits 2:0 = 3 (8 bit), 4 (16), 5 (24), 6 (32);
 *                            bit 3 = 15 bit; bit 4 = red and blue exchanged
 *               $06 ENABLE   bit 0: the RTG picture instead of the Amiga's
 *               $08 HSIZE    $0A VSIZE (12 bit)   $0C STRIDE (14 bit, bytes)
 *               $0E ID       $4D01
 *  +$400400  palette, 256 longwords $00RRGGBB (write as one longword)
 *  +$400800  blitter (CORE/vhdl/rtg_blitter.vhd in the Megamiga repository has
 *            the full description):
 *               $00 SRC  $04 DST (long, bits 21:0 = board offset)
 *               $08 SSTRIDE $0A DSTRIDE (signed words)
 *               $0C WIDTH (bytes, 1..8190)  $0E HEIGHT (lines)
 *               $10 PAT (long, memory order)  $14 BPP (1, 2, 4)
 *               $16 CMD 1 fill, 2 copy, 3 template; read bit 0 = busy
 *               $18 TBYTES  $1A TCTRL (bits 2:0 bit offset, 3 JAM2,
 *                   4 inverted)  $1E ID ($B11B)  $20 BGPAT  $24 MASK
 *
 * Pixel formats: the board memory is a little-endian byte array as the 68k
 * sees it (byte A of the board = byte A in VRAM), the scaler reads 16-bit
 * pixels in PC order. The four formats offered are the ones Megamiga.card
 * (the board's Picasso96 driver) has shown on the hardware since Megamiga
 * 0.4: CLUT8, B8G8R8, R5G6B5PC, R8G8B8A8.
 *
 * Not there: a hardware sprite (PrismD draws the pointer), a vertical-blank
 * status (double buffering swaps at once), monitor power control, lines.
 *
 * Facts from the Megamiga sources (GPL v3: rtg.v, rtg_blitter.vhd,
 * cpu_wrapper.v; Megamiga.card.asm, LGPL 2.1), written by the board's
 * author.
 */
#include <exec/types.h>
#include <exec/memory.h>
#include <libraries/configvars.h>
#include <proto/exec.h>
#include <proto/expansion.h>
#include <stdio.h>
#include <string.h>
#include "boardops.h"
#ifdef PRISM_DRIVER_MODULE
#include "driver_module.h"
#endif

#define MM_MFR          2011
#define MM_PROD         102

#define VRAM_SIZE       0x400000UL    /* board memory                        */
#define REGS_OFFSET     0x400100UL    /* display registers, from the board   */
#define FB_BASE         0x400000UL    /* HyperRAM byte address of VRAM 0     */

/* the display registers */
#define REG_ADDRESS     0x00
#define REG_FORMAT      0x04
#define REG_ENABLE      0x06
#define REG_HSIZE       0x08
#define REG_VSIZE       0x0a
#define REG_STRIDE      0x0c
#define REG_ID          0x0e
#define REG_PALETTE     0x300
#define MM_ID           0x4d01

#define FMT_8           3
#define FMT_16          4
#define FMT_24          5
#define FMT_32          6
#define FMT_SWAP        16            /* red and blue exchanged */

/* the blitter, from the display registers */
#define BLT_OFFSET      0x700
#define BLT_SRC         0x00
#define BLT_DST         0x04
#define BLT_SSTRIDE     0x08
#define BLT_DSTRIDE     0x0a
#define BLT_WIDTH       0x0c
#define BLT_HEIGHT      0x0e
#define BLT_PAT         0x10
#define BLT_BPP         0x14
#define BLT_CMD         0x16
#define BLT_TBYTES      0x18
#define BLT_TCTRL       0x1a
#define BLT_ID          0x1e
#define BLT_BGPAT       0x20
#define BLT_MASK        0x24
#define BLT_FILL        1
#define BLT_COPY        2
#define BLT_TEMPLATE    3
#define TCTRL_JAM2      8
#define BLT_MAXW        8190
#define MM_BLT_ID       0xb11b
#define BLT_WAIT        2000000UL     /* busy polls before the engine counts as
                                         wedged (each a Zorro III access: ~1 s) */

/* Text templates are copied into two scratch areas at the top of the board
 * memory, which PrismD does not get: the CPU fills one while the engine
 * may still read the other. */
#define TMPL_SIZE       0x10000UL
#define TMPL_OFF        (VRAM_SIZE - 2 * TMPL_SIZE)

#define MAX_STRIDE      16383         /* STRIDE register: 14 bits            */
#define MAX_SIZE        4095          /* HSIZE, VSIZE: 12 bits               */

struct MMPriv {
    volatile UBYTE *blt;
    UBYTE tmplHalf;                   /* the scratch area for the next template */
    /* saveState/restoreState */
    UWORD saved[7];
    ULONG savedPal[256];
};
static struct MMPriv mmpriv;

#define W16(a, off, v)  (*(volatile UWORD *)((a) + (off)) = (UWORD)(v))
#define R16(a, off)     (*(volatile UWORD *)((a) + (off)))
#define W32(a, off, v)  (*(volatile ULONG *)((a) + (off)) = (ULONG)(v))
#define R32(a, off)     (*(volatile ULONG *)((a) + (off)))

static UWORD mm_format(UBYTE f)
{
    switch (f) {
    case PF_CLUT8:    return FMT_8;
    case PF_RGB565LE: return FMT_16 | FMT_SWAP;
    case PF_BGR24:    return FMT_24 | FMT_SWAP;
    case PF_RGBA32:   return FMT_32;
    }
    return 0;
}

/* ---- modes -------------------------------------------------------------
 * The scaler takes any size; the output timing is the core's business.
 * The row length is a register of its own, so oversized (autoscroll)
 * screens work too. */
static BOOL mm_CheckMode(struct PrismBoard *b, struct PrismMode *m)
{
    UBYTE bpp = board_bpp(m->format);
    ULONG bpr;

    if (!bpp || !(b->formats & PF_BIT(m->format)))
        return FALSE;
    if (m->width < 320 || m->height < 200 || m->width > b->maxWidth || m->height > b->maxHeight)
        return FALSE;
    if (m->pitchPixels && m->pitchPixels < m->width)
        return FALSE;
    bpr = (ULONG)(m->pitchPixels ? m->pitchPixels : m->width) * bpp;
    if (bpr > MAX_STRIDE || bpr * m->height > b->vramSize)
        return FALSE;
    m->bytesPerRow = bpr;
    return TRUE;
}

static BOOL mm_SetMode(struct PrismBoard *b, struct PrismMode *m)
{
    if (!mm_CheckMode(b, m))
        return FALSE;
    W16(b->regs, REG_FORMAT, mm_format(m->format));
    W16(b->regs, REG_STRIDE, m->bytesPerRow);
    W16(b->regs, REG_HSIZE, m->width);
    W16(b->regs, REG_VSIZE, m->height);
    return TRUE;
}

static void mm_SetDisplayStart(struct PrismBoard *b, ULONG off)
{
    W32(b->regs, REG_ADDRESS, FB_BASE + off);
}

static void mm_SetPalette(struct PrismBoard *b, UWORD first, UWORD count, const UBYTE *rgb)
{
    volatile UBYTE *pal = b->regs + REG_PALETTE + 4 * (ULONG)first;

    while (count-- && first++ < 256) {
        W32(pal, 0, ((ULONG)rgb[0] << 16) | ((ULONG)rgb[1] << 8) | rgb[2]);
        pal += 4;
        rgb += 3;
    }
}

static void mm_SetSwitch(struct PrismBoard *b, BOOL rtg)
{
    W16(b->regs, REG_ENABLE, rtg ? 1 : 0);
}

static void mm_Shutdown(struct PrismBoard *b)
{
    mm_SetSwitch(b, FALSE);
}

/* What another RTG system (Picasso96 with Megamiga.card) left on the board,
 * for PrismTest: every register reads back. */
static void mm_SaveState(struct PrismBoard *b)
{
    struct MMPriv *p = b->priv;
    int i;

    for (i = 0; i < 7; i++)
        p->saved[i] = R16(b->regs, 2 * i);
    for (i = 0; i < 256; i++)
        p->savedPal[i] = R32(b->regs, REG_PALETTE + 4 * i);
}

static void mm_RestoreState(struct PrismBoard *b)
{
    struct MMPriv *p = b->priv;
    int i;

    for (i = 0; i < 256; i++)
        W32(b->regs, REG_PALETTE + 4 * i, p->savedPal[i]);
    W16(b->regs, REG_FORMAT, p->saved[2]);
    W16(b->regs, REG_HSIZE, p->saved[4]);
    W16(b->regs, REG_VSIZE, p->saved[5]);
    W16(b->regs, REG_STRIDE, p->saved[6]);
    W16(b->regs, REG_ADDRESS, p->saved[0]);
    W16(b->regs, REG_ADDRESS + 2, p->saved[1]);
    W16(b->regs, REG_ENABLE, p->saved[3]);
}

/* ---- the blitter -------------------------------------------------------
 * A command runs on its own: every operation waits for the previous one to
 * end before it writes the registers, and PrismD calls waitBlit before the
 * CPU touches VRAM. The engine orders the CPU's earlier writes before its
 * own (it waits until they reached the memory). */
static BOOL mm_idle(struct PrismBoard *b)
{
    volatile UBYTE *blt = ((struct MMPriv *)b->priv)->blt;
    ULONG n;

    for (n = 0; n < BLT_WAIT; n++)
        if (!(R16(blt, BLT_CMD) & 1))
            return TRUE;
    return FALSE;
}

static void mm_WaitBlit(struct PrismBoard *b)
{
    if (!mm_idle(b))
        b->flags |= PBF_ACCEL_BROKEN;   /* bounded: CPU from now on */
}

/* surfaces the engine can address: in VRAM, rows a signed word apart */
static BOOL mm_surface(struct PrismBoard *b, const struct PrismSurface *s)
{
    return s->pitch <= 32767 && s->offset <= b->vramSize &&
        s->allocation <= b->vramSize - s->offset;
}

/* the colour as the pattern register wants it: the pixel's bytes first */
static ULONG mm_pattern(UBYTE bpp, ULONG c)
{
    return bpp == 1 ? c << 24 : bpp == 2 ? c << 16 : c;
}

static enum PrismResult mm_fill(struct PrismBoard *b, const struct PrismSurface *d,
                                UWORD x, UWORD y, UWORD w, UWORD h, ULONG colour)
{
    volatile UBYTE *blt = ((struct MMPriv *)b->priv)->blt;
    ULONG bytes = (ULONG)w * d->bpp;

    if (!mm_surface(b, d) || d->bpp == 3 || bytes > BLT_MAXW)
        return PR_DECLINED;
    if (!mm_idle(b))
        return PR_FAILED;
    W32(blt, BLT_DST, d->offset + (ULONG)y * d->pitch + (ULONG)x * d->bpp);
    W16(blt, BLT_DSTRIDE, d->pitch);
    W16(blt, BLT_WIDTH, bytes);
    W16(blt, BLT_HEIGHT, h);
    W32(blt, BLT_PAT, mm_pattern(d->bpp, colour));
    W16(blt, BLT_BPP, d->bpp);
    W16(blt, BLT_MASK, 0xff);
    W16(blt, BLT_CMD, BLT_FILL);
    return PR_DONE;
}

static enum PrismResult mm_copy(struct PrismBoard *b, const struct PrismSurface *s,
                                const struct PrismSurface *d, UWORD sx, UWORD sy,
                                UWORD dx, UWORD dy, UWORD w, UWORD h)
{
    volatile UBYTE *blt = ((struct MMPriv *)b->priv)->blt;
    ULONG bytes = (ULONG)w * d->bpp;
    LONG sstr = s->pitch, dstr = d->pitch;
    ULONG src, dst;

    if (!mm_surface(b, s) || !mm_surface(b, d) || bytes > BLT_MAXW)
        return PR_DECLINED;
    /* one bitmap (overlap handled below), or two that do not overlap */
    if (!(s->offset == d->offset && s->pitch == d->pitch) &&
        !(s->offset + s->allocation <= d->offset || d->offset + d->allocation <= s->offset))
        return PR_DECLINED;
    src = s->offset + (ULONG)sy * s->pitch + (ULONG)sx * s->bpp;
    dst = d->offset + (ULONG)dy * d->pitch + (ULONG)dx * d->bpp;
    /* A line is read whole before it is written, so only an overlap between
     * lines needs care: with the destination behind the source, bottom up. */
    if (dst > src) {
        src += (ULONG)(h - 1) * s->pitch;
        dst += (ULONG)(h - 1) * d->pitch;
        sstr = -sstr;
        dstr = -dstr;
    }
    if (!mm_idle(b))
        return PR_FAILED;
    W32(blt, BLT_SRC, src);
    W32(blt, BLT_DST, dst);
    W16(blt, BLT_SSTRIDE, sstr);
    W16(blt, BLT_DSTRIDE, dstr);
    W16(blt, BLT_WIDTH, bytes);
    W16(blt, BLT_HEIGHT, h);
    W16(blt, BLT_MASK, 0xff);
    W16(blt, BLT_CMD, BLT_COPY);
    return PR_DONE;
}

static enum PrismResult mm_expand(struct PrismBoard *b, const struct PrismSurface *d,
                                  UWORD x, UWORD y, UWORD w, UWORD h, const UBYTE *tmpl,
                                  ULONG mod, ULONG fg, ULONG bg, BOOL transparent)
{
    struct MMPriv *p = b->priv;
    volatile UBYTE *blt = p->blt;
    ULONG bytes = (ULONG)w * d->bpp;
    ULONG tbytes = ((ULONG)w + 7) / 8;
    ULONG tstride = (tbytes + 3) & ~3UL;
    ULONG toff;
    UBYTE *to;
    UWORD i;

    if (!mm_surface(b, d) || d->bpp == 3 || bytes > BLT_MAXW || tstride * h > TMPL_SIZE)
        return PR_DECLINED;
    /* The engine may still read the other scratch area; this one was last
     * used by the command before that, which ended before the previous one
     * started. */
    toff = TMPL_OFF + p->tmplHalf * TMPL_SIZE;
    p->tmplHalf ^= 1;
    to = b->vram + toff;
    for (i = 0; i < h; i++) {
        CopyMem((APTR)tmpl, to, tbytes);
        tmpl += mod;
        to += tstride;
    }
    if (!mm_idle(b))
        return PR_FAILED;
    W32(blt, BLT_SRC, toff);
    W32(blt, BLT_DST, d->offset + (ULONG)y * d->pitch + (ULONG)x * d->bpp);
    W16(blt, BLT_SSTRIDE, tstride);
    W16(blt, BLT_DSTRIDE, d->pitch);
    W16(blt, BLT_WIDTH, bytes);
    W16(blt, BLT_HEIGHT, h);
    W32(blt, BLT_PAT, mm_pattern(d->bpp, fg));
    W32(blt, BLT_BGPAT, mm_pattern(d->bpp, bg));
    W16(blt, BLT_BPP, d->bpp);
    W16(blt, BLT_TBYTES, tbytes);
    W16(blt, BLT_TCTRL, transparent ? 0 : TCTRL_JAM2);
    W16(blt, BLT_MASK, 0xff);
    W16(blt, BLT_CMD, BLT_TEMPLATE);
    return PR_DONE;
}

static const struct PrismOps mm_ops = { .fill = mm_fill, .copy = mm_copy, .expand = mm_expand };

/* ---- the probe ------------------------------------------------------------ */
static BOOL mm_probe(struct PrismBoard *b)
{
    struct MMPriv *p = &mmpriv;
    struct ConfigDev *cd = driver_find(NULL, MM_MFR, MM_PROD);
    UBYTE *base;

    if (!cd)
        return FALSE;
    base = (UBYTE *)cd->cd_BoardAddr;
    b->regs = (volatile UBYTE *)(base + REGS_OFFSET);
    /* the probe runs in the driver's own process and may print: only once
     * the board is found (no output on other Amigas, where PrismD on Auto
     * tries every driver) */
    printf("MEGAMIGA.driver: board at $%08lx (%lu KB), ID $%04x, blitter ID $%04x\n",
           (unsigned long)base, (unsigned long)(cd->cd_BoardSize >> 10),
           R16(b->regs, REG_ID), R16(b->regs + BLT_OFFSET, BLT_ID));
    if (R16(b->regs, REG_ID) != MM_ID) {
        printf("MEGAMIGA.driver: not the Megamiga RTG card (ID $%04x wanted)\n", MM_ID);
        return FALSE;
    }

    b->name      = "Megamiga";
    b->configDev = cd;
    b->vram      = base;
    b->vramSize  = TMPL_OFF;
    b->formats   = PF_BIT(PF_CLUT8) | PF_BIT(PF_RGB565LE) | PF_BIT(PF_BGR24) |
                   PF_BIT(PF_RGBA32);
    b->flags     = 0;
    b->maxWidth  = 1920;
    b->maxHeight = 1200;
    b->priv      = p;

    b->setMode         = mm_SetMode;
    b->checkMode       = mm_CheckMode;
    b->setDisplayStart = mm_SetDisplayStart;
    b->setPalette      = mm_SetPalette;
    b->setSwitch       = mm_SetSwitch;
    b->shutdown        = mm_Shutdown;
    b->saveState       = mm_SaveState;
    b->restoreState    = mm_RestoreState;

    p->blt = b->regs + BLT_OFFSET;
    p->tmplHalf = 0;
    if (R16(p->blt, BLT_ID) == MM_BLT_ID) {
        b->ops      = &mm_ops;
        b->flags   |= PBF_BLIT_32;
        b->waitBlit = mm_WaitBlit;
    }
    return TRUE;
}

#ifdef PRISM_DRIVER_MODULE
BOOL driver_probe(struct PrismBoard *b, const struct PrismDriverConfig *config)
{
    (void)config;
    return mm_probe(b);
}

void driver_retain(void)
{
}
#endif
