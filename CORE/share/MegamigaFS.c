/*
 * MegamigaFS: the /amiga folder of the MEGA65's SD card as an AmigaOS volume (Megamiga 0.6.1)
 *
 * A file system handler without a disk: it turns every DOS packet into a request in the
 * shared memory at $DD4000 and waits until the Megamiga firmware (SHARE_STEP in
 * m2m-rom.asm) has answered it from the SD card. The protocol is the one of MiSTer's
 * shared folder, so this is MiSTerFileSystem by Alexey Melnikov (Minimig-AGA_MiSTer,
 * extra/MiSTerFileSystem.c, 2020), itself a version of a314fs by Niklas Ekstrom (CC0), with
 * these changes for Megamiga:
 *
 *  - The volume is removable. The firmware publishes its state at $DD4FF8: 'MS', then
 *    bit 15 = volume present and bits 14..0 = a generation that changes whenever the card
 *    goes away or comes back. The handler checks it before every packet and once a second
 *    (timer.device): a new generation is a disk change - the old volume is retired (it
 *    stays in the DOS list, without a handler, while locks on it exist, like an ejected
 *    floppy), a new volume appears, and input.device announces both to Workbench. Packets
 *    on a lock of a retired volume fail with ERROR_DEVICE_NOT_MOUNTED.
 *  - Without the firmware ('MS' missing: another core or an older Megamiga) the handler
 *    never writes to $DD4000.
 *  - The volume is write-protected for now (the firmware refuses every write).
 *  - Fixes: a failed READ or WRITE replies to its packet; ACTION_FH_FROM_LOCK,
 *    ACTION_IS_FILESYSTEM, ACTION_CURRENT_VOLUME, ACTION_FLUSH and ACTION_INHIBIT.
 *  - Read and write (firmware protocol version 2): the volume is writable, the handler
 *    puts the current DateStamp at SHARE_TIME_ADDR before every request (the firmware
 *    dates new and changed files with it) and knows ACTION_SET_DATE and
 *    ACTION_SET_FILE_SIZE. With protocol version 1 (Megamiga 0.6.0 firmware) the volume
 *    stays write-protected.
 *  - Kickstart 2.0 and later: the volume enters and leaves the DOS list under
 *    LockDosList (AddDosEntry/RemDosEntry), not only under Forbid - dos.library
 *    and Workbench walk that list holding its semaphore, possibly across a Wait.
 *
 * Built as a BCPL-style module (bcpl_start.asm, bcpl_end.asm and the length patch in
 * build.sh, the a314fs way), so that a mountlist entry starts it on every Kickstart.
 *
 * Megamiga changes (C) 2026, licensed under GPL v3 like the rest of Megamiga.
 */

#include <exec/types.h>
#include <exec/ports.h>
#include <exec/nodes.h>
#include <exec/libraries.h>
#include <exec/memory.h>
#include <exec/io.h>
#include <devices/timer.h>
#include <devices/input.h>
#include <devices/inputevent.h>

#include <libraries/dos.h>
#include <libraries/dosextens.h>
#include <libraries/filehandler.h>

#include <proto/exec.h>
#include <proto/dos.h>

#include "share_msg.h"

#define UMKBADDR(x) (((ULONG)x) >> 2)

#define ID_MEGAMIGA     0x4D534400      /* 'MSD\0' */
#define BUFFER_SIZE     4096
#define MAX_STALE       8

#ifndef ACTION_EXAMINE_FH
#define ACTION_EXAMINE_FH 1034
#endif
#ifndef ACTION_SAME_LOCK
#define ACTION_SAME_LOCK 40
#endif
#ifndef ACTION_FH_FROM_LOCK
#define ACTION_FH_FROM_LOCK 1026
#endif
#ifndef ACTION_IS_FILESYSTEM
#define ACTION_IS_FILESYSTEM 1027
#endif
#ifndef ACTION_SET_DATE
#define ACTION_SET_DATE 34
#endif
#ifndef ACTION_SET_FILE_SIZE
#define ACTION_SET_FILE_SIZE 1022
#endif

struct ExecBase *SysBase;
struct DosLibrary *DOSBase;
struct MsgPort *mp;

/* the shared memory */
volatile unsigned short *request_flg = (volatile unsigned short *)0xDD4000;  /* 4 bytes */
char *request_buffer                 = (char *)0xDD4004;                     /* 512 bytes */
volatile unsigned short *status      = (volatile unsigned short *)0xDD4FF8;  /* 'MS', state */
char *data_buffer                    = (char *)0xDD5000;                     /* 4 KB */

#define STATUS_MAGIC    0x4D53
#define STATUS_UP       0x8000

static const char volume_name[] = "SDCard";

struct DeviceList *cur_vol;             /* the volume, NULL while there is none */
unsigned short cur_gen;
struct DeviceList *stale[MAX_STALE];    /* retired volumes that still have locks */

struct MsgPort *timer_port;
struct timerequest *timer_req;
int timer_ok;
struct MsgPort *input_port;
struct IOStdReq *input_req;
int input_ok;

/* ---------------------------------------------------------------------------- helpers */

static void copy_mem(void *dst, const void *src, ULONG len)
{
    UBYTE *d = (UBYTE *)dst;
    const UBYTE *s = (const UBYTE *)src;
    while (len--)
        *d++ = *s++;
}

static void clear_mem(void *dst, ULONG len)
{
    UBYTE *d = (UBYTE *)dst;
    while (len--)
        *d++ = 0;
}

static struct MsgPort *create_port(void)
{
    BYTE sig = AllocSignal(-1);
    struct MsgPort *port;
    if (sig == -1)
        return NULL;
    port = (struct MsgPort *)AllocMem(sizeof(struct MsgPort), MEMF_PUBLIC | MEMF_CLEAR);
    if (!port)
    {
        FreeSignal(sig);
        return NULL;
    }
    port->mp_Node.ln_Type = NT_MSGPORT;
    port->mp_Flags = PA_SIGNAL;
    port->mp_SigBit = sig;
    port->mp_SigTask = FindTask(NULL);
    port->mp_MsgList.lh_Head = (struct Node *)&port->mp_MsgList.lh_Tail;
    port->mp_MsgList.lh_Tail = NULL;
    port->mp_MsgList.lh_TailPred = (struct Node *)&port->mp_MsgList.lh_Head;
    return port;
}

static char *dos_alloc(ULONG len)
{
    LONG *p = (LONG *)AllocMem(len + 4, MEMF_PUBLIC | MEMF_CLEAR);
    if (!p)
        return NULL;
    *p++ = len;
    return (char *)p;
}

static void dos_free(char *p)
{
    LONG *lp = (LONG *)p;
    LONG len = *--lp;
    FreeMem((char *)lp, len + 4);
}

static void reply_packet(struct DosPacket *dp)
{
    struct MsgPort *reply_port = dp->dp_Port;
    dp->dp_Port = mp;
    PutMsg(reply_port, dp->dp_Link);
}

static int firmware_present(void)
{
    return status[0] == STATUS_MAGIC;
}

/* protocol version 2: the firmware writes */
static int firmware_writes(void)
{
    return firmware_present() && status[2] >= 2;
}

/* write the request, then wait for the firmware (the request flag protocol of MiSTer) */
static void write_req_and_wait_for_res(int len)
{
    unsigned short n;
    struct DateStamp ds;
    DateStamp(&ds);
    copy_mem((void *)SHARE_TIME_ADDR, &ds, sizeof(ds));
    *(int *)request_buffer = len;
    request_flg[1] = 0xA55A;
    n = request_flg[0] + 1;
    n = ((n + 77) << 8) | (n & 0xFF);
    request_flg[0] = n;
    while (n != request_flg[1])
        ;
}

/* ------------------------------------------------------------------- volumes */

static void send_disk_event(UBYTE class)
{
    struct InputEvent ie;
    if (!input_ok)
        return;
    clear_mem(&ie, sizeof(ie));
    ie.ie_Class = class;
    input_req->io_Command = IND_WRITEEVENT;
    input_req->io_Data = (APTR)&ie;
    input_req->io_Length = sizeof(struct InputEvent);
    DoIO((struct IORequest *)input_req);
}

static struct DeviceList *create_volume(void)
{
    struct DeviceList *vol;
    struct RootNode *root;
    struct DosInfo *info;
    char *name;
    int len = sizeof(volume_name) - 1;

    vol = (struct DeviceList *)dos_alloc(sizeof(struct DeviceList));
    name = dos_alloc(len + 2);
    if (!vol || !name)
    {
        if (vol)
            dos_free((char *)vol);
        if (name)
            dos_free(name);
        return NULL;
    }
    name[0] = len;
    copy_mem(name + 1, volume_name, len);
    vol->dl_Name = (BSTR)UMKBADDR(name);
    vol->dl_Type = DLT_VOLUME;
    vol->dl_Task = mp;
    vol->dl_DiskType = ID_MEGAMIGA;
    DateStamp(&vol->dl_VolumeDate);

    if (DOSBase->dl_lib.lib_Version >= 36)
    {
        LONG ok;
        LockDosList(LDF_VOLUMES | LDF_WRITE);
        ok = AddDosEntry((struct DosList *)vol);
        UnLockDosList(LDF_VOLUMES | LDF_WRITE);
        if (!ok)
        {
            dos_free(name);
            dos_free((char *)vol);
            return NULL;
        }
        return vol;
    }
    root = (struct RootNode *)DOSBase->dl_Root;
    info = (struct DosInfo *)BADDR(root->rn_Info);
    Forbid();
    vol->dl_Next = info->di_DevInfo;
    info->di_DevInfo = UMKBADDR(vol);
    Permit();
    return vol;
}

static void remove_volume(struct DeviceList *vol)
{
    struct RootNode *root = (struct RootNode *)DOSBase->dl_Root;
    struct DosInfo *info = (struct DosInfo *)BADDR(root->rn_Info);
    BPTR b = UMKBADDR(vol);

    if (DOSBase->dl_lib.lib_Version >= 36)
    {
        LockDosList(LDF_VOLUMES | LDF_WRITE);
        RemDosEntry((struct DosList *)vol);
        UnLockDosList(LDF_VOLUMES | LDF_WRITE);
        dos_free((char *)BADDR(vol->dl_Name));
        dos_free((char *)vol);
        return;
    }
    Forbid();
    if (info->di_DevInfo == b)
        info->di_DevInfo = vol->dl_Next;
    else
    {
        struct DeviceList *prev = (struct DeviceList *)BADDR(info->di_DevInfo);
        while (prev && prev->dl_Next != b)
            prev = (struct DeviceList *)BADDR(prev->dl_Next);
        if (prev)
            prev->dl_Next = vol->dl_Next;
    }
    Permit();
    dos_free((char *)BADDR(vol->dl_Name));
    dos_free((char *)vol);
}

/* the volume goes away: removed now, or kept without a handler while it has locks */
static void retire_volume(struct DeviceList *vol)
{
    int i;
    if (vol->dl_Lock == 0)
    {
        remove_volume(vol);
        return;
    }
    vol->dl_Task = NULL;
    for (i = 0; i < MAX_STALE; i++)
    {
        if (!stale[i])
        {
            stale[i] = vol;
            return;
        }
    }
    /* no room to track it: it stays in the DOS list for good */
}

/* follow the firmware: a new generation is a disk change */
static void check_media(void)
{
    unsigned short st = 0;
    int up = 0;

    if (firmware_present())
    {
        st = status[1];
        up = (st & STATUS_UP) != 0;
    }

    if (cur_vol && (!up || (st & 0x7FFF) != cur_gen))
    {
        retire_volume(cur_vol);
        cur_vol = NULL;
        send_disk_event(IECLASS_DISKREMOVED);
    }
    if (up && !cur_vol)
    {
        cur_vol = create_volume();
        if (cur_vol)
        {
            cur_gen = st & 0x7FFF;
            send_disk_event(IECLASS_DISKINSERTED);
        }
    }
}

/* ------------------------------------------------------------------- locks */

static struct FileLock *create_and_add_file_lock(long key, long mode)
{
    struct FileLock *lock = (struct FileLock *)dos_alloc(sizeof(struct FileLock));
    if (!lock)
        return NULL;
    lock->fl_Key = key;
    lock->fl_Access = mode;
    lock->fl_Task = mp;
    lock->fl_Volume = UMKBADDR(cur_vol);

    Forbid();
    lock->fl_Link = cur_vol->dl_Lock;
    cur_vol->dl_Lock = UMKBADDR(lock);
    Permit();
    return lock;
}

/* a lock may be used: it belongs to the current volume (NULL is its root) */
static int lock_ok(struct DosPacket *dp, struct FileLock *lock)
{
    if (!cur_vol)
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = ERROR_NO_DISK;
        return 0;
    }
    if (lock && lock->fl_Volume != UMKBADDR(cur_vol))
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = ERROR_DEVICE_NOT_MOUNTED;
        return 0;
    }
    return 1;
}

/* a lock of the current volume: its key, 0 for the root */
static long lock_key(struct FileLock *lock)
{
    return lock == NULL ? 0 : lock->fl_Key;
}

static void unlink_lock(struct FileLock *lock, BPTR b)
{
    struct DeviceList *vol = (struct DeviceList *)BADDR(lock->fl_Volume);
    int i;

    Forbid();
    if (vol->dl_Lock == b)
        vol->dl_Lock = lock->fl_Link;
    else
    {
        struct FileLock *prev = (struct FileLock *)BADDR(vol->dl_Lock);
        while (prev && prev->fl_Link != b)
            prev = (struct FileLock *)BADDR(prev->fl_Link);
        if (prev)
            prev->fl_Link = lock->fl_Link;
    }
    Permit();

    /* the last lock of a retired volume: the volume goes, too */
    if (vol != cur_vol && vol->dl_Lock == 0)
    {
        for (i = 0; i < MAX_STALE; i++)
        {
            if (stale[i] == vol)
            {
                stale[i] = NULL;
                remove_volume(vol);
                break;
            }
        }
    }
}

/* ------------------------------------------------------------------- packets */

static void action_locate_object(struct DosPacket *dp)
{
    struct FileLock *parent = (struct FileLock *)BADDR(dp->dp_Arg1);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg2);
    long mode = dp->dp_Arg3;
    struct LocateObjectRequest *req = (struct LocateObjectRequest *)request_buffer;
    struct LocateObjectResponse *res = (struct LocateObjectResponse *)request_buffer;
    int nlen = *name;

    if (!lock_ok(dp, parent))
    {
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->key = lock_key(parent);
    req->mode = mode;
    copy_mem(req->name, name, nlen + 1);
    write_req_and_wait_for_res(sizeof(struct LocateObjectRequest) + nlen);

    if (!res->success)
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = res->error_code;
    }
    else
    {
        struct FileLock *lock = create_and_add_file_lock(res->key, mode);
        dp->dp_Res1 = UMKBADDR(lock);
        dp->dp_Res2 = lock ? 0 : ERROR_NO_FREE_STORE;
    }
    reply_packet(dp);
}

static void action_free_lock(struct DosPacket *dp)
{
    BPTR b = dp->dp_Arg1;
    struct FileLock *lock = (struct FileLock *)BADDR(b);

    if (lock != NULL)
    {
        if (cur_vol && lock->fl_Volume == UMKBADDR(cur_vol))
        {
            struct FreeLockRequest *req = (struct FreeLockRequest *)request_buffer;
            req->type = dp->dp_Type;
            req->key = lock->fl_Key;
            write_req_and_wait_for_res(sizeof(struct FreeLockRequest));
        }
        unlink_lock(lock, b);
        dos_free((char *)lock);
    }
    dp->dp_Res1 = DOSTRUE;
    dp->dp_Res2 = 0;
    reply_packet(dp);
}

/* a request that answers with a new lock: COPY_DIR and PARENT */
static void lock_from_key_request(struct DosPacket *dp, struct FileLock *lock, long mode)
{
    struct CopyDirRequest *req = (struct CopyDirRequest *)request_buffer;
    struct CopyDirResponse *res = (struct CopyDirResponse *)request_buffer;

    req->type = dp->dp_Type;
    req->key = lock_key(lock);
    write_req_and_wait_for_res(sizeof(struct CopyDirRequest));
    if (!res->success)
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = res->error_code;
    }
    else if (res->key == 0)
    {
        dp->dp_Res1 = 0;
        dp->dp_Res2 = 0;
    }
    else
    {
        struct FileLock *nl = create_and_add_file_lock(res->key, mode);
        dp->dp_Res1 = UMKBADDR(nl);
        dp->dp_Res2 = nl ? 0 : ERROR_NO_FREE_STORE;
    }
}

static void action_copy_dir(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);

    if (lock == NULL)
    {
        dp->dp_Res1 = 0;
        dp->dp_Res2 = 0;
    }
    else if (lock_ok(dp, lock))
        lock_from_key_request(dp, lock, lock->fl_Access);
    reply_packet(dp);
}

static void action_parent(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);

    if (lock == NULL)
    {
        dp->dp_Res1 = 0;            /* the root has no parent */
        dp->dp_Res2 = 0;
    }
    else if (lock_ok(dp, lock))
        lock_from_key_request(dp, lock, SHARED_LOCK);
    reply_packet(dp);
}

/* the Examine responses all have the same layout */
static void fill_fib(struct FileInfoBlock *fib, struct ExamineObjectResponse *res)
{
    int nlen = (unsigned char)(res->file_name[0]);
    if (nlen > 106)
        nlen = 106;
    copy_mem(fib->fib_FileName, res->file_name, nlen + 1);
    fib->fib_FileName[0] = nlen;
    fib->fib_FileName[nlen + 1] = 0;
    fib->fib_DiskKey = res->disk_key;
    fib->fib_DirEntryType = res->entry_type;
    fib->fib_EntryType = res->entry_type;
    fib->fib_Protection = res->protection;
    fib->fib_Size = res->size;
    fib->fib_NumBlocks = (res->size + 511) >> 9;
    fib->fib_Date.ds_Days = res->date[0];
    fib->fib_Date.ds_Minute = res->date[1];
    fib->fib_Date.ds_Tick = res->date[2];
    fib->fib_Comment[0] = 0;
}

static void examine_reply(struct DosPacket *dp, struct FileInfoBlock *fib)
{
    struct ExamineObjectResponse *res = (struct ExamineObjectResponse *)request_buffer;
    if (!res->success)
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = res->error_code;
    }
    else
    {
        fill_fib(fib, res);
        dp->dp_Res1 = DOSTRUE;
        dp->dp_Res2 = 0;
    }
    reply_packet(dp);
}

static void action_examine_object(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);
    struct FileInfoBlock *fib = (struct FileInfoBlock *)BADDR(dp->dp_Arg2);
    struct ExamineObjectRequest *req = (struct ExamineObjectRequest *)request_buffer;

    if (!lock_ok(dp, lock))
    {
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->key = lock_key(lock);
    write_req_and_wait_for_res(sizeof(struct ExamineObjectRequest));
    examine_reply(dp, fib);
}

static void action_examine_next(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);
    struct FileInfoBlock *fib = (struct FileInfoBlock *)BADDR(dp->dp_Arg2);
    struct ExamineObjectRequest *req = (struct ExamineObjectRequest *)request_buffer;   /* (ExNext: the same layout) */

    if (!lock_ok(dp, lock))
    {
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->key = lock_key(lock);
    req->disk_key = fib->fib_DiskKey;
    write_req_and_wait_for_res(sizeof(struct ExamineObjectRequest));
    examine_reply(dp, fib);
}

static void action_examine_fh(struct DosPacket *dp)
{
    struct FileInfoBlock *fib = (struct FileInfoBlock *)BADDR(dp->dp_Arg2);
    struct ExamineFhRequest *req = (struct ExamineFhRequest *)request_buffer;

    if (!lock_ok(dp, NULL))
    {
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->arg1 = dp->dp_Arg1;
    write_req_and_wait_for_res(sizeof(struct ExamineFhRequest));
    examine_reply(dp, fib);
}

/* open: FINDINPUT etc. on a lock and a name, also used by FH_FROM_LOCK (empty name) */
static int open_request(struct DosPacket *dp, long type, struct FileHandle *fh,
                        struct FileLock *lock, unsigned char *name)
{
    struct FindXxxRequest *req = (struct FindXxxRequest *)request_buffer;
    struct FindXxxResponse *res = (struct FindXxxResponse *)request_buffer;
    int nlen = name ? *name : 0;

    req->type = type;
    req->key = lock_key(lock);
    req->name[0] = nlen;
    if (nlen)
        copy_mem(req->name + 1, name + 1, nlen);
    write_req_and_wait_for_res(sizeof(struct FindXxxRequest) + nlen);
    if (!res->success)
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = res->error_code;
        return 0;
    }
    fh->fh_Arg1 = res->arg1;
    fh->fh_Type = mp;
    fh->fh_Port = DOSFALSE;         /* not interactive */
    dp->dp_Res1 = DOSTRUE;
    dp->dp_Res2 = 0;
    return 1;
}

static void action_findxxx(struct DosPacket *dp)
{
    struct FileHandle *fh = (struct FileHandle *)BADDR(dp->dp_Arg1);
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg2);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg3);

    if (lock_ok(dp, lock))
        open_request(dp, dp->dp_Type, fh, lock, name);
    reply_packet(dp);
}

static void action_fh_from_lock(struct DosPacket *dp)
{
    struct FileHandle *fh = (struct FileHandle *)BADDR(dp->dp_Arg1);
    BPTR b = dp->dp_Arg2;
    struct FileLock *lock = (struct FileLock *)BADDR(b);

    if (lock_ok(dp, lock) && open_request(dp, ACTION_FINDINPUT, fh, lock, NULL))
    {
        /* on success the lock belongs to the file handle now: it is freed here */
        struct FreeLockRequest *req = (struct FreeLockRequest *)request_buffer;
        req->type = ACTION_FREE_LOCK;
        req->key = lock->fl_Key;
        write_req_and_wait_for_res(sizeof(struct FreeLockRequest));
        unlink_lock(lock, b);
        dos_free((char *)lock);
        dp->dp_Res1 = DOSTRUE;
        dp->dp_Res2 = 0;
    }
    reply_packet(dp);
}

static void action_read(struct DosPacket *dp)
{
    ULONG arg1 = dp->dp_Arg1;
    UBYTE *dst = (UBYTE *)dp->dp_Arg2;
    LONG length = dp->dp_Arg3;
    LONG total_read = 0;

    if (!lock_ok(dp, NULL))
    {
        dp->dp_Res1 = -1;
        reply_packet(dp);
        return;
    }
    while (length > 0)
    {
        struct ReadRequest *req = (struct ReadRequest *)request_buffer;
        struct ReadResponse *res = (struct ReadResponse *)request_buffer;
        LONG to_read = length > BUFFER_SIZE ? BUFFER_SIZE : length;

        req->type = dp->dp_Type;
        req->arg1 = arg1;
        req->address = (int)data_buffer;
        req->length = to_read;
        write_req_and_wait_for_res(sizeof(struct ReadRequest));
        if (!res->success)
        {
            dp->dp_Res1 = -1;
            dp->dp_Res2 = res->error_code;
            reply_packet(dp);
            return;
        }
        if (res->actual)
        {
            copy_mem(dst, data_buffer, res->actual);
            dst += res->actual;
            total_read += res->actual;
            length -= res->actual;
        }
        if (res->actual < to_read)
            break;
    }
    dp->dp_Res1 = total_read;
    dp->dp_Res2 = 0;
    reply_packet(dp);
}

static void action_write(struct DosPacket *dp)
{
    ULONG arg1 = dp->dp_Arg1;
    UBYTE *src = (UBYTE *)dp->dp_Arg2;
    LONG length = dp->dp_Arg3;
    LONG total_written = 0;

    if (!lock_ok(dp, NULL))
    {
        dp->dp_Res1 = -1;
        reply_packet(dp);
        return;
    }
    while (length > 0)
    {
        struct WriteRequest *req = (struct WriteRequest *)request_buffer;
        struct WriteResponse *res = (struct WriteResponse *)request_buffer;
        LONG to_write = length > BUFFER_SIZE ? BUFFER_SIZE : length;

        copy_mem(data_buffer, src, to_write);
        req->type = dp->dp_Type;
        req->arg1 = arg1;
        req->address = (int)data_buffer;
        req->length = to_write;
        write_req_and_wait_for_res(sizeof(struct WriteRequest));
        if (!res->success)
        {
            dp->dp_Res1 = total_written ? total_written : -1;
            dp->dp_Res2 = res->error_code;
            reply_packet(dp);
            return;
        }
        if (res->actual)
        {
            src += res->actual;
            total_written += res->actual;
            length -= res->actual;
        }
        if (res->actual < to_write)
            break;
    }
    dp->dp_Res1 = total_written;
    dp->dp_Res2 = 0;
    reply_packet(dp);
}

static void action_seek(struct DosPacket *dp)
{
    struct SeekRequest *req = (struct SeekRequest *)request_buffer;
    struct SeekResponse *res = (struct SeekResponse *)request_buffer;

    if (!lock_ok(dp, NULL))
    {
        dp->dp_Res1 = -1;
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->arg1 = dp->dp_Arg1;
    req->new_pos = dp->dp_Arg2;
    req->mode = dp->dp_Arg3;
    write_req_and_wait_for_res(sizeof(struct SeekRequest));
    if (!res->success)
    {
        dp->dp_Res1 = -1;
        dp->dp_Res2 = res->error_code;
    }
    else
    {
        dp->dp_Res1 = res->old_pos;
        dp->dp_Res2 = 0;
    }
    reply_packet(dp);
}

static void action_end(struct DosPacket *dp)
{
    if (cur_vol)
    {
        struct EndRequest *req = (struct EndRequest *)request_buffer;
        req->type = dp->dp_Type;
        req->arg1 = dp->dp_Arg1;
        write_req_and_wait_for_res(sizeof(struct EndRequest));
    }
    dp->dp_Res1 = DOSTRUE;
    dp->dp_Res2 = 0;
    reply_packet(dp);
}

/* name requests that only answer success or an error (all refused while read-only) */
static void name_request(struct DosPacket *dp, struct FileLock *lock, unsigned char *name)
{
    struct DeleteObjectRequest *req = (struct DeleteObjectRequest *)request_buffer;
    struct DeleteObjectResponse *res = (struct DeleteObjectResponse *)request_buffer;
    int nlen = *name;

    if (!lock_ok(dp, lock))
        return;
    req->type = dp->dp_Type;
    req->key = lock_key(lock);
    copy_mem(req->name, name, nlen + 1);
    write_req_and_wait_for_res(sizeof(struct DeleteObjectRequest) + nlen);
    dp->dp_Res1 = res->success ? DOSTRUE : DOSFALSE;
    dp->dp_Res2 = res->success ? 0 : res->error_code;
}

static void action_delete_object(struct DosPacket *dp)
{
    name_request(dp, (struct FileLock *)BADDR(dp->dp_Arg1), (unsigned char *)BADDR(dp->dp_Arg2));
    reply_packet(dp);
}

static void action_create_dir(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg2);
    struct CreateDirRequest *req = (struct CreateDirRequest *)request_buffer;
    struct CreateDirResponse *res = (struct CreateDirResponse *)request_buffer;
    int nlen = *name;

    if (lock_ok(dp, lock))
    {
        req->type = dp->dp_Type;
        req->key = lock_key(lock);
        copy_mem(req->name, name, nlen + 1);
        write_req_and_wait_for_res(sizeof(struct CreateDirRequest) + nlen);
        if (!res->success)
        {
            dp->dp_Res1 = DOSFALSE;
            dp->dp_Res2 = res->error_code;
        }
        else
        {
            struct FileLock *nl = create_and_add_file_lock(res->key, SHARED_LOCK);
            dp->dp_Res1 = UMKBADDR(nl);
            dp->dp_Res2 = nl ? 0 : ERROR_NO_FREE_STORE;
        }
    }
    reply_packet(dp);
}

static void action_rename_object(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg2);
    struct FileLock *target_dir = (struct FileLock *)BADDR(dp->dp_Arg3);
    unsigned char *new_name = (unsigned char *)BADDR(dp->dp_Arg4);
    struct RenameObjectRequest *req = (struct RenameObjectRequest *)request_buffer;
    struct RenameObjectResponse *res = (struct RenameObjectResponse *)request_buffer;
    int nlen = *name, nnlen = *new_name;
    unsigned char *p;

    if (lock_ok(dp, lock) && lock_ok(dp, target_dir))
    {
        req->type = dp->dp_Type;
        req->key = lock_key(lock);
        req->target_dir = lock_key(target_dir);
        req->name_len = nlen;
        req->new_name_len = nnlen;
        p = &(req->new_name_len) + 1;
        copy_mem(p, name + 1, nlen);
        copy_mem(p + nlen, new_name + 1, nnlen);
        write_req_and_wait_for_res(sizeof(struct RenameObjectRequest) + nlen + nnlen);
        dp->dp_Res1 = res->success ? DOSTRUE : DOSFALSE;
        dp->dp_Res2 = res->success ? 0 : res->error_code;
    }
    reply_packet(dp);
}

static void action_set_protect(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg2);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg3);
    struct SetProtectRequest *req = (struct SetProtectRequest *)request_buffer;
    struct SetProtectResponse *res = (struct SetProtectResponse *)request_buffer;
    int nlen = *name;

    if (lock_ok(dp, lock))
    {
        req->type = dp->dp_Type;
        req->key = lock_key(lock);
        req->mask = dp->dp_Arg4;
        copy_mem(req->name, name, nlen + 1);
        write_req_and_wait_for_res(sizeof(struct SetProtectRequest) + nlen);
        dp->dp_Res1 = res->success ? DOSTRUE : DOSFALSE;
        dp->dp_Res2 = res->success ? 0 : res->error_code;
    }
    reply_packet(dp);
}

static void action_set_comment(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg2);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg3);
    unsigned char *comment = (unsigned char *)BADDR(dp->dp_Arg4);
    struct SetCommentRequest *req = (struct SetCommentRequest *)request_buffer;
    struct SetCommentResponse *res = (struct SetCommentResponse *)request_buffer;
    int nlen = *name, clen = *comment;
    unsigned char *p;

    if (lock_ok(dp, lock))
    {
        req->type = dp->dp_Type;
        req->key = lock_key(lock);
        req->name_len = nlen;
        req->comment_len = clen;
        p = &(req->comment_len) + 1;
        copy_mem(p, name + 1, nlen);
        copy_mem(p + nlen, comment + 1, clen);
        write_req_and_wait_for_res(sizeof(struct SetCommentRequest) + nlen + clen);
        dp->dp_Res1 = res->success ? DOSTRUE : DOSFALSE;
        dp->dp_Res2 = res->success ? 0 : res->error_code;
    }
    reply_packet(dp);
}

static void action_set_date(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg2);
    unsigned char *name = (unsigned char *)BADDR(dp->dp_Arg3);
    struct DateStamp *date = (struct DateStamp *)dp->dp_Arg4;
    struct SetDateRequest *req = (struct SetDateRequest *)request_buffer;
    struct SetDateResponse *res = (struct SetDateResponse *)request_buffer;
    int nlen = *name;

    if (lock_ok(dp, lock))
    {
        req->type = dp->dp_Type;
        req->key = lock_key(lock);
        req->date[0] = date->ds_Days;
        req->date[1] = date->ds_Minute;
        req->date[2] = date->ds_Tick;
        copy_mem(req->name, name, nlen + 1);
        write_req_and_wait_for_res(sizeof(struct SetDateRequest) + nlen);
        dp->dp_Res1 = res->success ? DOSTRUE : DOSFALSE;
        dp->dp_Res2 = res->success ? 0 : res->error_code;
    }
    reply_packet(dp);
}

static void action_set_file_size(struct DosPacket *dp)
{
    struct SetFileSizeRequest *req = (struct SetFileSizeRequest *)request_buffer;
    struct SetFileSizeResponse *res = (struct SetFileSizeResponse *)request_buffer;

    if (!lock_ok(dp, NULL))
    {
        dp->dp_Res1 = -1;
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->arg1 = dp->dp_Arg1;
    req->offset = dp->dp_Arg2;
    req->mode = dp->dp_Arg3;
    write_req_and_wait_for_res(sizeof(struct SetFileSizeRequest));
    if (!res->success)
    {
        dp->dp_Res1 = -1;
        dp->dp_Res2 = res->error_code;
    }
    else
    {
        dp->dp_Res1 = res->new_size;
        dp->dp_Res2 = 0;
    }
    reply_packet(dp);
}

static void action_same_lock(struct DosPacket *dp)
{
    struct FileLock *lock1 = (struct FileLock *)BADDR(dp->dp_Arg1);
    struct FileLock *lock2 = (struct FileLock *)BADDR(dp->dp_Arg2);
    struct SameLockRequest *req = (struct SameLockRequest *)request_buffer;
    struct SameLockResponse *res = (struct SameLockResponse *)request_buffer;

    if (!cur_vol || !lock1 || !lock2 ||
        lock1->fl_Volume != UMKBADDR(cur_vol) || lock2->fl_Volume != UMKBADDR(cur_vol))
    {
        /* not both on the current volume: the same only if it is the same lock */
        dp->dp_Res1 = lock1 == lock2 ? DOSTRUE : DOSFALSE;
        dp->dp_Res2 = lock1 == lock2 ? LOCK_SAME : LOCK_DIFFERENT;
        reply_packet(dp);
        return;
    }
    req->type = dp->dp_Type;
    req->key1 = lock1->fl_Key;
    req->key2 = lock2->fl_Key;
    write_req_and_wait_for_res(sizeof(struct SameLockRequest));
    dp->dp_Res1 = res->success ? DOSTRUE : DOSFALSE;
    dp->dp_Res2 = res->error_code;
    reply_packet(dp);
}

static void fill_info_data(struct DosPacket *dp, struct InfoData *id)
{
    clear_mem(id, sizeof(struct InfoData));
    id->id_BytesPerBlock = 512;
    if (!cur_vol)
    {
        id->id_DiskState = ID_WRITE_PROTECTED;
        id->id_DiskType = ID_NO_DISK_PRESENT;
        return;
    }
    id->id_DiskState = firmware_writes() ? ID_VALIDATED : ID_WRITE_PROTECTED;
    {
        struct DiskInfoRequest *req = (struct DiskInfoRequest *)request_buffer;
        struct DiskInfoResponse *res = (struct DiskInfoResponse *)request_buffer;
        req->type = dp->dp_Type;
        req->key = 0;
        req->dummy1 = 0;
        req->dummy2 = 0;
        write_req_and_wait_for_res(sizeof(struct DiskInfoRequest));
        if (res->success)
        {
            id->id_NumBlocks = res->total;
            id->id_NumBlocksUsed = res->used;
        }
    }
    id->id_DiskType = cur_vol->dl_DiskType;
    id->id_VolumeNode = UMKBADDR(cur_vol);
    id->id_InUse = cur_vol->dl_Lock ? DOSTRUE : DOSFALSE;
}

static void action_info(struct DosPacket *dp)
{
    struct FileLock *lock = (struct FileLock *)BADDR(dp->dp_Arg1);
    struct InfoData *id = (struct InfoData *)BADDR(dp->dp_Arg2);

    if (lock && (!cur_vol || lock->fl_Volume != UMKBADDR(cur_vol)))
    {
        dp->dp_Res1 = DOSFALSE;
        dp->dp_Res2 = ERROR_DEVICE_NOT_MOUNTED;
    }
    else
    {
        fill_info_data(dp, id);
        dp->dp_Res1 = DOSTRUE;
        dp->dp_Res2 = 0;
    }
    reply_packet(dp);
}

static void action_disk_info(struct DosPacket *dp)
{
    fill_info_data(dp, (struct InfoData *)BADDR(dp->dp_Arg1));
    dp->dp_Res1 = DOSTRUE;
    dp->dp_Res2 = 0;
    reply_packet(dp);
}

static void action_simple(struct DosPacket *dp, LONG res1, LONG res2)
{
    dp->dp_Res1 = res1;
    dp->dp_Res2 = res2;
    reply_packet(dp);
}

/* ------------------------------------------------------------------- start */

static void startup_fs_handler(struct DosPacket *dp)
{
    struct DeviceNode *node = (struct DeviceNode *)BADDR(dp->dp_Arg3);

    node->dn_Task = mp;
    dp->dp_Res1 = DOSTRUE;
    dp->dp_Res2 = 0;
    reply_packet(dp);
}

static void open_devices(void)
{
    timer_port = create_port();
    if (timer_port)
    {
        timer_req = (struct timerequest *)AllocMem(sizeof(struct timerequest), MEMF_PUBLIC | MEMF_CLEAR);
        if (timer_req)
        {
            timer_req->tr_node.io_Message.mn_Node.ln_Type = NT_MESSAGE;
            timer_req->tr_node.io_Message.mn_ReplyPort = timer_port;
            timer_req->tr_node.io_Message.mn_Length = sizeof(struct timerequest);
            timer_ok = OpenDevice(TIMERNAME, UNIT_VBLANK, (struct IORequest *)timer_req, 0) == 0;
        }
    }
    input_port = create_port();
    if (input_port)
    {
        input_req = (struct IOStdReq *)AllocMem(sizeof(struct IOStdReq), MEMF_PUBLIC | MEMF_CLEAR);
        if (input_req)
        {
            input_req->io_Message.mn_Node.ln_Type = NT_MESSAGE;
            input_req->io_Message.mn_ReplyPort = input_port;
            input_req->io_Message.mn_Length = sizeof(struct IOStdReq);
            input_ok = OpenDevice("input.device", 0, (struct IORequest *)input_req, 0) == 0;
        }
    }
}

static void start_timer(void)
{
    if (!timer_ok)
        return;
    timer_req->tr_node.io_Command = TR_ADDREQUEST;
    timer_req->tr_time.tv_secs = 1;
    timer_req->tr_time.tv_micro = 0;
    SendIO((struct IORequest *)timer_req);
}

void start(__reg("a0") struct DosPacket *startup_packet)
{
    ULONG port_sig, timer_sig;

    SysBase = *(struct ExecBase **)4;
    DOSBase = (struct DosLibrary *)OpenLibrary(DOSNAME, 0);

    mp = create_port();
    startup_fs_handler(startup_packet);
    open_devices();
    check_media();
    start_timer();

    port_sig = 1L << mp->mp_SigBit;
    timer_sig = timer_ok ? 1L << timer_port->mp_SigBit : 0;

    while (1)
    {
        struct StandardPacket *sp;
        ULONG sigs = Wait(port_sig | timer_sig);

        if (sigs & timer_sig)
        {
            if (GetMsg(timer_port))
            {
                check_media();
                start_timer();
            }
        }

        while ((sp = (struct StandardPacket *)GetMsg(mp)) != NULL)
        {
            struct DosPacket *dp = (struct DosPacket *)(sp->sp_Msg.mn_Node.ln_Name);

            check_media();
            switch (dp->dp_Type)
            {
            case ACTION_LOCATE_OBJECT: action_locate_object(dp); break;
            case ACTION_FREE_LOCK: action_free_lock(dp); break;
            case ACTION_COPY_DIR: action_copy_dir(dp); break;
            case ACTION_PARENT: action_parent(dp); break;
            case ACTION_EXAMINE_OBJECT: action_examine_object(dp); break;
            case ACTION_EXAMINE_NEXT: action_examine_next(dp); break;
            case ACTION_EXAMINE_FH: action_examine_fh(dp); break;
            case ACTION_FINDUPDATE:
            case ACTION_FINDINPUT:
            case ACTION_FINDOUTPUT: action_findxxx(dp); break;
            case ACTION_FH_FROM_LOCK: action_fh_from_lock(dp); break;
            case ACTION_READ: action_read(dp); break;
            case ACTION_WRITE: action_write(dp); break;
            case ACTION_SEEK: action_seek(dp); break;
            case ACTION_END: action_end(dp); break;
            case ACTION_DELETE_OBJECT: action_delete_object(dp); break;
            case ACTION_RENAME_OBJECT: action_rename_object(dp); break;
            case ACTION_CREATE_DIR: action_create_dir(dp); break;
            case ACTION_SET_PROTECT: action_set_protect(dp); break;
            case ACTION_SET_COMMENT: action_set_comment(dp); break;
            case ACTION_SAME_LOCK: action_same_lock(dp); break;
            case ACTION_SET_DATE: action_set_date(dp); break;
            case ACTION_SET_FILE_SIZE: action_set_file_size(dp); break;
            case ACTION_DISK_INFO: action_disk_info(dp); break;
            case ACTION_INFO: action_info(dp); break;
            case ACTION_CURRENT_VOLUME:
                action_simple(dp, UMKBADDR(cur_vol), 0); break;
            case ACTION_IS_FILESYSTEM:
            case ACTION_FLUSH:
            case ACTION_INHIBIT:
                action_simple(dp, DOSTRUE, 0); break;
            default:
                action_simple(dp, DOSFALSE, ERROR_ACTION_NOT_KNOWN); break;
            }
        }
    }
}
