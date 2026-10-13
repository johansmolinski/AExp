/*
 * Megamiga: the requests and responses of the shared folder, in the layout of MiSTer's
 * Main_MiSTer support/minimig/miminig_fs_messages.h (GPL), itself the a314fs messages.h of
 * Niklas Ekstrom (CC0). 32-bit big-endian fields, no padding (all are longs or bytes in an
 * order that needs none on the 68000).
 */
#ifndef SHARE_MSG_H
#define SHARE_MSG_H
struct LocateObjectRequest
{
	long sz;
	long type;
	long key;
	long mode;
	char name[1];
};

struct LocateObjectResponse
{
	long sz;
	long success;
	long error_code;
	long key;
};

struct FreeLockRequest
{
	long sz;
	long type;
	long key;
};

struct FreeLockResponse
{
	long sz;
	long success;
	long error_code;
};

struct CopyDirRequest
{
	long sz;
	long type;
	long key;
};

struct CopyDirResponse
{
	long sz;
	long success;
	long error_code;
	long key;
};

struct ParentRequest
{
	long sz;
	long type;
	long key;
};

struct ParentResponse
{
	long sz;
	long success;
	long error_code;
	long key;
};

struct ExamineObjectRequest
{
	long sz;
	long type;
	long key;
	long disk_key;
};

struct ExamineObjectResponse
{
	long sz;
	long success;
	long error_code;

	long disk_key;
	long entry_type;
	int size;
	int protection;
	int date[3];
	char file_name[1];
};

struct FindXxxRequest
{
	long sz;
	long type;
	long key;
	char name[1];
};

struct FindXxxResponse
{
	long sz;
	long success;
	long error_code;
	long arg1;
};

struct ReadRequest
{
	long sz;
	long type;
	long arg1;
	int address;
	int length;
};

struct ReadResponse
{
	long sz;
	long success;
	long error_code;
	int actual;
};

struct WriteRequest
{
	long sz;
	long type;
	long arg1;
	int address;
	int length;
};

struct WriteResponse
{
	long sz;
	long success;
	long error_code;
	int actual;
};

struct SeekRequest
{
	long sz;
	long type;
	long arg1;
	int new_pos;
	int mode;
};

struct SeekResponse
{
	long sz;
	long success;
	long error_code;
	int old_pos;
};

struct EndRequest
{
	long sz;
	long type;
	long arg1;
};

struct EndResponse
{
	long sz;
	long success;
	long error_code;
};

struct DeleteObjectRequest
{
	long sz;
	long type;
	long key;
	char name[1];
};

struct DeleteObjectResponse
{
	long sz;
	long success;
	long error_code;
};

struct RenameObjectRequest
{
	long sz;
	long type;
	long key;
	long target_dir;
	unsigned char name_len;
	unsigned char new_name_len;
	char name[1];
};

struct RenameObjectResponse
{
	long sz;
	long success;
	long error_code;
};

struct CreateDirRequest
{
	long sz;
	long type;
	long key;
	char name[1];
};

struct CreateDirResponse
{
	long sz;
	long success;
	long error_code;
	long key;
};

struct SetProtectRequest
{
	long sz;
	long type;
	long key;
	long mask;
	char name[1];
};

struct SetProtectResponse
{
	long sz;
	long success;
	long error_code;
};

struct SetCommentRequest
{
	long sz;
	long type;
	long key;
	unsigned char name_len;
	unsigned char comment_len;
};

struct SetCommentResponse
{
	long sz;
	long success;
	long error_code;
};

struct SameLockRequest
{
	long sz;
	long type;
	long key1;
	long key2;
};

struct SameLockResponse
{
	long sz;
	long success;
	long error_code;
};

struct ExamineFhRequest
{
	long sz;
	long type;
	long arg1;
};

struct ExamineFhResponse
{
	long sz;
	long success;
	long error_code;

	long disk_key;
	long entry_type;
	int size;
	int protection;
	int date[3];
	char file_name[1];
};

struct DiskInfoRequest
{
	long sz;
	long type;
	long key;
	long dummy1;
	long dummy2;
};

struct DiskInfoResponse
{
	long sz;
	long success;
	long error_code;
	unsigned long total;
	unsigned long used;
	long update;
};

/* Megamiga extensions (protocol version 2, see MegamigaFS.c) */

/* the current Amiga time, written by the handler before every request */
#define SHARE_TIME_ADDR 0xDD4FE0

struct SetDateRequest
{
	long sz;
	long type;
	long key;
	long date[3];           /* DateStamp: days, minute, tick */
	char name[1];           /* BSTR */
};

struct SetDateResponse
{
	long sz;
	long success;
	long error_code;
};

struct SetFileSizeRequest
{
	long sz;
	long type;
	long arg1;              /* the file handle */
	long offset;
	long mode;              /* OFFSET_BEGINNING, OFFSET_CURRENT, OFFSET_END */
};

struct SetFileSizeResponse
{
	long sz;
	long success;
	long error_code;
	long new_size;
};

#endif
