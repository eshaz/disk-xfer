#include "disk.h"

#ifndef UTILS_H
#define UTILS_H

void print_update(char* prefix, char* message, Disk* disk);

int print_welcome(Disk* disk, double bytes_per_second);

int interrupt_handler(Disk* disk, double bytes_per_second);

#endif /* UTILS_H */