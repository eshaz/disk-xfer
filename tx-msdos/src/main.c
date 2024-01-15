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
#include "xmodem-send.h"

#define BUFFER_SIZE 512

static int atoui(char *in, unsigned int *out) 
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
  unsigned int start_sector = 0;
  int error = 0;
  if (argc >= 2) {
    error = atoui(argv[1], &start_sector);
    if (error) {
      printf("Usage: tx start_sector\n");
      return 1;
    }
  }

  error = int14_init();
  if (error) {
    printf("Failed to initialize serial port\n");
    return 1;
  }
  printf("serial port initialized.\n");
  
  xmodem_send(start_sector);
    
  return 0;
}
