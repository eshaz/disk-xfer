/**
 * tx - disk-send
 *
 * XMODEM-512 (512K block) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include "xm-send.h"
#include "crc.h"
#include "int14.h"
#include "md5.h"
#include "utils.h"
#include <i86.h>
#include <stdio.h>
#include <stdlib.h>

#define BYTE_XMODEM_START 0x43 // C (for CRC)
#define MAX_READ_RETRY_COUNT 128 // number of times to retry when a read error is encountered (up to 255)
#define READ_RETRY_DELAY_MS 100 // delay introduced when retrying to read
#define DISK_RESET_INTERVAL 2 // interval to reset the disk heads when an error occurs
#define MAX_BUFFERED_SEND_PACKETS 4 // number of blocks permitted to be buffered (recommend 8, we'll only send a max of MAX_read_blocks / 2, but keep 4 extra in case of a NAK that goes further back)
#define ABORT_TIMEOUT_MS 1000 // Time in milliseconds to spend flushing the buffer when the user aborts the transfer
#define RESEND_TIMEOUT_MS 100 // Time in milliseconds to wait to resend packets after no response from receive

#define MAX(a, b) a > b ? a : b

ProtocolState state = START;

SendPacket* tx_packets[MAX_BUFFERED_SEND_PACKETS];
ReceivePacket* rx_packet;
Disk* disk;

unsigned long completed_blocks = 0;
unsigned long current_blocks = 0;
unsigned long read_blocks = 0;
unsigned char hash[16] = { 0 };
md5_ctx* md5;

unsigned char* rx_buffer;
const char rx_buffer_size = 9;
unsigned char rx_buffer_pos;

unsigned int abort_timeout = 0;
unsigned int resend_timeout = 0;

/**
 * 1   SOH
 * 4   Block #
 * 512 Data
 * 4   CRC
 */
unsigned int sector_size = 512; // may be different if disk geometry specifies something else
unsigned long start_sector = 0;
unsigned char* retry_bits;

static char catch_interrupt()
{
    if (interrupt_handler(disk, start_sector)) {
        fprintf(stderr, "\nReceived Interrupt. Aborting transfer.\n");
        set_state(ABORT);
        return 1;
    }
    return 0;
}

static void update_read_status(unsigned char read_count)
{
    if (disk->status_code) {
        // there is an error
        if (
            disk->read_log_tail == 0 || // read log is empty
            disk->read_log_tail->status_code != disk->status_code || // error status is different
            disk->read_log_tail->sector != disk->current_sector // error sector is different
        ) {
            // new error, add to the read log
            fprintf(stderr, ".Error: 0x%02X, %s.", disk->status_code, disk->status_msg);
            add_read_log(disk, read_count);
        } else {
            // same error, update the retry count
            update_read_log(disk, read_count);
        }
    } else if (read_count > 0) {
        // there is a success, but only after retrying
        fprintf(stderr, ".Recovered: 0x%02X, %s.", disk->status_code, disk->status_msg);
        add_read_log(disk, read_count);
    } else {
        // there is a success, and no retries, don't log
    }
}

void clean_up()
{
    unsigned char i;
    for (i = 0; i < MAX_BUFFERED_SEND_PACKETS; i++)
        free(tx_packets[i]);

    free(rx_packet);
    free_disk(disk);
    free(retry_bits);
    free(rx_buffer);
    free(md5);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(char drive_letter, unsigned long start, unsigned long baud_rate)
{
    // ring buffer for sent data
    unsigned char i;
    for (i = 0; i < MAX_BUFFERED_SEND_PACKETS; i++) {
        tx_packets[i] = malloc_with_check(sizeof(SendPacket));
        // initialize to invalid packet so it does not appear buffered
        tx_packets[i]->block0 = 0xff;
        tx_packets[i]->block1 = 0xff;
        tx_packets[i]->block2 = 0xff;
        tx_packets[i]->block3 = 0xff;
    }

    // initialize to invalid packet so it does not appear buffered
    rx_packet = malloc_with_check(sizeof(ReceivePacket));
    rx_packet->response_code = 0xFF;
    rx_packet->block_num = ~0UL;

    // ring buffer for recieve data
    rx_buffer = malloc_with_check(rx_buffer_size);
    rx_buffer_pos = 0;

    // retry buffer
    retry_bits = malloc_with_check(sector_size * 8);

    // disk structure
    disk = create_disk(drive_letter);

    // md5 hash
    md5 = malloc_with_check(sizeof(md5_ctx));
    md5_init_ctx(md5);

    start_sector = start;

    if (int13_disk_geometry(disk) == 1) {
        fprintf(stderr, "\nFATAL: Could not retrieve disk geometry for device 0x%02X! Aborting.", disk->device_id);
        clean_up();
        return;
    }

    if (start_sector > disk->total_sectors) {
        fprintf(stderr, "\nFATAL: Start block %lu was greater than device 0x%02X length!", start_sector, disk->device_id);
        fprintf(stderr, "\nFATAL: Device is %lu blocks in length. Aborting.", disk->total_sectors);
        clean_up();
        return;
    }

    if (int14_init(baud_rate)) {
        fprintf(stderr, "\nFATAL: Failed to initialize serial port.");
        clean_up();
        return;
    }

    set_sector(disk, start_sector);
    print_welcome(disk, (double)baud_rate / 9 / sizeof(SendPacket) * sector_size); // effective baud rate = 8 bits - 1 stop bit
    if (!prompt_user("\n\nStart Transfer? [y]: ", 1, 'y')) {
        fprintf(stderr, "\nAborted.");
        return;
    }
    fprintf(stderr, "\nRun `rx [serial_port] [file_name]` command on Linux...\n");

    while (1) {
        catch_interrupt();
        // update time every once in a while to avoid midnight rollover issues
        if (!(disk->current_sector & 0xFF))
            update_time_elapsed(disk, start_sector);
        switch (state) {
        case START:
            xmodem_state_start();
            break;
        case SEND:
            xmodem_state_send();
            break;
        case ABORT:
            if (state == START) {
                set_state(END);
                break;
            } else if (
                abort_timeout < ABORT_TIMEOUT_MS && // aborts timed out
                read_blocks - completed_blocks != 1 // all blocks are sent
            ) {
                delay(1);
                abort_timeout++;
                // continue to check to send buffered blocks
            } else {
                set_state(END);
                break;
            }
        case CHECK:
            xmodem_state_check();
            break;
        case REBLOCK:
        case END:
            update_time_elapsed(disk, start_sector);
            md5_finish_ctx(md5, hash);
            print_status(disk, hash);
            save_report(disk, hash, start_sector);
            clean_up();
            return;
        }
    }
}

static void flush_receive_buffer()
{
    while (int14_read_block(rx_buffer, rx_buffer_size)) { }
}

/**
 * Send CRC START (0x43) character and delay for 3 seconds, polling for SOH.
 */
void xmodem_state_start()
{
    unsigned int wait = 0;
    char start_token;
    short wait_time;

    fprintf(stderr, "\nWaiting for receiver.");
    while (state == START) {
        wait_time = 1000;
        wait++;
        while (wait_time >= 0) {
            if (catch_interrupt())
                return;
            delay(1);
            wait_time--;

            int14_read_block(&start_token, 1);

            if (start_token == 'C') {
                set_state(SEND);
                fprintf(stderr, "\nStarting Transfer!\n");
                delay(100);
                flush_receive_buffer();
                update_time_elapsed(disk, start_sector);
                return;
            }
        }
        fprintf(stderr, ".");
    }
}

/**
 * Send an XMODEM-512 block with CRC
 */
void xmodem_state_send(void)
{
    SendPacket* tx_packet;
    unsigned long current_packet_block;
    unsigned long tx_packet_current_block;
    unsigned char* packet_ptr;
    unsigned char* data;

    unsigned long calced_crc;
    unsigned char read_error;
    unsigned long data_written;
    unsigned char read_count = 0;

    unsigned char* retry_bit;
    short byte;
    unsigned char bit;

    // get tx packet if it's buffered
    current_packet_block = ((unsigned long)disk->current_sector - start_sector);

    tx_packet = tx_packets[current_packet_block % MAX_BUFFERED_SEND_PACKETS];

    packet_ptr = (unsigned char*)tx_packet;
    tx_packet_current_block = buf_to_ul(packet_ptr + 1);
    data = &(tx_packet->data);

    // only read this block if we don't have it buffered
    if (tx_packet_current_block != current_packet_block) {
        // read the data
        read_error = int13_read_sector(disk, data);
        read_count++;

        // retry on error
        if (read_error) {
            // clear out retry buffer
            memset(retry_bits, 0, sector_size * 8);

            // gather samples of each failed block read
            while (read_error && read_count <= MAX_READ_RETRY_COUNT && read_count != 0xFF) {
                if (catch_interrupt())
                    return;

                // add the previous read result into this buffer
                for (byte = 0; byte < sector_size; byte++) {
                    retry_bit = retry_bits + byte * 8;
                    for (bit = 0; bit < 8; bit++) {
                        retry_bit[bit] += ((data[byte] >> bit) & 0x01);
                    }
                }

                update_read_status(read_count);
                // reset the disk periodically to reposition the drive heads for a successful read
                if (!(read_count % DISK_RESET_INTERVAL)) {
                    int13_reset_disk_system(disk);
                } else {
                    delay(READ_RETRY_DELAY_MS);
                }

                read_error = int13_read_sector(disk, data);
                read_count++;
            }

            if (read_error) {
                // retries failed
                fprintf(stderr, "E");

                // set the sent data to the consensus (average) of each bit in the read sectors
                for (byte = 0; byte < sector_size; byte++) {
                    retry_bit = retry_bits + byte * 8;
                    data[byte] = 0;
                    for (bit = 0; bit < 8; bit++) {
                        data[byte] |= ((retry_bit[bit] >= (MAX_READ_RETRY_COUNT / 2)) << bit);
                    }
                }
            } else {
                // send the most recent read, and disregard any retry data
                update_read_status(read_count);
            }

            // clear out any packets received while retrying
            flush_receive_buffer();
        }

        tx_packet->soh_byte = SOH;
        ul_to_buf(current_packet_block, packet_ptr + 1);

        calced_crc = crc32(packet_ptr, sizeof(SendPacket) - 4);
        ul_to_buf(calced_crc, packet_ptr + sizeof(SendPacket) - 4);

        if (read_blocks > current_packet_block) {
            fprintf(stderr, "\nFATAL: Re-reading a block, hash will be incorrect. Read %lu. Rereading %lu.", read_blocks, current_packet_block);
            set_state(END);
        } else {
            md5_process_block(tx_packet->data, sector_size, md5);
            read_blocks++;
        }
    }

    data_written = 0;
    do {
        data_written += int14_write_block((char*)packet_ptr + data_written, sizeof(SendPacket) - data_written);
    } while (data_written < sizeof(SendPacket));

    // successful send
    resend_timeout = 0;
    set_state(CHECK);
}

// 1 if there are more blocks to complete
// 0 if everything is complete (no more blocks left to read)
static unsigned char set_complete_block(unsigned long rx_block)
{
    completed_blocks = rx_block;

    if ((unsigned long)completed_blocks + start_sector >= disk->total_sectors) {
        fprintf(stderr, "\nTransfer complete!");
        set_state(END);
        return 0;
    } else {
        // fprintf(stderr, "increment complete %lu %lu.", rx_block, completed_blocks);
        return 1;
    }
}

// 1 if position was set
// 0 if position was not set (a block was skiped)
static unsigned char set_current_block(unsigned long new_position)
{
    if (
        new_position > (unsigned long)read_blocks + 1 && // skip a block
        read_blocks + start_sector < disk->total_sectors // not complete
    ) {
        fprintf(stderr, "\nFATAL: Cannot skip a block. Read: %lu Skipping: %lu", read_blocks, rx_packet->block_num);
        set_state(END);
        return 0;
    } else {
        current_blocks = new_position;
        set_sector(disk, new_position + start_sector);
    }

    return 1;
}

// 1 if position was incremented
// 0 if position was not incremented (buffer being full)
static unsigned char read_next_block()
{
    signed int buffer_size = read_blocks - completed_blocks;

    if ((buffer_size < MAX_BUFFERED_SEND_PACKETS) && state != ABORT) {
        current_blocks++;
        return set_current_block(current_blocks);
        // fprintf(stderr, "increment position %lu %lu %lu %d.", read_blocks, current_blocks, completed_blocks, buffer_size);
    } else {
        // fprintf(stderr, "no increment position %lu %lu %lu %d.\n", read_blocks, current_blocks, completed_blocks, buffer_size);
        return 0;
    }
}

static void set_state(ProtocolState new_state)
{
    if (state != ABORT || new_state == END) {
        state = new_state;
    }
}

/**
 * Read incoming ACK / NAK / SYN packets
 *
 */
static unsigned char receive_packets()
{
    unsigned long rx_block_num;
    unsigned char i;
    unsigned char bytes_read = 0;

// fill the buffer
read:
    while (rx_buffer_pos < rx_buffer_size) {
        bytes_read = int14_read_block(rx_buffer + rx_buffer_pos, rx_buffer_size - rx_buffer_pos);
        if (bytes_read == 0)
            // not enough data to form a packet
            return 0;

        rx_buffer_pos += bytes_read;
    }

    if (
        (rx_buffer[0] == ACK || rx_buffer[0] == NAK || rx_buffer[0] == SYN) && // valid packet
        check_crc32(rx_buffer, 5, rx_buffer + 5) // valid crc
    ) {
        // clear the buffer for the next read
        rx_buffer_pos = 0;

        // synced on valid packet
        rx_block_num = buf_to_ul(rx_buffer + 1);

        rx_packet->response_code = rx_buffer[0];
        rx_packet->block_num = rx_block_num;

        return 1;
    } else {
        // continue syncing
        for (i = 1; i < rx_buffer_size; i++)
            rx_buffer[i - 1] = rx_buffer[i];

        rx_buffer_pos--;
        goto read;
    }

    return 0;
}

/**
 * Synchronize data stream using sliding window
 * ACK -> Block is acknoledged and saved to disk on the receiver.
 * NAK -> Block is not acknowledged and needs to be resent.
 * SYN -> Data is out of sync, SYN block will indicate the last ACK'd block
 *        so the data can be re-wound, re-sent, or fast-forwarded to this block.
 */
void xmodem_state_check(void)
{
    if (receive_packets()) {
        // packet recieved
        if (rx_packet->response_code == ACK) {
            fprintf(stderr, "A");

            // record ACK'd block as complete
            if (set_complete_block(rx_packet->block_num)) {
                if (rx_packet->block_num <= current_blocks) {
                    if (read_next_block()) {
                        // buffer is not full, send next block
                        set_state(SEND);
                    } else {
                        // buffer is full, don't send any more
                        set_state(CHECK);
                    }
                } else {
                    // rx_packet > current_blocks
                    // resend this block _without_ checking the buffer since, this and prior blocks were previously ACK'd.
                    if (set_current_block(rx_packet->block_num)) {
                        set_state(SEND);
                    } else {
                        // this block will result in a skipped block
                        set_state(ABORT);
                    }
                }
            } else {
                // no more blocks to send
                set_state(END);
            }
        } else if (rx_packet->response_code == SYN) {
            fprintf(stderr, "S");

            // send the next block _without_ checking the buffer since this block was ACK'd
            if (set_current_block(rx_packet->block_num + 1)) {
                // record this block as complete
                if (set_complete_block(rx_packet->block_num)) {
                    // send the next block
                    set_state(SEND);
                } else {
                    set_state(END);
                }
            } else {
                set_state(ABORT);
            }
        } else { // if (rx_packet->response_code == NAK) {
            fprintf(stderr, "N");

            // set the current block to the one received,
            if (set_current_block(rx_packet->block_num)) {
                // so it can be resent
                set_state(SEND);
            } else {
                set_state(ABORT);
            }
        }
    } else {
        // no packet received
        if (read_next_block()) {
            // buffer is not full, send more data
            set_state(SEND);
        } else {
            // buffer is full,
            if (resend_timeout > RESEND_TIMEOUT_MS) {
                // checked for packets, but nothing was received, resend the last packet
                set_state(SEND);
                resend_timeout = 0;
            } else {
                // continue to check for more packets before resending
                delay(1);
                resend_timeout++;
                set_state(CHECK);
            }
        }
    }
}
