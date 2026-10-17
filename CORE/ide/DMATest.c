/*
 * DMATest - write a file with a known pattern, read it back, check every byte
 *
 *   DMATest FILE/A,SIZE/N,BLOCK/N,KEEP/S
 *     FILE   the test file (on the disk to test, e.g. DH0:dmatest)
 *     SIZE   its size in MB (default 8)
 *     BLOCK  the size of one Write()/Read() in KB (default 128)
 *     KEEP   do not delete the file at the end
 *
 * Four rounds, each with its own buffer: Fast RAM long-aligned (the IDE DMA of the Megamiga
 * board takes those), Fast RAM at +2 and at +1 (not long-aligned: lide.device copies with
 * the CPU) and Chip RAM (refused by the DMA: the CPU again). Each round writes the whole file
 * and reads it back, with MB/s for both directions. The buffer is filled by the CPU just
 * before each Write() (so with a copyback cache the data sits in the cache: the driver must
 * push it out before the DMA reads memory) and filled with garbage just before each Read()
 * (the cache then holds stale lines: the driver must drop them after the DMA wrote memory).
 * A wrong byte stops the round and prints its file offset, what was read and what was
 * expected. CTRL-C stops.
 *
 * Megamiga, October 2026. Licensed under the GPL v3.
 */

#include <exec/types.h>
#include <exec/memory.h>
#include <dos/dos.h>
#include <dos/rdargs.h>

#include <proto/exec.h>
#include <proto/dos.h>

static BPTR out;

static void put(const char *s)
{
    LONG n = 0;
    while (s[n])
        n++;
    Write(out, (APTR)s, n);
}

static void put_num(ULONG v)
{
    char buf[12];
    int i = sizeof(buf) - 1;
    buf[i] = 0;
    do
    {
        buf[--i] = '0' + v % 10;
        v /= 10;
    } while (v);
    put(buf + i);
}

static void put_hex(ULONG v, int digits)
{
    char buf[9];
    int i;
    for (i = digits - 1; i >= 0; i--)
    {
        buf[i] = "0123456789ABCDEF"[v & 15];
        v >>= 4;
    }
    buf[digits] = 0;
    put(buf);
}

/* bytes per second as "12.34 MB/s" (1 MB = 1048576 bytes) */
static void put_rate(ULONG bytes, ULONG ticks)
{
    ULONG r;
    if (ticks == 0)
        ticks = 1;
    /* hundredths of MB/s = bytes * 50 * 100 / ticks / 1048576, without overflowing */
    r = (bytes / 1024) * 50 / ticks;            /* KB/s */
    r = r * 100 / 1024;                         /* hundredths of MB/s */
    put_num(r / 100);
    put(".");
    if (r % 100 < 10)
        put("0");
    put_num(r % 100);
    put(" MB/s");
}

/* the pattern: the long at file offset 4n is n * 0x9E3779B1 + seed, big-endian */
static UBYTE pbyte(ULONG off, ULONG seed)
{
    ULONG l = (off >> 2) * 0x9E3779B1UL + seed;
    return (UBYTE)(l >> (24 - 8 * (off & 3)));
}

static void fill(UBYTE *d, ULONG off, ULONG n, ULONG seed)
{
    ULONG i = 0;
    /* whole longs while the file offset is long-aligned (d itself may be odd) */
    while (i < n && ((off + i) & 3))
    {
        d[i] = pbyte(off + i, seed);
        i++;
    }
    while (i + 4 <= n)
    {
        ULONG l = ((off + i) >> 2) * 0x9E3779B1UL + seed;
        d[i] = (UBYTE)(l >> 24);
        d[i + 1] = (UBYTE)(l >> 16);
        d[i + 2] = (UBYTE)(l >> 8);
        d[i + 3] = (UBYTE)l;
        i += 4;
    }
    while (i < n)
    {
        d[i] = pbyte(off + i, seed);
        i++;
    }
}

/* the first wrong byte of d (file offset off), or -1 */
static LONG check(const UBYTE *d, ULONG off, ULONG n, ULONG seed)
{
    ULONG i = 0;
    while (i < n && ((off + i) & 3))
    {
        if (d[i] != pbyte(off + i, seed))
            return (LONG)i;
        i++;
    }
    while (i + 4 <= n)
    {
        ULONG l = ((off + i) >> 2) * 0x9E3779B1UL + seed;
        if (d[i] != (UBYTE)(l >> 24) || d[i + 1] != (UBYTE)(l >> 16) ||
            d[i + 2] != (UBYTE)(l >> 8) || d[i + 3] != (UBYTE)l)
        {
            while (d[i] == pbyte(off + i, seed))
                i++;
            return (LONG)i;
        }
        i += 4;
    }
    while (i < n)
    {
        if (d[i] != pbyte(off + i, seed))
            return (LONG)i;
        i++;
    }
    return -1;
}

static ULONG ticks_since(struct DateStamp *t0)
{
    struct DateStamp t1;
    DateStamp(&t1);
    return (ULONG)(t1.ds_Days - t0->ds_Days) * 24 * 60 * 50 * 60 +
           (ULONG)(t1.ds_Minute - t0->ds_Minute) * 60 * 50 +
           (ULONG)(t1.ds_Tick - t0->ds_Tick);
}

static BOOL broken(void)
{
    if (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
    {
        put("*** Break\n");
        return TRUE;
    }
    return FALSE;
}

/* one round; returns 0 = OK, 1 = wrong data, 2 = I/O error or break */
static int do_round(const char *name, const char *file, ULONG size, ULONG block,
                 ULONG memtype, ULONG skew, ULONG seed)
{
    UBYTE *mem, *buf;
    BPTR fh;
    ULONG off, n, tw, tr;
    struct DateStamp t0;
    int res = 0;

    mem = AllocMem(block + 8, memtype);
    if (!mem)
    {
        put(name);
        put("no memory of that kind, skipped\n");
        return 0;
    }
    buf = mem + skew;
    put(name);

    /* write: the CPU fills each block right before Write() */
    fh = Open((STRPTR)file, MODE_NEWFILE);
    if (!fh)
    {
        put("cannot create the file\n");
        FreeMem(mem, block + 8);
        return 2;
    }
    tw = 0;
    for (off = 0; off < size; off += n)
    {
        n = size - off < block ? size - off : block;
        fill(buf, off, n, seed);
        DateStamp(&t0);
        if (Write(fh, buf, n) != (LONG)n)
        {
            put("write error ");
            put_num(IoErr());
            put("\n");
            res = 2;
            break;
        }
        tw += ticks_since(&t0);
        if (broken())
        {
            res = 2;
            break;
        }
    }
    Close(fh);
    if (res)
    {
        FreeMem(mem, block + 8);
        return res;
    }
    put("write ");
    put_rate(size, tw);

    /* read: garbage in the buffer (and its cache lines) right before Read() */
    fh = Open((STRPTR)file, MODE_OLDFILE);
    if (!fh)
    {
        put(", cannot open the file again\n");
        FreeMem(mem, block + 8);
        return 2;
    }
    tr = 0;
    for (off = 0; off < size; off += n)
    {
        LONG bad;
        ULONG i;
        n = size - off < block ? size - off : block;
        for (i = 0; i < n; i++)
            buf[i] = 0xA5;
        DateStamp(&t0);
        if (Read(fh, buf, n) != (LONG)n)
        {
            put(", read error ");
            put_num(IoErr());
            put("\n");
            res = 2;
            break;
        }
        tr += ticks_since(&t0);
        bad = check(buf, off, n, seed);
        if (bad >= 0)
        {
            put(", read ");
            put_rate(off + n, tr);
            put("\n    WRONG DATA at file offset $");
            put_hex(off + bad, 8);
            put(": read");
            for (i = 0; i < 8 && bad + i < n; i++)
            {
                put(" ");
                put_hex(buf[bad + i], 2);
            }
            put(", expected");
            for (i = 0; i < 8 && bad + i < n; i++)
            {
                put(" ");
                put_hex(pbyte(off + bad + i, seed), 2);
            }
            put("\n");
            res = 1;
            break;
        }
        if (broken())
        {
            res = 2;
            break;
        }
    }
    Close(fh);
    if (res == 0)
    {
        put(", read ");
        put_rate(size, tr);
        put(", OK\n");
    }
    FreeMem(mem, block + 8);
    return res;
}

int main(void)
{
    static const char tmpl[] = "FILE/A,SIZE/N,BLOCK/N,KEEP/S";
    LONG args[4] = { 0, 0, 0, 0 };
    struct RDArgs *rda;
    ULONG size, block;
    int fails = 0, r;

    out = Output();
    if (((struct Library *)DOSBase)->lib_Version < 36)
    {
        put("DMATest needs Kickstart 2.0 or newer\n");
        return RETURN_FAIL;
    }
    rda = ReadArgs((STRPTR)tmpl, args, NULL);
    if (!rda)
    {
        PrintFault(IoErr(), (STRPTR)"DMATest");
        return RETURN_FAIL;
    }
    size = args[1] ? *(ULONG *)args[1] : 8;
    block = args[2] ? *(ULONG *)args[2] : 128;
    if (size < 1 || size > 1024 || block < 1 || block > 4096)
    {
        put("SIZE 1..1024 (MB), BLOCK 1..4096 (KB)\n");
        FreeArgs(rda);
        return RETURN_FAIL;
    }
    size <<= 20;
    block <<= 10;
    put("DMATest: ");
    put_num(size >> 20);
    put(" MB in blocks of ");
    put_num(block >> 10);
    put(" KB, file ");
    put((const char *)args[0]);
    put("\n");

    r = do_round("  Fast RAM, long-aligned  ", (const char *)args[0], size, block, MEMF_FAST, 0, 0x1234567);
    if (r == 1) fails++;
    if (r < 2)
    {
        r = do_round("  Fast RAM, at +2         ", (const char *)args[0], size, block, MEMF_FAST, 2, 0x2345678);
        if (r == 1) fails++;
    }
    if (r < 2)
    {
        r = do_round("  Fast RAM, at +1 (odd)   ", (const char *)args[0], size, block, MEMF_FAST, 1, 0x3456789);
        if (r == 1) fails++;
    }
    if (r < 2)
    {
        r = do_round("  Chip RAM, long-aligned  ", (const char *)args[0], size, block, MEMF_CHIP, 0, 0x456789A);
        if (r == 1) fails++;
    }
    if (!args[3])
        DeleteFile((STRPTR)args[0]);
    FreeArgs(rda);
    if (r == 2)
        return RETURN_FAIL;
    if (fails)
    {
        put("FAILED: wrong data in ");
        put_num(fails);
        put(fails == 1 ? " round\n" : " rounds\n");
        return RETURN_ERROR;
    }
    put("All rounds OK\n");
    return RETURN_OK;
}
