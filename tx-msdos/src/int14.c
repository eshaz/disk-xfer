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
#include "int14.h"

static union REGS regs;

/**
 * Initialize port
 */
unsigned char int14_init(unsigned int baud_rate)
{
  unsigned char use_extended_init = 0;
  unsigned char baud;

  switch(baud_rate) {
    case 110: baud=0; break;
    case 150: baud=1; break;
    case 300: baud=2; break;
    case 600: baud=3; break;
    case 1200: baud=4; break;
    case 2400: baud=5; break;
    case 4800: baud=6; break;
    case 9600: baud=7; break;
    case 19200: baud=8; use_extended_init=1; break;
  }

  if (use_extended_init) {
    regs.x.dx=0;    // COM1
    regs.h.ah=0x04; // Extended initialize (for FOSSIL)
    regs.h.cl=baud; // baud
    regs.h.ch=3;    // 8 bits
    regs.h.bh=0;    // No parity
    regs.h.bl=0;    // 1 stop bit
    regs.h.al=0;    // no break
  } else {
    regs.x.dx=0;         // COM1
    regs.h.ah=0x00;      // Serial initialize
    regs.h.al=0x03 |     // 8 bits
             (0x01<<2) | // 1 stop bit
             (0x00<<3) | // No parity
             (baud<<5);  // baud
  }

  int86(0x14,&regs,&regs);

  if (use_extended_init && regs.x.ax!=0x1954)
    return 1;

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
