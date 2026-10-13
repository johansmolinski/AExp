/*
 * ShareInfo - the state of the Megamiga shared folder (SDCard:), for diagnostics
 *
 * Prints the status the firmware publishes for MegamigaFS at $DD4FF8 (volume present,
 * generation, protocol version) and its event counters at $DD4FEC: card-detect changes
 * (raw, so a glitch of the signal counts, too), card removals and insertions (after the
 * debounce), card changes the core noticed (SD_CHANGED), SD slot switches and mounts.
 * Every removal, insertion, card change or slot switch is a disk change for the Amiga.
 *
 * Only reads the shared memory; runs on every Kickstart.
 *
 * Megamiga, October 2026. Licensed under the GPL v3.
 */

#include <exec/types.h>
#include <dos/dos.h>

#include <proto/exec.h>
#include <proto/dos.h>

static volatile UWORD *const evc = (volatile UWORD *)0xDD4FEC;     /* 6 counters */
static volatile UWORD *const status = (volatile UWORD *)0xDD4FF8;  /* 'MS', state, version */

static const char *const ev_name[6] = {
    "Card-detect changes (raw)  ",
    "Cards removed              ",
    "Cards inserted             ",
    "Card changes (SD_CHANGED)  ",
    "SD slot switches           ",
    "Mounts                     "
};

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

int main(void)
{
    UWORD st, w[6];
    int i;

    out = Output();
    if (status[0] != 0x4D53)
    {
        put("No Megamiga shared folder here (firmware status missing).\n");
        return RETURN_WARN;
    }
    st = status[1];
    for (i = 0; i < 6; i++)
        w[i] = evc[i];
    put("Megamiga shared folder, protocol ");
    put_num(status[2]);
    put("\nVolume                     ");
    put(st & 0x8000 ? "present" : "not present");
    put("\nGeneration                 ");
    put_num(st & 0x7FFF);
    put("\n");
    for (i = 0; i < 6; i++)
    {
        put(ev_name[i]);
        put_num(w[i]);
        put("\n");
    }
    return RETURN_OK;
}
