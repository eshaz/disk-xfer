/**
 * tx - disk-send
 * 
 * BIOS INT 13H (Disk) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include <i86.h>
#include "int13.h"

union REGS regs;

/**
 * Get disk Geometry
 */
unsigned char int13_disk_geometry(Disk* disk)
{
  // BIOS call to get disk geometry.
  regs.h.ah=AH_GET_DRIVE_PARAMETERS;
  regs.h.dl=disk->device_id;
  int86(0x13,&regs,&regs);

  /**
   * https://tldp.org/HOWTO/Large-Disk-HOWTO-4.html
   * 
   * At most 
   * 1024 cylinders (0-1023), 
   * 16 heads (0-15), 
   * 63 sectors/track (1-63)
   * total capacity of 528482304 bytes (528MB)
   */

  // Unpack disk geometry.
  disk->geometry.c=regs.h.ch;              // Get lower 8 bits of cylinder count.
  disk->geometry.c|=((regs.h.cl)&0xC0)<<2; // Get upper two bits of cylinder count.
  disk->geometry.c+=1;
  disk->geometry.h=regs.h.dh;
  disk->geometry.s=regs.h.cl&0x3F;         // mask off high order bits of cylinder count (upper 2-bits)

  disk->total_sectors = (unsigned long)(disk->geometry.c + 1) * (disk->geometry.h + 1) * disk->geometry.s - 1;
  disk->total_bytes = (unsigned long)(disk->total_sectors + 1) * 512;

  // 0 if successful, 1 if not.
  return regs.x.cflag;
}

/**
 * Read sector given CHS
 */
unsigned char int13_read_sector(Disk* disk, char* buf)
{
  // Perform the read.
  regs.h.ah=AH_READ_DISK_SECTORS;
  regs.h.al=1;                               // 1 sector.
  regs.h.dh=disk->position.h;
  regs.h.dl=disk->device_id;
  regs.x.bx=(short)buf;
  regs.h.ch=disk->position.c&0xFF;           // cyl low
  regs.h.cl=disk->position.s;
  regs.h.cl|=((disk->position.c >> 2)&0xC0); // sector / cyl high */
  int86(0x13,&regs,&regs);

  disk->status_code = regs.h.ah;
  int13_set_status(disk);

  // 0 if successful, 1 if not.
  return regs.x.cflag;
}

unsigned char int13_reset_disk_system(Disk* disk) {
  // Perform the read.
  regs.h.ah=AH_RESET_DISK_SYSTEM;
  regs.h.dl=disk->device_id;
  int86(0x13,&regs,&regs);

  disk->status_code = regs.h.ah;
  int13_set_status(disk);

  // 0 if successful, 1 if not.
  return regs.x.cflag;
}

static char* status_msgs[] = {
  "no error", // 00
  "bad command passed to driver", // 01
  "address mark not found or bad sector", // 02
  "diskette write protect error", // 03
  "sector not found", // 04
  "fixed disk reset failed", // 05
  "diskette changed or removed", // 06
  "bad fixed disk parameter table", // 07
  "DMA overrun", // 08
  "DMA access across 64k boundary", // 09
  "bad fixed disk sector flag", // 0A
  "bad fixed disk cylinder", // 0B
  "unsupported track/invalid media", // 0C
  "invalid number of sectors on fixed disk format", // 0D
  "fixed disk controlled data address mark detected", // 0E
  "fixed disk DMA arbitration level out of range", // 0F
  "ECC/CRC error on disk read", // 10
  "recoverable fixed disk data error, data fixed by ECC" // 11
  "controller error (NEC for floppies)", // 20
  "seek failure", // 40
  "time out, drive not ready", // 80
  "fixed disk drive not ready", // AA
  "fixed disk undefined error", // BB
  "fixed disk write fault on selected drive", // CC
  "fixed disk status error/Error reg = 0", // E0
  "sense operation failed" // FF
};

static void int13_set_status(Disk* disk) {
  if (disk->status_code < 0x11) {
    disk->status_msg = (char*) status_msgs[disk->status_code];
  } else {
    switch (disk->status_code) {
      case 0x20: disk->status_msg = status_msgs[0x12]; break;
      case 0x40: disk->status_msg = status_msgs[0x13]; break;
      case 0x80: disk->status_msg = status_msgs[0x14]; break;
      case 0xAA: disk->status_msg = status_msgs[0x15]; break;
      case 0xBB: disk->status_msg = status_msgs[0x16]; break;
      case 0xCC: disk->status_msg = status_msgs[0x17]; break;
      case 0xE0: disk->status_msg = status_msgs[0x18]; break;
      case 0xFF: disk->status_msg = status_msgs[0x19]; break;
      default: "unknown error"; break;
    }
  }
}