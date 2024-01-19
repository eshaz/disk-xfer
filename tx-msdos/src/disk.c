#include <stdlib.h>
#include <stdio.h>
#include "utils.h"
#include "disk.h"

static void iterate_bad_sectors(Disk* disk, void (*operation) (BadSector* bs)) {
  BadSector* bs = disk->bad_sector_head;
  if (bs) {
    do {
      operation(bs);
      bs = bs->next;
    } while (bs);
  }
}

static void print_bad_sector(BadSector* bs) {
    printf(" Block: %lu, Code: 0x%02X, %s.\n", bs->sector, bs->status_code, bs->status_msg);
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
  // bad sector information linked list
  disk->bad_sector_head = 0;
  disk->bad_sector_tail = 0;
  return disk;
}

void free_disk(Disk* disk) {
  iterate_bad_sectors(disk, &free);
  free(disk);
}

void set_sector(Disk* disk, unsigned long sector) {
  disk->position.c = sector / (disk->geometry.s * (disk->geometry.h + 1));
  disk->position.h = (sector / disk->geometry.s) % (disk->geometry.h + 1);
  disk->position.s = 1 + (sector % disk->geometry.s);

  disk->current_sector = sector;
  disk->current_byte = sector*512;
}

void add_bad_sector(Disk* disk) {
  BadSector* bs = malloc(sizeof(BadSector));
  bs->sector = disk->current_sector;
  bs->status_code = disk->status_code;
  bs->status_msg = disk->status_msg;
  bs->next = 0;

  if (disk->bad_sector_head == 0) {
    // create new list
    disk->bad_sector_head = bs;
    disk->bad_sector_tail = bs;
  } else if (disk->bad_sector_tail->sector != bs->sector) {
    // append to list
    disk->bad_sector_tail->next = bs;
    disk->bad_sector_tail = bs;
  } else {
    // discard duplicate
    free(bs);
  }
}

void print_bad_sectors(Disk* disk) {
  iterate_bad_sectors(disk, &print_bad_sector);
}
