#include <stdlib.h>
#include <stdio.h>
#include "utils.h"
#include "disk.h"

static void iterate_read_errors(Disk* disk, void (*operation) (ReadError* re)) {
  ReadError* re = disk->read_error_head;
  if (re) {
    do {
      operation(re);
      re = re->next;
    } while (re);
  }
}

static void print_read_error(ReadError* re) {
    printf(" Block: %lu, Code: 0x%02X, %s.\n", re->sector, re->status_code, re->status_msg);
}

Disk* create_disk() {
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
  // read error information linked list
  disk->read_error_head = 0;
  disk->read_error_tail = 0;
  return disk;
}

void free_disk(Disk* disk) {
  iterate_read_errors(disk, &free);
  free(disk);
}

void set_sector(Disk* disk, unsigned long sector) {
  disk->position.c = sector / (disk->geometry.s * (disk->geometry.h + 1));
  disk->position.h = (sector / disk->geometry.s) % (disk->geometry.h + 1);
  disk->position.s = 1 + (sector % disk->geometry.s);

  disk->current_sector = sector;
  disk->current_byte = sector*512;
}

void add_read_error(Disk* disk) {
  ReadError* re = malloc(sizeof(ReadError));
  re->sector = disk->current_sector;
  re->status_code = disk->status_code;
  re->status_msg = disk->status_msg;
  re->next = 0;

  if (disk->read_error_head == 0) {
    // create new list
    disk->read_error_head = re;
    disk->read_error_tail = re;
  } else if (disk->read_error_tail->sector != re->sector) {
    // append to list
    disk->read_error_tail->next = re;
    disk->read_error_tail = re;
  } else {
    // discard duplicate
    free(re);
  }
}

void print_read_errors(Disk* disk) {
  iterate_read_errors(disk, &print_read_error);
}
