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
#include "int14.h"
#include "xm-send.h"

#define BUFFER_SIZE 512

static int atoul(char *in, unsigned long *out) 
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
  unsigned long start_block = 0;
  int error = 0;
  if (argc >= 2) {
    error = atoul(argv[1], &start_block);
    if (error) {
      printf("Usage: tx [start_block]");
      return 1;
    }
  }

  if (int14_init()) {
    printf("WARNING: Failed to initialize serial port.\n");
    printf("WARNING: You may need to configure the serial port using `mode`.\n");
  }
  
  xmodem_send(start_block);
  clean_up();
    
  return 0;
}
