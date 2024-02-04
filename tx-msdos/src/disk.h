#ifndef DISK_H
#define DISK_H

typedef struct {
    short c; /* Cylinders */
    unsigned char h; /* Heads */
    unsigned char s; /* Sectors per Track */
} CHS;

// linked list of read logs
typedef struct {
    unsigned long sector; // set to current position of read log
    char* status_msg; // status message when the error was encountered
    unsigned char status_code;
    unsigned char retry_count;
    void* next; // set to 0 if no more read logs
} ReadLog;

typedef struct {
    // device information
    unsigned char device_id;
    char device_letter;
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
    // read log information
    ReadLog* read_log_tail; // 0 if no read logs
} Disk;

Disk* create_disk(char drive_letter);

void free_disk(Disk* disk);

void set_sector(Disk* disk, unsigned long sector);

void set_geometry(Disk* disk, CHS geometry);

void add_read_log(Disk* disk, unsigned char retry_count);

void update_read_log(Disk* disk, unsigned char retry_count);

void print_read_logs(Disk* disk);

#endif /* DISK_H */
