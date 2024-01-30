/**
 * tx - disk-send
 *
 * XMODEM-512 (512K block) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include "disk.h"
#include "int13.h"
#include "int14.h"

#ifndef XMODEM_H
#define XMODEM_H

#define SOH 0x01
#define ACK 0x06
#define NAK 0x15
#define SYN 0x16

typedef enum _state { START,
    SEND,
    CHECK,
    REBLOCK,
    ABORT,
    END } ProtocolState;

/*
length | description
     1 | SOH byte (0x01)
     4 | block #
   512 | data
     2 | CRC
*/
typedef struct {
    unsigned char soh_byte;
    unsigned char block0;
    unsigned char block1;
    unsigned char block2;
    unsigned char block3;
    char data[512];
    unsigned char crc0;
    unsigned char crc1;
    unsigned char crc2;
    unsigned char crc3;
} SendPacket;

typedef struct {
    unsigned char response_code;
    unsigned long block_num;
} ReceivePacket;

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
void xmodem_state_send(void);

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
