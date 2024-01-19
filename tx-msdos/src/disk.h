#ifndef DISK_H
#define DISK_H

typedef struct {
  short c; /* Cylinders */
  unsigned char h; /* Heads */
  unsigned char s; /* Sectors per Track */
} CHS;

// linked list of read errors
typedef struct {
  unsigned long sector; // set to current position of read error
  char* status_msg; // status message when the error was encountered
  unsigned char status_code;
  void* next; // set to 0 if no more read errors
} ReadError;

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
  // read error information
  ReadError* read_error_head; // 0 if no read errors
  ReadError* read_error_tail; // 0 if no read errors
} Disk;

Disk* create_disk();

void free_disk();

void set_sector(Disk* disk, unsigned long sector);

void add_read_error(Disk* disk);

void print_read_errors();

#endif /* DISK_H */