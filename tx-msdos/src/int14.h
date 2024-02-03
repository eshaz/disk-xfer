/**
 * tx - disk-send
 *
 * BIOS INT 14H (RS-232C) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include <stddef.h>

#ifndef INT14_H
#define INT14_H

/**
 * Initialize port
 */
unsigned char int14_init(unsigned long baud_rate);

unsigned short int14_write_block(char* buf, unsigned short buf_size);

unsigned short int14_read_block(char* buf, unsigned short buf_size);

#endif /* INT14_H */
