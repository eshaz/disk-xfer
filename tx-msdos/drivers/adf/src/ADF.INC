;
; adf.inc       January 19, 2000
;
; Copyright (c) 1995-2000 Scandinavian Digital Systems AB
;
;
; Revision history:
;
; Vers:     Date:       Comments:
;
; 1.10.10   950903      Reconstruction of lost source code.
; 1.10.12   951116      BETA 12
; 1.10      951122      Version released
; 1.11.01   951123      Bugfix: Clearing of Control-C / Control-K received
; 1.11.02   951127      Timer tick and debug improvements, load high fixed
; 1.11.03   951128      Added /s
; 1.11.04   951128      Modified /s. Improved error message display.
; 1.11.05   951128      Removed /s. Use INT 1CH instead of INT 08H for timer
;                       ticks.
; 1.11.06   951128      Testversion without timers
; 1.11.07   951130      Added all functions defined by X00 v1.50
; 1.11.08   951202      Some adjustments, new utilities, moved debug
;                       into separate program. FOSSIL info bug fixed.
; 1.11.09   951204      Minor changes.
; 1.11.10   951205      Baud-rate check.
; 1.20      951209      Version released.
; 1.21.02   951210      Bugfix of External Application.
; 1.21.03   951212      Bugfix of function 1E "Extended line control initialization".
; 1.21.04   951212      Bugfix of function 04, 05, 1C, 14 when used on illegal
;                       port number. Only check DL for port number (due to bugs
;                       in other programs), valid port range is now 0-126.
; 1.21.05   960104      Uses 'print_err' on registration error and expire.
;                       More use of ALIGN 4 to speed things up.
; 1.30      960120      Added COMx as port number. Version released.
; 1.31      960122      Removed time limit of 30 days. Version released.
; 1.32.01   960123      Bugfix of external application.
; 1.32      960209      Version released.
; 1.33.01   960210      Bugfix: When input buffer was purged the RTS signal was
;                       not restored (activated, made high) if it had been
;                       lowered due to flow control.
; 1.40.02   960222      Receiver flow control hold and continue may now be
;                       specified on the command line.
;                       Improved block read and write (function 18H and 19H).
;                       User settings of line and modem control registers.
;                       Included support for 16650.
; 1.40.03   960222      Minor changes.
; 1.40.04   960225      Bugfix of block read and write (function 18H and 19H).
; 1.40.05   960229      Changed protection. REGISTER v1.20 needed.
; 1.40      960323      Version released.
; 1.41.01   960524      Changed the reboot method. User may specify watchdog
;                       time out, default changed to 60 seconds.
; 1.41      960717      Version released.
; 1.42.02   960805      The FOSSIL is now always kept alive, it is never
;                       actually closed,
; 1.42.03   960921      Compilation improvements and minor changes.
; 1.42.06   960929      Does not touch 16650 register if not 16650 has been
;                       set on command line. The internal size of receive and
;                       transmit buffers adjusted so the reported sizes will
;                       be equal to the sizes on the command line.
; 1.42.07   960930      Due to behavior in Windows 95 when ADF is loaded in
;                       AUTOEXEC.BAT (not recommended), the Priority Interrupt
;                       Controller enable bits are toggled on initialization
;                       calls to the FOSSIL.
; 1.42.08   961019      Included support for 16750. ADFComCh has new
;                       ERRORLEVELs.
; 1.42.09   961026      Bug corrected for 16750 on command-line.
; 1.42      961103      Version released.
; 1.43      970309      New e-mail address, new currency tables.
;                       Version released.
; 1.44      980112      FidoNet address removed, new currency tables.
;                       Version released.
; 1.45.01   981025      Debug test of 16750.
; 1.45.02   981026      Uses 16 bytes transmit FIFO for 16750.
; 1.45      990101      Version released.
; 1.50.01   990416      The FOSSIL is kept in more hot condition, it is only
;                       initialized when loading ADF and on first call (use)
;                       of the FOSSIL.
; 1.50.02   990417      The hot condition above removed.
;                       ADFTerm improved a little.
; 1.50.03   990610      Changed protection. REGISTER v1.40 needed.
; 1.46.04   990612      NKL-version prepared. v1.46 is not to be released
;                       as shareware, v1.50 with new addresses will probably
;                       be released at September 1, 1999.
; 1.46      990713      Version released.
; 1.50.01  2000-01-19   Changed from shareware to freeware. No registration
;                       needed anymore.
;

VERSION         EQU <'1.50'>

                OPTION NOSCOPED,NOSIGNEXTEND,NOLJMP,PROC:PRIVATE

                .8086

                OPTION SEGMENT:USE16

