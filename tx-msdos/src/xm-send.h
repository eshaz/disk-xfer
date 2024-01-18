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

#ifndef XMODEM_H
#define XMODEM_H

typedef enum _state {START, BLOCK, CHECK, REBLOCK, END} ProtocolState;

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start_block);

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

#endif /* XMODEM_H */

void clean_up();

/**
 * Print helpers
*/
static char get_number_length(unsigned long n) {
    if (n < 10) return 1;
    if (n < 100) return 2;
    if (n < 1000) return 3;
    if (n < 10000) return 4;
    if (n < 100000) return 5;
    if (n < 1000000) return 6;
    if (n < 10000000) return 7;
    if (n < 100000000) return 8;
    if (n < 1000000000) return 9;
    return 10;
}

static void print_right_aligned(unsigned long to_print, unsigned long to_align) {
    printf("%*s%lu", get_number_length(to_align) - get_number_length(to_print), "", to_print);
}

static void print_c_s_h(CHS *position, CHS *geometry) {
    printf("C: ");
    print_right_aligned(position->c, geometry->c);
    printf(" H: ");
    print_right_aligned(position->h, geometry->h);
    printf(" S: ");
    print_right_aligned(position->s, geometry->s);
}

static void print_block_progress(unsigned long current_block, unsigned long total_blocks) {
    float progress = ((float) current_block / total_blocks) * 100.0;
    printf("Block ");
    print_right_aligned(current_block, total_blocks);
    printf(" of ");
    print_right_aligned(total_blocks, total_blocks);
    printf(" (%3.2f %%)", progress);
}

static void print_separator() {
    char i;
    for (i = 0; i < 60; i++) {
        printf("-");
    }
    printf("\n");
}

static void print_update(
    char* prefix,
    char* message,
    CHS *geometry,
    CHS *position,
    unsigned long current_block,
    unsigned long total_blocks
) {
    printf(prefix);
    print_block_progress(current_block, total_blocks);
    printf(" ");
    print_c_s_h(position, geometry);
    printf(message);
}