/*
 * CacheTime - how long the cache calls around one IDE DMA take
 *
 *   CacheTime SIZE/N,LOOPS/N
 *     SIZE   the buffer in KB (default 128, what DMATest moves per Read()/Write())
 *     LOOPS  repetitions per measurement (default 64)
 *
 * lide.device (Megamiga DMA) calls CachePreDMA before and CachePostDMA after every DMA. On a
 * 68040 with copyback these may walk the buffer line by line; this prints the time of each
 * variant for one buffer of SIZE KB in Fast RAM, with the buffer's lines dirty in the data
 * cache (the CPU wrote it just before, like DMATest) and clean. CacheClearU (push and
 * invalidate everything) is the cheap alternative.
 *
 * Megamiga, October 2026. Licensed under the GPL v3.
 */

#include <exec/types.h>
#include <exec/memory.h>
#include <exec/execbase.h>
#include <dos/dos.h>
#include <devices/timer.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/timer.h>

struct Device *TimerBase;
static BPTR out;
static ULONG efreq;

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

/* E clock ticks between two readings */
static ULONG eticks(struct EClockVal *a, struct EClockVal *b)
{
    return b->ev_lo - a->ev_lo;
}

/* the mean time of one call in microseconds, from E clock ticks for loops calls */
static void put_us(ULONG ticks, ULONG loops)
{
    /* ticks * 1000000 / efreq / loops, in tenths (no floating point; 32 bits hold
       ticks * 10000 up to 429496 ticks = 0.6 s at the PAL E clock) */
    ULONG t;
    while (ticks > 429496)
    {
        ticks >>= 1;
        loops >>= 1;
        if (!loops)
            loops = 1;
    }
    t = ticks * 10000 / (efreq / 1000) / loops;
    put_num(t / 10);
    put(".");
    put_num(t % 10);
    put(" us");
}

static void dirty(ULONG *b, ULONG longs, ULONG v)
{
    ULONG i;
    for (i = 0; i < longs; i++)
        b[i] = v + i;
}

/* what: 0 = CachePreDMA+CachePostDMA (the board writes memory), 1 = the same with
   DMA_ReadFromRAM (the board reads memory), 2 = CacheClearU twice */
static void measure(const char *name, ULONG *buf, ULONG size, ULONG loops, int what, int dirt)
{
    struct EClockVal t0, t1;
    ULONG total = 0, i, len = 0;
    APTR a = 0;

    for (i = 0; i < loops; i++)
    {
        ULONG flags = what == 1 ? DMA_ReadFromRAM : 0;
        if (dirt)
            dirty(buf, size >> 2, i);
        ReadEClock(&t0);
        if (what == 2)
        {
            CacheClearU();
            CacheClearU();
        }
        else
        {
            len = size;
            a = CachePreDMA(buf, &len, flags);
            CachePostDMA(buf, &len, flags);
        }
        ReadEClock(&t1);
        total += eticks(&t0, &t1);
    }
    put(name);
    put(dirt ? " (dirty): " : " (clean): ");
    put_us(total, loops);
    if (what != 2)
    {
        put("  length ");
        put_num(len);
        if (a != (APTR)buf)
        {
            put("  address $");
            put_hex((ULONG)a, 8);
        }
    }
    put("\n");
}

int main(void)
{
    static const char tmpl[] = "SIZE/N,LOOPS/N";
    LONG args[2] = { 0, 0 };
    struct RDArgs *rda;
    struct timerequest tr;
    ULONG size, loops;
    ULONG *buf;
    struct EClockVal t0;
    UWORD attn = SysBase->AttnFlags;

    out = Output();
    if (SysBase->LibNode.lib_Version < 37)
    {
        put("CacheTime needs Kickstart 2.04 or newer\n");
        return RETURN_FAIL;
    }
    rda = ReadArgs((STRPTR)tmpl, args, NULL);
    if (!rda)
    {
        PrintFault(IoErr(), (STRPTR)"CacheTime");
        return RETURN_FAIL;
    }
    size = (args[0] ? *(ULONG *)args[0] : 128) << 10;
    loops = args[1] ? *(ULONG *)args[1] : 64;
    FreeArgs(rda);
    if (loops < 1)
        loops = 1;
    if (OpenDevice((STRPTR)TIMERNAME, UNIT_ECLOCK, (struct IORequest *)&tr, 0))
    {
        put("cannot open timer.device\n");
        return RETURN_FAIL;
    }
    TimerBase = tr.tr_node.io_Device;
    efreq = ReadEClock(&t0);
    buf = AllocMem(size, MEMF_FAST);
    if (!buf)
    {
        put("no Fast RAM\n");
        CloseDevice((struct IORequest *)&tr);
        return RETURN_FAIL;
    }

    put("CacheTime: ");
    put_num(size >> 10);
    put(" KB at $");
    put_hex((ULONG)buf, 8);
    put(", ");
    put_num(loops);
    put(" loops, CPU ");
    put((attn & AFF_68060) ? "68060" : (attn & AFF_68040) ? "68040" : (attn & AFF_68030) ? "68030" :
        (attn & AFF_68020) ? "68020" : "68000/010");
    put(", E clock ");
    put_num(efreq);
    put(" Hz, CACR bits $");
    put_hex(CacheControl(0, 0), 8);
    put("\n");

    measure("  CachePreDMA+CachePostDMA, board writes", buf, size, loops, 0, 1);
    measure("  CachePreDMA+CachePostDMA, board writes", buf, size, loops, 0, 0);
    measure("  CachePreDMA+CachePostDMA, board reads ", buf, size, loops, 1, 1);
    measure("  CachePreDMA+CachePostDMA, board reads ", buf, size, loops, 1, 0);
    measure("  CacheClearU x2                        ", buf, size, loops, 2, 1);
    measure("  CacheClearU x2                        ", buf, size, loops, 2, 0);

    FreeMem(buf, size);
    CloseDevice((struct IORequest *)&tr);
    return RETURN_OK;
}
