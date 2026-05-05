#ifndef RUNNER_WINTAB_DEFINES_H_
#define RUNNER_WINTAB_DEFINES_H_

// Wintab API definitions (inline, no external SDK needed).
// Based on the Wintab 1.4 specification.
// Reference: https://developer-docs.wacom.com/intuos-cintiq-business-702/docs/wintab-basics

#include <windows.h>

// FIX32 is a Wintab fixed-point type (16.16)
typedef DWORD FIX32;

// Wintab message
#define WT_DEFBASE    0x7FF0
#define WT_MAXOFFSET  0x0F
#define WT_PACKET     (WT_DEFBASE + 0)
#define WT_CTXOPEN    (WT_DEFBASE + 1)
#define WT_CTXCLOSE   (WT_DEFBASE + 2)
#define WT_CTXUPDATE  (WT_DEFBASE + 3)
#define WT_CTXOVERLAP (WT_DEFBASE + 4)
#define WT_PROXIMITY  (WT_DEFBASE + 5)
#define WT_INFOCHANGE (WT_DEFBASE + 6)
#define WT_CSRCHANGE  (WT_DEFBASE + 7)
#define WT_PACKETEXT  (WT_DEFBASE + 8)

// Wintab packet data items (PK_*)
#define PK_CONTEXT        0x0001
#define PK_STATUS         0x0002
#define PK_TIME           0x0004
#define PK_CHANGED        0x0008
#define PK_SERIAL_NUMBER  0x0010
#define PK_CURSOR         0x0020
#define PK_BUTTONS        0x0040
#define PK_X              0x0080
#define PK_Y              0x0100
#define PK_Z              0x0200
#define PK_NORMAL_PRESSURE 0x0400
#define PK_TANGENT_PRESSURE 0x0800
#define PK_ORIENTATION    0x1000

// Context option flags
#define CXO_SYSTEM   0x0001
#define CXO_PEN      0x0002
#define CXO_MESSAGES 0x0004
#define CXO_MARGIN   0x8000
#define CXO_MGNINSIDE 0x4000
#define CXO_CSRMESSAGES 0x0008

// Wintab info categories
#define WTI_DEFCONTEXT 3
#define WTI_DEFSYSCTX  4
#define WTI_DEVICES    100

// Device info indices (Wintab 1.4 spec)
#define DVC_X          12
#define DVC_Y          13
#define DVC_Z          14
#define DVC_NPRESSURE  15
#define DVC_TPRESSURE  16
#define DVC_ORIENTATION 17

// Context fields
#define CTX_NAME       1
#define CTX_OPTIONS    2
#define CTX_STATUS     3
#define CTX_LOCKS      4
#define CTX_MSGBASE    5
#define CTX_DEVICE     6
#define CTX_PKTRATE    7
#define CTX_PKTDATA    8
#define CTX_PKTMODE    9
#define CTX_MOVEMASK   10
#define CTX_BUTNDN     11
#define CTX_BTNUP      12
#define CTX_INORGX     13
#define CTX_INORGY     14
#define CTX_INORGZ     15
#define CTX_INEXTX     16
#define CTX_INEXTY     17
#define CTX_INEXTZ     18
#define CTX_OUTORGX    19
#define CTX_OUTORGY    20
#define CTX_OUTORGZ    21
#define CTX_OUTEXTX    22
#define CTX_OUTEXTY    23
#define CTX_OUTEXTZ    24
#define CTX_SENSX      25
#define CTX_SENSY      26
#define CTX_SENSZ      27
#define CTX_SYSMODE    28
#define CTX_SYSORGX    29
#define CTX_SYSORGY    30
#define CTX_SYSEXTX    31
#define CTX_SYSEXTY    32
#define CTX_SYSSEN     33

// Wintab types
typedef HANDLE HCTX;
typedef UINT WTPKT;

// AXIS structure
typedef struct tagAXIS {
  LONG axMin;
  LONG axMax;
  UINT axUnits;
  FIX32 axResolution;
} AXIS;

// LOGCONTEXT structure (Wintab context)
typedef struct tagLOGCONTEXTA {
  char   lcName[40];
  UINT   lcOptions;
  UINT   lcStatus;
  UINT   lcLocks;
  UINT   lcMsgBase;
  UINT   lcDevice;
  UINT   lcPktRate;
  WTPKT  lcPktData;
  WTPKT  lcPktMode;
  WTPKT  lcMoveMask;
  DWORD  lcBtnDnMask;
  DWORD  lcBtnUpMask;
  LONG   lcInOrgX;
  LONG   lcInOrgY;
  LONG   lcInOrgZ;
  LONG   lcInExtX;
  LONG   lcInExtY;
  LONG   lcInExtZ;
  LONG   lcOutOrgX;
  LONG   lcOutOrgY;
  LONG   lcOutOrgZ;
  LONG   lcOutExtX;
  LONG   lcOutExtY;
  LONG   lcOutExtZ;
  FIX32  lcSensX;
  FIX32  lcSensY;
  FIX32  lcSensZ;
  BOOL   lcSysMode;
  int    lcSysOrgX;
  int    lcSysOrgY;
  int    lcSysExtX;
  int    lcSysExtY;
  FIX32  lcSysSensX;
  FIX32  lcSysSensY;
} LOGCONTEXTA;

// PACKET structure - must match lcPktData flags
// We request: PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_CURSOR | PK_BUTTONS
typedef struct tagWINTAB_PACKET {
  UINT   pkCursor;
  DWORD  pkButtons;
  LONG   pkX;
  LONG   pkY;
  UINT   pkNormalPressure;
} WINTAB_PACKET;

// Wintab function pointer types
typedef UINT  (WINAPI* WTINFOA_FUNC)(UINT, UINT, LPVOID);
typedef HCTX  (WINAPI* WTOPENA_FUNC)(HWND, LOGCONTEXTA*, BOOL);
typedef BOOL  (WINAPI* WTCLOSE_FUNC)(HCTX);
typedef BOOL  (WINAPI* WTPACKET_FUNC)(HCTX, UINT, LPVOID);
typedef BOOL  (WINAPI* WTENABLE_FUNC)(HCTX, BOOL);
typedef BOOL  (WINAPI* WTOVERLAP_FUNC)(HCTX, BOOL);
typedef int   (WINAPI* WTQUEUESIZESET_FUNC)(HCTX, int);

#endif  // RUNNER_WINTAB_DEFINES_H_
