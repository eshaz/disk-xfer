#ifndef DISK_H
#define DISK_H

typedef struct {
  short c; /* Cylinders */
  unsigned char h; /* Heads */
  unsigned char s; /* Sectors per Track */
} CHS;

// linked list of bad sectors
typedef struct {
  unsigned long sector; // set to current position of bad sector
  char* status_msg; // status message when the error was encountered
  unsigned char status_code;
  void* next; // set to 0 if no more bad sectors
} BadSector;

typedef struct {
  // device information
  unsigned char device_id;
  CHS geometry;
  unsigned long total_sectors;
  unsigned long total_bytes;
  // current posittion information
  CHS position;
  unsigned long current_sector;
  unsigned long current_byte;
  // status information
  unsigned char status_code;
  char* status_msg;
  // bad sector information
  BadSector* bad_sector_head; // 0 if no bad sectors
  BadSector* bad_sector_tail; // 0 if no bad sectors
} Disk;

Disk* create_disk();

void free_disk();

void set_sector(Disk* disk, unsigned long sector);

void add_bad_sector(Disk* disk);

void print_bad_sectors();

#endif /* DISK_H */