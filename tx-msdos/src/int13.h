/**
 * tx - disk-send
 * 
 * BIOS INT 13H (Disk) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include "disk.h"

#ifndef INT13_H
#define INT13_H

#define AH_RESET_DISK_SYSTEM    0x00
#define AH_READ_DISK_SECTORS    0x02
#define AH_GET_DRIVE_PARAMETERS 0x08

/**
 * Get disk Geometry
 */
unsigned char int13_disk_geometry(Disk* disk);

/**
 * Read sector given CHS
 */
unsigned char int13_read_sector(Disk* disk, char* buf);

unsigned char int13_reset_disk_system(Disk* disk);

#endif /* INT13_H */
