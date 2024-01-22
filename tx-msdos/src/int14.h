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
unsigned char int14_init(unsigned long baud_rate, unsigned char* is_fossil);

/**
 * Send byte
 */
void int14_send_byte(unsigned char b);

/**
 * Get Port Status
 */
short int14_get_status(void);

/**
 * Is data waiting?
 * Return 0 if nothing, 1 if data waiting.
 */
unsigned short int14_data_waiting(void);

/**
 * Read byte
 */
unsigned char int14_read_byte(void);

size_t int14_write_block(char* buf, size_t buf_size);

#endif /* INT14_H */
