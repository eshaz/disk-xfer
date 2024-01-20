/**
 * tx - disk-send
 * 
 * main routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include <stdio.h>
#include <stdlib.h>
#include "xm-send.h"

#define BUFFER_SIZE 512

static char atoul(char *in, unsigned long *out) 
{
    char *p;

    for(p = in; *p; p++) 
        if (*p > '9' || *p < '0') 
            return 1;

    *out = strtoul(in, NULL, 10);
return 0;
}

int main(int argc, char* argv[])
{
  // start from a sector if we left off
  unsigned long start_sector = 0;
  unsigned long baud = 9600;
  char error = 0;
  if (argc >= 3) {
    error += atoul(argv[2], &baud);
  }
  if (argc == 2) {
    error += atoul(argv[1], &start_sector);
  }
  if (error) {
    fprintf(stderr, "\nUsage: tx [start_sector] [baud]");
    fprintf(stderr, "\n\nDefaults:");
    fprintf(stderr, "\n* [start_sector]    `0` sector to start transfer");
    fprintf(stderr, "\n* [baud]         `9600` baud rate to set for COM1");
    return 1;
  }
  
  xmodem_send(start_sector, baud);
  clean_up();
    
  return 0;
}
