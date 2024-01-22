/**
 * tx - disk-send
 * 
 * XMODEM-512 (512K block) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include "int14.h"
#include "int13.h"
#include "disk.h"

#ifndef XMODEM_H
#define XMODEM_H

typedef enum _state {START, BLOCK, CHECK, REBLOCK, END} ProtocolState;

/*
length | description
     1 | SOH byte (0x01)
     1 | block # (mod 256)
     1 | 0xFF - BLOCK # (simple checksum)
   512 | data
     2 | CRC
*/
typedef struct {
  unsigned char soh_byte;
  unsigned char block;
  unsigned char block_checksum;
  char data[512];
  unsigned char crc_hi;
  unsigned char crc_lo;
} Packet;

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start, unsigned long baud);

/**
 * Send CRC START (0x43) character and delay for 3 seconds, waiting for SOH.
 */
void xmodem_state_start();

/**
 * Send an XMODEM-512 block with CRC
 */
void xmodem_state_block(void);

/**
 * Wait for ack/nak/cancel from receiver
 */
void xmodem_state_check(void);

/**
 * Set next sector (in response to ACK)
 */
void xmodem_set_next_sector(void);

void clean_up();

#endif /* XMODEM_H */
