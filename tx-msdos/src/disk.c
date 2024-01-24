#include "disk.h"
#include "utils.h"
#include <stdio.h>
#include <stdlib.h>

/**
 * Readlog (for logging bad sectors or other read errors)
 */
static ReadLog* iterate_read_logs(Disk* disk, unsigned char (*operation)(Disk* disk, ReadLog* rl))
{
    ReadLog* rl = disk->read_log_tail;
    if (rl) { // if the log isn't empty
        do {
            rl = rl->next;
            if (operation(disk, rl))
                return rl; // return this read log entry if operation returns 1
        } while (rl != disk->read_log_tail); // iterate until reaching the tail again
    }
    return rl;
}

static char print_read_log(Disk* disk, ReadLog* rl)
{
    fprintf(stderr, "\n Block: %lu, Retry Count: %3u, Code: 0x%02X, %s.", rl->sector, rl->retry_count, rl->status_code, rl->status_msg);
    return 0;
}

static char free_read_log(Disk* disk, ReadLog* rl)
{
    free(rl);
    return 0;
}

static char is_current_sector_in_read_log(Disk* disk, ReadLog* rl)
{
    if (rl->sector == disk->current_sector)
        return 1;
    return 0;
}

void add_read_log(Disk* disk, unsigned char retry_count)
{
    ReadLog* rl = malloc(sizeof(ReadLog));
    rl->sector = disk->current_sector;
    rl->status_code = disk->status_code;
    rl->status_msg = disk->status_msg;
    rl->retry_count = retry_count;

    if (disk->read_log_tail == 0) {
        // head is the tail
        disk->read_log_tail = rl;
        rl->next = rl;
    } else {
        rl->next = disk->read_log_tail->next; // tail always points to the head
        disk->read_log_tail->next = rl; // point old tail to the next node
        disk->read_log_tail = rl; // add new tail
    }
}

void update_read_log(Disk* disk, unsigned char retry_count)
{
    if (disk->read_log_tail == 0) {
        add_read_log(disk, retry_count);
    } else {
        disk->read_log_tail->retry_count = retry_count;
    }
}

void print_read_logs(Disk* disk)
{
    iterate_read_logs(disk, &print_read_log);
}

ReadLog* get_read_log_for_current_sector(Disk* disk)
{
    ReadLog* rl = iterate_read_logs(disk, &is_current_sector_in_read_log);
    if (rl && rl->sector == disk->current_sector)
        return rl;
    return (ReadLog*)NULL; // null pointer if not found
}

/**
 * Disk data structure
 */

Disk* create_disk()
{
    Disk* disk = malloc(sizeof(Disk));
    // device information
    disk->device_id = 0x80; // default to C: drive
    disk->geometry.c = 0;
    disk->geometry.h = 0;
    disk->geometry.s = 0;
    disk->total_sectors = 0;
    disk->total_bytes = 0;
    // status information
    disk->position.c = 0;
    disk->position.h = 0;
    disk->position.s = 1; // physical sector always starts at 1
    disk->current_sector = 0;
    disk->current_byte = 0;
    disk->status_code = 0;
    disk->status_msg = "";
    // read log information linked list
    disk->read_log_tail = 0;
    return disk;
}

void free_disk(Disk* disk)
{
    iterate_read_logs(disk, &free_read_log);
    free(disk->read_log_tail);
    free(disk);
}

void set_sector(Disk* disk, unsigned long sector)
{
    if (sector > disk->total_sectors) {
        fprintf(stderr, "\nFATAL: Cannot set sector to %lu which is beyond drive limit %lu", sector, disk->total_sectors);
        return;
    }
    disk->position.c = sector / (disk->geometry.s * (disk->geometry.h + 1));
    disk->position.h = (sector / disk->geometry.s) % (disk->geometry.h + 1);
    disk->position.s = 1 + (sector % disk->geometry.s);

    disk->current_sector = sector;
    disk->current_byte = sector * 512;
}

void set_geometry(Disk* disk, CHS geometry)
{
    disk->geometry = geometry;
    disk->total_sectors = (unsigned long)(disk->geometry.c + 1) * (disk->geometry.h + 1) * disk->geometry.s - 1;
    disk->total_bytes = (unsigned long)(disk->total_sectors + 1) * 512;
}