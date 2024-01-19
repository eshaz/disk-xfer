#include "disk.h"

#ifndef UTILS_H
#define UTILS_H

void print_update(char* prefix, char* message, Disk* disk);

int print_welcome(Disk* disk, double avg_bytes_per_sec);

int interrupt_handler(Disk* disk, double avg_bytes_per_sec);

#endif /* UTILS_H */