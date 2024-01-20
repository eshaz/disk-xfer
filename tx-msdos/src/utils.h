#include "disk.h"

#ifndef UTILS_H
#define UTILS_H

int prompt_user(char* msg, char default_yes, char yes_key);

void print_update(char* prefix, char* message, Disk* disk);

void print_welcome(Disk* disk, double bytes_per_second);

void print_status(Disk* disk, double bytes_per_second);

void print_read_logs_status(Disk* disk);

int interrupt_handler(Disk* disk, double bytes_per_second);

void save_report(Disk* disk, unsigned long start_sector, double bytes_per_second);

#endif /* UTILS_H */