#include "disk.h"

#ifndef UTILS_H
#define UTILS_H

int prompt_user(char* msg, char default_yes, char yes_key);

void print_update(char* prefix, char* message, Disk* disk);

void print_welcome(Disk* disk, double estimated_bytes_per_second);

void print_status(Disk* disk, unsigned char* hash);

void print_read_logs_status(Disk* disk);

int interrupt_handler(Disk* disk, unsigned long start_sector);

void save_report(Disk* disk, unsigned char* hash, unsigned long start_sector);

void update_time_elapsed(Disk* disk, unsigned long start_sector);

void* malloc_with_check(unsigned long size);

#endif /* UTILS_H */