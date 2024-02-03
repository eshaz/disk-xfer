/**
 * tx - disk-send
 *
 * main routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include "md5.h"
#include "utils.h"
#include "xm-send.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma code_seg("utils");
static char atoul(char* in, unsigned long* out)
{
    char* p;

    for (p = in; *p; p++)
        if (*p > '9' || *p < '0')
            return 1;

    *out = strtoul(in, NULL, 10);
    return 0;
}

#pragma code_seg("utils");
static int verify_md5()
{
    const unsigned char data[64] = "This sentence should be exactly (64) sixty four bytes in length.";
    const unsigned char expected[16] = { 0x25, 0xb1, 0x60, 0x07, 0x88, 0x8d, 0x2d, 0x3c, 0x29, 0x5a, 0x24, 0x1e, 0x53, 0xf9, 0xb6, 0x7c };
    unsigned char actual[16] = { 0 };
    md5_ctx* md5 = malloc_with_check(sizeof(md5_ctx));

    md5_init_ctx(md5);
    md5_process_block(data, 64, md5);
    md5_finish_ctx(md5, actual);
    free(md5);

    return memcmp(expected, actual, 16);
}

int main(int argc, char* argv[])
{
    // start from a sector if we left off
    char drive_letter = 'C';
    unsigned long start_sector = 0;
    unsigned long baud = 115200;
    char error = 0;
    if (argc >= 2)
        drive_letter = argv[1][0];
    if (argc >= 3)
        error += atoul(argv[2], &start_sector);
    if (argc >= 4)
        error += atoul(argv[3], &baud);
    if (error) {
        fprintf(stderr, "\nUsage: tx [drive] [start_sector] [baud]");
        fprintf(stderr, "\n\nDefaults:");
        fprintf(stderr, "\n* [drive]             `C` drive to transfer");
        fprintf(stderr, "\n* [start_sector]      `0` sector to start transfer");
        fprintf(stderr, "\n* [baud]         `115200` baud rate to set for COM1");
        return 1;
    }
    if (verify_md5())
        fprintf(stderr, "WARN: MD5 hashing does not work with this build!\n");
    xmodem_send(drive_letter, start_sector, baud);
    clean_up();

    return 0;
}
