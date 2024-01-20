#include <stdlib.h>
#include <stdio.h>
#include "utils.h"
#include "disk.h"

static void iterate_read_logs(Disk* disk, void (*operation) (ReadLog* rl)) {
  ReadLog* rl = disk->read_log_head;
  if (rl) {
    do {
      operation(rl);
      rl = rl->next;
    } while (rl);
  }
}

static void print_read_log(ReadLog* rl) {
    fprintf(stderr, "\n Block: %lu, Retry Count: %3u, Code: 0x%02X, %s.", rl->sector, rl->retry_count, rl->status_code, rl->status_msg);
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
  // read log information linked list
  disk->read_log_head = 0;
  disk->read_log_tail = 0;
  return disk;
}

void free_disk(Disk* disk) {
  iterate_read_logs(disk, &free);
  free(disk);
}

void set_sector(Disk* disk, unsigned long sector) {
  disk->position.c = sector / (disk->geometry.s * (disk->geometry.h + 1));
  disk->position.h = (sector / disk->geometry.s) % (disk->geometry.h + 1);
  disk->position.s = 1 + (sector % disk->geometry.s);

  disk->current_sector = sector;
  disk->current_byte = sector*512;
}

static ReadLog* create_read_log(Disk* disk, unsigned char retry_count) {
  ReadLog* rl = malloc(sizeof(ReadLog));
  rl->sector = disk->current_sector;
  rl->status_code = disk->status_code;
  rl->status_msg = disk->status_msg;
  rl->retry_count = retry_count;
  rl->next = 0;
  return rl;
}

void add_read_log(Disk* disk, unsigned char retry_count) {
  ReadLog* rl = create_read_log(disk, retry_count);

  if (disk->read_log_head == 0) {
    // create new list
    disk->read_log_head = rl;
    disk->read_log_tail = rl;
  } else {
    // append to list
    disk->read_log_tail->next = rl;
    disk->read_log_tail = rl;
  }
}

void update_read_log(Disk* disk, unsigned char retry_count) {
  ReadLog* rl = disk->read_log_tail;
  
  if (disk->read_log_head == 0) {
    ReadLog* rl = create_read_log(disk, retry_count);
    disk->read_log_head = rl;
    disk->read_log_tail = rl;
  }

  rl->retry_count=retry_count;
}

void print_read_logs(Disk* disk) {
  iterate_read_logs(disk, &print_read_log);
}
