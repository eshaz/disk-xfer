/**
 * tx - disk-send
 * 
 * BIOS INT 14H (RS-232C) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include <i86.h>
#include <stdio.h>
#include "int14.h"

static union REGS regs;

/**
 * Initialize port
 */
#define SUPPORTED_BAUD_RATES 13
static const unsigned int baud_rates[] = {
  11,
  15,
  30,
  60,
  120,
  240,
  480,
  960,
  1920,
  3840,
  5760,
  7680,
  11520
};
unsigned char int14_init(unsigned long baud_rate)
{
  unsigned char baud = 0;
  baud_rate/=10;
  
  for (; baud < SUPPORTED_BAUD_RATES; baud++)
    if (baud_rates[baud] == baud_rate) break;

  if (baud == SUPPORTED_BAUD_RATES) {
    fprintf(stderr, "Invalid baud rate supplied: %lu", baud_rate*10);
    fprintf(stderr, "\nSupported baud rates:");
    for (baud = 0; baud < SUPPORTED_BAUD_RATES; baud++)
      fprintf(stderr, "\n * %lu", (unsigned long)baud_rates[baud] * 10);
    return 1;
  }

  // setup COM1 port
  if (baud > 9) {
    // FOSSIL Extended line control initialization
    regs.x.dx=0;
    regs.h.ah=0x1E;
    regs.h.cl=(baud/8<<7)|(baud%8); // Init baud rate
    regs.h.ch=3;                    // 8 bits
    regs.h.bh=0;                    // No parity
    regs.h.bl=0;                    // 1 stop bit
    regs.h.al=0;                    // no break
  } else {
    // use normal / FOSSIL initialize
    regs.x.dx=0;           // COM1
    regs.h.ah=0x00;        // Serial initialize
    regs.h.al=0x03 |       // 8 bits
             (0x01<<2) |   // 1 stop bit
             (0x00<<3) |   // No parity
             (baud%8<<5);  // baud
  }
  int86(0x14,&regs,&regs);

  // Load FOSSIL
  if (baud > 7) {
    regs.x.dx=0;    // COM1
    regs.h.ah=0x04; // FOSSIL initialize
    int86(0x14,&regs,&regs);

    if (regs.x.ax!=0x1954) {
      fprintf(stderr, "\nThis PC may not support: %lu baud or the FOSSIL driver may not be installed.", baud_rate*10);
      fprintf(stderr, "\nTry using 9600 baud.");
      return 1;
    }
    
    // Set RTS/CTS flow control
    regs.h.ah = 0x0f;
    regs.h.al = 0x02;
    regs.x.dx = 0;
    int86(0x14,&regs,&regs);
  }

  return 0;
}

/**
 * Send byte
 */
void int14_send_byte(unsigned char b)
{
  regs.x.dx = 0;
  regs.h.al = b;
  regs.h.ah = 0x01;
  int86(0x14,&regs,&regs);
}

/**
 * Get Port Status
 */
short int14_get_status(void)
{
  // Get port status
  regs.x.dx = 0;
  regs.h.al = 0;
  regs.h.ah = 3;
  int86(0x14,&regs,&regs);
  return regs.x.ax;
}

/**
 * Is data waiting?
 * Return 0 if nothing, 1 if data waiting.
 */
unsigned short int14_data_waiting(void)
{
  return (int14_get_status()&0x100);
}

/**
 * Read byte
 */
unsigned char int14_read_byte(void)
{
  regs.x.dx=0;
  regs.h.ah=0x02;
  int86(0x14,&regs,&regs);
  return regs.h.al;
}
