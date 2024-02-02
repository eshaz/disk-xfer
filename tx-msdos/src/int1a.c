#include "int1a.h"
#include <i86.h>

static union REGS regs;

/*
INT 1A - TIME - GET SYSTEM TIME
        AH = 00h
Return: CX:DX = number of clock ticks since midnight
        AL = midnight flag, nonzero if midnight passed since time last read
Notes:	there are approximately 18.2 clock ticks per second, 1800B0h per 24 hrs
          (except on Tandy 2000, where the clock runs at 20 ticks per second)
        IBM and many clone BIOSes set the flag for AL rather than incrementing
          it, leading to loss of a day if two consecutive midnights pass
          without a request for the time (e.g. if the system is on but idle)
        since the midnight flag is cleared, if an application calls this
          function after midnight before DOS does, DOS will not receive the
          midnight flag and will fail to advance the date
        Modern releases of MS-DOS/PC DOS (5.0+???) assume that AL is a day
          rollover counter rather than a flag, as expected by older releases.
          DOS 5 - 7.10 (Windows 98 SE) provide an undocumented CONFIG.SYS
          SWITCHES=/T option to force the old behaviour of the day advancing
          code, that is using a flag instead of a counter.
        DR DOS 3.31 - DR-DOS 7.03 handle AL as a flag.
*/
static const double time_divisor = 18.206481481; // 0x1800b0 / 24 / 60 / 60
static unsigned int days = 0;

unsigned long int1a_get_system_time()
{
    unsigned long ticks;

    regs.h.ah = 0x00;
    regs.h.al = 0;
    regs.w.cx = 0;
    regs.w.dx = 0;
    int86(0x1A, &regs, &regs);

    if (regs.h.al == 1)
        days++;
    ticks = regs.w.cx;
    ticks <<= 16;
    ticks |= regs.w.dx;
    ticks += days * 0x1800b0;

    return ticks;
}

double int1a_system_ticks_to_seconds(unsigned long ticks)
{
    return (double)ticks / time_divisor;
}