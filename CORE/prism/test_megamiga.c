/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Johan Smolinski */
/*
 * test_megamiga.c - host fixture for drv_megamiga.c in PrismRTG's style
 * (tests/zz_surfaces.c): the driver against fake registers, plus a model of
 * the Megamiga blitter as CORE/vhdl/rtg_blitter.vhd describes it. Every
 * accelerated fill, copy and text expansion is run on the model and must
 * leave VRAM byte-identical to a plain CPU reference; the rest checks the
 * mode, palette and display-start registers and the decline rules.
 *
 * Copied into a PrismRTG checkout's tests/ by CORE/prism/test.sh, built with
 * amiga-gcc and run under vamos.
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../src/drv_megamiga.c"
struct ExpansionBase *ExpansionBase = NULL; /* not common: keeps libnix from auto-opening it */

static UBYTE regs[0x800 + 0x40];            /* display registers + palette + blitter */
static UBYTE *vram, *ref;                   /* 4 MB each */
static ULONG seed = 12345;
static ULONG rnd(void) { seed = seed * 1103515245UL + 12345UL; return seed >> 8; }

#define BREG16(off) R16(regs + BLT_OFFSET, off)
#define BREG32(off) R32(regs + BLT_OFFSET, off)

/* the engine, as rtg_blitter.vhd describes it; runs the command just started */
static void blitter(void)
{
    UWORD cmd = BREG16(BLT_CMD);
    ULONG src = BREG32(BLT_SRC) & 0x3fffff, dst = BREG32(BLT_DST) & 0x3fffff;
    WORD sstr = (WORD)BREG16(BLT_SSTRIDE), dstr = (WORD)BREG16(BLT_DSTRIDE);
    UWORD width = BREG16(BLT_WIDTH), height = BREG16(BLT_HEIGHT);
    UWORD bpp = BREG16(BLT_BPP), tbytes = BREG16(BLT_TBYTES), tctrl = BREG16(BLT_TCTRL);
    ULONG pat = BREG32(BLT_PAT), bgpat = BREG32(BLT_BGPAT);
    static UBYTE line[8192];
    UWORD l, i;

    assert(BREG16(BLT_MASK) == 0xff);
    assert(width >= 1 && width <= BLT_MAXW);
    for (l = 0; l < height; l++) {
        UBYTE *d = vram + dst;
        if (cmd == BLT_FILL) {
            assert(bpp == 1 || bpp == 2 || bpp == 4);
            for (i = 0; i < width; i++)
                d[i] = pat >> (24 - 8 * (i % bpp));
        } else if (cmd == BLT_COPY) {
            memcpy(line, vram + src, width);       /* the whole line first */
            memcpy(d, line, width);
        } else if (cmd == BLT_TEMPLATE) {
            assert(tbytes >= 1 && tbytes <= BLT_MAXW);
            memcpy(line, vram + src, tbytes);
            for (i = 0; i < width; i++) {
                ULONG bit = (tctrl & 7) + i / bpp;
                BOOL set = (line[bit / 8] >> (7 - bit % 8)) & 1;
                assert(bit / 8 < tbytes);
                if (tctrl & 16)
                    set = !set;
                if (set)
                    d[i] = pat >> (24 - 8 * (i % bpp));
                else if (tctrl & TCTRL_JAM2)
                    d[i] = bgpat >> (24 - 8 * (i % bpp));
            }
        } else
            assert(!"unknown command");
        src = (src + sstr) & 0x3fffff;
        dst = (dst + dstr) & 0x3fffff;
    }
    W16(regs + BLT_OFFSET, BLT_CMD, 0);            /* idle again */
}

/* CPU references */
static void put(UBYTE *m, const struct PrismSurface *s, UWORD x, UWORD y, ULONG c)
{
    UBYTE *p = m + s->offset + (ULONG)y * s->pitch + (ULONG)x * s->bpp;
    UBYTE i;
    for (i = 0; i < s->bpp; i++)
        p[i] = c >> (8 * (s->bpp - 1 - i));
}
static void ref_fill(const struct PrismSurface *s, UWORD x, UWORD y, UWORD w, UWORD h, ULONG c)
{
    UWORD i, j;
    for (j = 0; j < h; j++)
        for (i = 0; i < w; i++)
            put(ref, s, x + i, y + j, c);
}
static void ref_copy(const struct PrismSurface *s, const struct PrismSurface *d,
                     UWORD sx, UWORD sy, UWORD dx, UWORD dy, UWORD w, UWORD h)
{
    ULONG n = (ULONG)w * s->bpp;
    UBYTE *tmp = malloc(n * h);
    UWORD j;
    for (j = 0; j < h; j++)
        memcpy(tmp + j * n, ref + s->offset + (ULONG)(sy + j) * s->pitch + (ULONG)sx * s->bpp, n);
    for (j = 0; j < h; j++)
        memcpy(ref + d->offset + (ULONG)(dy + j) * d->pitch + (ULONG)dx * d->bpp, tmp + j * n, n);
    free(tmp);
}
static void ref_expand(const struct PrismSurface *s, UWORD x, UWORD y, UWORD w, UWORD h,
                       const UBYTE *t, ULONG mod, ULONG fg, ULONG bg, BOOL tr)
{
    UWORD i, j;
    for (j = 0; j < h; j++)
        for (i = 0; i < w; i++) {
            if ((t[j * mod + i / 8] >> (7 - i % 8)) & 1)
                put(ref, s, x + i, y + j, fg);
            else if (!tr)
                put(ref, s, x + i, y + j, bg);
        }
}

static void same(const char *what, ULONG n)
{
    if (memcmp(vram, ref, TMPL_OFF)) {
        ULONG i;
        for (i = 0; i < TMPL_OFF && vram[i] == ref[i]; i++)
            ;
        printf("%s #%lu: VRAM differs at offset %lu (%02x, expected %02x)\n",
               what, (unsigned long)n, (unsigned long)i, vram[i], ref[i]);
        exit(1);
    }
}

static ULONG colour(UBYTE bpp)
{
    ULONG c = rnd() ^ (rnd() << 16);
    return bpp == 4 ? c : c & ((1UL << (8 * bpp)) - 1);
}

int main(void)
{
    struct PrismBoard b = {0};
    struct PrismMode m = {0};
    static const UBYTE fmts[] = { PF_CLUT8, PF_RGB565LE, PF_BGR24, PF_RGBA32 };
    static UBYTE tmpl[64 * 40];
    struct PrismSurface s, d;
    ULONG n, i;
    UBYTE f;

    (void)mm_probe;                          /* needs a ConfigDev: on the hardware only */

    vram = malloc(VRAM_SIZE);
    ref = malloc(VRAM_SIZE);
    assert(vram && ref);
    for (i = 0; i < VRAM_SIZE; i++)
        vram[i] = ref[i] = rnd();

    b.regs = regs;
    b.vram = vram;
    b.vramSize = TMPL_OFF;
    b.priv = &mmpriv;
    b.ops = &mm_ops;
    b.formats = PF_BIT(PF_CLUT8) | PF_BIT(PF_RGB565LE) | PF_BIT(PF_BGR24) | PF_BIT(PF_RGBA32);
    b.maxWidth = 1920;
    b.maxHeight = 1200;
    mmpriv.blt = regs + BLT_OFFSET;

    /* modes */
    m.width = 800; m.height = 600; m.format = PF_RGB565LE;
    assert(mm_SetMode(&b, &m) && m.bytesPerRow == 1600);
    assert(R16(regs, REG_FORMAT) == 20 && R16(regs, REG_STRIDE) == 1600);
    assert(R16(regs, REG_HSIZE) == 800 && R16(regs, REG_VSIZE) == 600);
    m.format = PF_CLUT8; assert(mm_CheckMode(&b, &m) && R16(regs, REG_FORMAT) == 20);
    assert(mm_SetMode(&b, &m) && R16(regs, REG_FORMAT) == 3);
    m.format = PF_BGR24; assert(mm_SetMode(&b, &m) && R16(regs, REG_FORMAT) == 21);
    m.format = PF_RGBA32; assert(mm_SetMode(&b, &m) && R16(regs, REG_FORMAT) == 6);
    assert(m.bytesPerRow == 3200);
    m.format = PF_RGB565BE; assert(!mm_CheckMode(&b, &m));
    m.format = PF_RGBA32; m.width = 1920; m.height = 1080;
    assert(!mm_CheckMode(&b, &m));                 /* 8.3 MB: more than VRAM */
    m.format = PF_RGB565LE; assert(!mm_CheckMode(&b, &m));  /* 4.1 MB */
    m.format = PF_CLUT8; assert(mm_CheckMode(&b, &m) && m.bytesPerRow == 1920);
    m.width = 1024; m.height = 768; m.format = PF_RGB565LE; m.pitchPixels = 1600;
    assert(mm_SetMode(&b, &m) && m.bytesPerRow == 3200 && R16(regs, REG_STRIDE) == 3200);
    assert(R16(regs, REG_HSIZE) == 1024);
    m.format = PF_RGBA32; m.pitchPixels = 4096; assert(!mm_CheckMode(&b, &m)); /* STRIDE 14 bit */
    m.pitchPixels = 1000; assert(!mm_CheckMode(&b, &m));                       /* narrower */
    m.pitchPixels = 0; m.width = 1921; assert(!mm_CheckMode(&b, &m));
    m.width = 319; assert(!mm_CheckMode(&b, &m));

    /* display start, palette, switch */
    mm_SetDisplayStart(&b, 0x12344);
    assert(R16(regs, REG_ADDRESS) == 0x0041 && R16(regs, REG_ADDRESS + 2) == 0x2344);
    {
        static const UBYTE rgb[] = { 0x11, 0x22, 0x33, 0xaa, 0xbb, 0xcc };
        mm_SetPalette(&b, 254, 3, rgb);           /* the third is past pen 255 */
        assert(R32(regs, REG_PALETTE + 4 * 254) == 0x112233);
        assert(R32(regs, REG_PALETTE + 4 * 255) == 0xaabbcc);
        assert(R16(regs, REG_PALETTE + 4 * 256) == 0);
    }
    mm_SetSwitch(&b, TRUE); assert(R16(regs, REG_ENABLE) == 1);
    mm_Shutdown(&b); assert(R16(regs, REG_ENABLE) == 0);

    /* random blits on random surfaces against the CPU */
    for (n = 0; n < 3000; n++) {
        UWORD w, h, x, y, sx, sy;
        enum PrismResult r;
        f = fmts[rnd() % 4];
        memset(&s, 0, sizeof s);
        s.format = f;
        s.bpp = board_bpp(f);
        s.width = 16 + rnd() % 300;
        s.height = 8 + rnd() % 100;
        s.pitch = ((ULONG)s.width * s.bpp + 7 + (rnd() % 3) * 8) & ~7UL;
        s.allocation = s.pitch * s.height;
        s.offset = (rnd() % (TMPL_OFF / 2 - s.allocation)) & ~7UL;
        s.flags = PSF_VRAM;
        w = 1 + rnd() % s.width;
        h = 1 + rnd() % s.height;
        x = rnd() % (s.width - w + 1);
        y = rnd() % (s.height - h + 1);
        switch (rnd() % 4) {
        case 0: {
            ULONG c = colour(s.bpp);
            r = board_fill(&b, &s, x, y, w, h, c);
            if (s.bpp == 3) { assert(r == PR_DECLINED); break; }
            assert(r == PR_DONE);
            blitter();
            ref_fill(&s, x, y, w, h, c);
            same("fill", n);
            break;
        }
        case 1:                                    /* within one bitmap: overlaps */
            sx = rnd() % (s.width - w + 1);
            sy = rnd() % (s.height - h + 1);
            r = board_copy(&b, &s, &s, sx, sy, x, y, w, h);
            assert(r == PR_DONE);
            blitter();
            ref_copy(&s, &s, sx, sy, x, y, w, h);
            same("copy", n);
            break;
        case 2:                                    /* to a bitmap of its own */
            d = s;
            d.offset = TMPL_OFF / 2 + ((rnd() % (TMPL_OFF / 2 - d.allocation)) & ~7UL);
            sx = rnd() % (s.width - w + 1);
            sy = rnd() % (s.height - h + 1);
            r = board_copy(&b, &s, &d, sx, sy, x, y, w, h);
            assert(r == PR_DONE);
            blitter();
            ref_copy(&s, &d, sx, sy, x, y, w, h);
            same("copy between", n);
            break;
        case 3: {
            ULONG mod, fg = colour(s.bpp), bg = colour(s.bpp);
            BOOL tr = rnd() & 1;
            if (w > 300) w = 300;
            if (h > 40) h = 40;
            mod = (w + 7) / 8 + rnd() % 4;
            for (i = 0; i < mod * h; i++)
                tmpl[i] = rnd();
            r = board_expand(&b, &s, x, y, w, h, tmpl, mod, fg, bg, tr);
            if (s.bpp == 3) { assert(r == PR_DECLINED); break; }
            assert(r == PR_DONE);
            blitter();
            ref_expand(&s, x, y, w, h, tmpl, mod, fg, bg, tr);
            same(tr ? "text (transparent)" : "text", n);
            break;
        }
        }
    }

    /* declines: overlapping bitmaps of different geometry, too wide, pitch */
    memset(&s, 0, sizeof s);
    s.format = PF_RGBA32; s.bpp = 4; s.width = 2100; s.height = 4;
    s.pitch = 8400; s.allocation = 8400 * 4; s.flags = PSF_VRAM;
    assert(board_fill(&b, &s, 0, 0, 2048, 1, 0) == PR_DECLINED);    /* 8192 bytes */
    assert(board_fill(&b, &s, 0, 0, 2047, 1, 0) == PR_DONE); blitter();
    d = s; d.offset = 8400; d.pitch = 8404; d.width = 2101; d.allocation = 8404 * 4;
    assert(board_copy(&b, &s, &d, 0, 0, 0, 0, 10, 2) == PR_DECLINED);
    s.width = 9000; s.pitch = 36000; s.allocation = 36000 * 4;
    assert(board_fill(&b, &s, 0, 0, 10, 1, 0) == PR_DECLINED);      /* stride > 32767 */
    s.offset = TMPL_OFF - 16; s.width = 4; s.height = 1; s.pitch = 16; s.allocation = 32;
    assert(board_fill(&b, &s, 0, 0, 4, 1, 0) == PR_DECLINED);       /* past VRAM */

    puts("Megamiga modes, registers and 3000 blits against the CPU passed");
    return 0;
}
