/**
 * tx - disk-send
 * 
 * BIOS INT 13H (Disk) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#ifndef INT13_H
#define INT13_H

typedef struct {
  short c; /* Cylinders */
  unsigned char h; /* Heads */
  unsigned char s; /* Sectors per Track */
} CHS;

#define AH_READ_DISK_SECTORS    0x02
#define AH_GET_DRIVE_PARAMETERS 0x08

/**
 * Get disk Geometry
 */
unsigned char int13_disk_geometry(CHS* geometry);

/**
 * Read sector given CHS
 */
unsigned char int13_read_sector(CHS* read_position, char* buf);

#endif /* INT13_H */
