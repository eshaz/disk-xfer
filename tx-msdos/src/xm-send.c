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
unsigned char hash[16] = {0};
md5_ctx* md5;

unsigned char* rx_buffer;
const char rx_buffer_size = 9;
unsigned char rx_buffer_pos;

unsigned char is_fossil = 0;
unsigned int abort_timeout = 0;
unsigned int resend_timeout = 0;
unsigned char resent = 0;

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
void xmodem_send(unsigned long start, unsigned long baud_rate)
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
    disk = create_disk();

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

    if (int14_init(baud_rate, &is_fossil)) {
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
            } else if (abort_timeout < ABORT_TIMEOUT_MS && read_blocks != completed_blocks) {
                delay(1);
                abort_timeout++;
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

    if ((rx_buffer[0] == ACK || rx_buffer[0] == NAK || rx_buffer[0] == SYN) && check_crc32(rx_buffer, 5, rx_buffer + 5)) {
        // clear the buffer for the next read
        rx_buffer_pos = 0;
        
        // synced on valid packet
        rx_block_num = 0;
        rx_block_num |= (unsigned long)rx_buffer[1] << 24;
        rx_block_num |= (unsigned long)rx_buffer[2] << 16;
        rx_block_num |= (unsigned int)rx_buffer[3] << 8;
        rx_block_num |= rx_buffer[4];

        rx_packet->response_code = rx_buffer[0];
        rx_packet->block_num = rx_block_num;
    
        //if (rx_packet->block_num < completed_blocks) {
            //skip
        //} else {
            return 1;
        //}
    } else {
        // continue syncing
        for (i = 1; i < rx_buffer_size; i++)
            rx_buffer[i - 1] = rx_buffer[i];

        rx_buffer_pos--;
        goto read;
    }

    return 0;
}

static void flush_receive_buffer() {
    while (int14_data_waiting())
        int14_read_byte();
}

/**
 * Send CRC START (0x43) character and delay for 3 seconds, polling for SOH.
 */
void xmodem_state_start()
{
    unsigned int wait = 0;
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

            if (int14_data_waiting() != 0) {
                if (int14_read_byte() == 'C') {
                    set_state(SEND);
                    fprintf(stderr, "\nStarting Transfer!\n");
                    delay(100);
                    flush_receive_buffer();
                    update_time_elapsed(disk, start_sector);
                    return;
                }
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
    unsigned char* buf;

    unsigned long calced_crc;
    unsigned char read_error;
    unsigned long data_written;
    unsigned char read_count = 0;

    unsigned char* retry_bit;
    short byte;

    // get tx packet if it's buffered
    current_packet_block = ((unsigned long)disk->current_sector - start_sector);

    tx_packet = tx_packets[current_packet_block % MAX_BUFFERED_SEND_PACKETS];
    tx_packet_current_block = 0;
    tx_packet_current_block |= (unsigned long)tx_packet->block0 << 24;
    tx_packet_current_block |= (unsigned long)tx_packet->block1 << 16;
    tx_packet_current_block |= (unsigned int)tx_packet->block2 << 8;
    tx_packet_current_block |= tx_packet->block3;

    packet_ptr = (unsigned char*)tx_packet;
    buf = &(tx_packet->data);

    // only read this block if we don't have it buffered
    // validate the block checksum so uninitialized blocks are not considered buffered
    if (tx_packet_current_block != current_packet_block) {
        // read the data
        read_error = int13_read_sector(disk, buf);
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
                    retry_bit[0] += (buf[byte] & 0x01);
                    retry_bit[1] += ((buf[byte] >> 1) & 0x01);
                    retry_bit[2] += ((buf[byte] >> 2) & 0x01);
                    retry_bit[3] += ((buf[byte] >> 3) & 0x01);
                    retry_bit[4] += ((buf[byte] >> 4) & 0x01);
                    retry_bit[5] += ((buf[byte] >> 5) & 0x01);
                    retry_bit[6] += ((buf[byte] >> 6) & 0x01);
                    retry_bit[7] += ((buf[byte] >> 7) & 0x01);
                }

                update_read_status(read_count);
                // reset the disk periodically to reposition the drive heads for a successful read
                if (!(read_count % DISK_RESET_INTERVAL)) {
                    int13_reset_disk_system(disk);
                } else {
                    delay(READ_RETRY_DELAY_MS);
                }

                read_error = int13_read_sector(disk, buf);
                read_count++;
            }

            if (read_error) {
                // retries failed
                fprintf(stderr, "E");

                // set the sent data to the consensus (average) of each bit in the read sectors
                for (byte = 0; byte < sector_size; byte++) {
                    retry_bit = retry_bits + byte * 8;
                    buf[byte] = 0;
                    buf[byte] |= (retry_bit[0] >= (MAX_READ_RETRY_COUNT / 2));
                    buf[byte] |= ((retry_bit[1] >= (MAX_READ_RETRY_COUNT / 2)) << 1);
                    buf[byte] |= ((retry_bit[2] >= (MAX_READ_RETRY_COUNT / 2)) << 2);
                    buf[byte] |= ((retry_bit[3] >= (MAX_READ_RETRY_COUNT / 2)) << 3);
                    buf[byte] |= ((retry_bit[4] >= (MAX_READ_RETRY_COUNT / 2)) << 4);
                    buf[byte] |= ((retry_bit[5] >= (MAX_READ_RETRY_COUNT / 2)) << 5);
                    buf[byte] |= ((retry_bit[6] >= (MAX_READ_RETRY_COUNT / 2)) << 6);
                    buf[byte] |= ((retry_bit[7] >= (MAX_READ_RETRY_COUNT / 2)) << 7);
                }
            } else {
                // send the most recent read, and disregard any retry data
                update_read_status(read_count);
            }

            flush_receive_buffer();
        }

        tx_packet->soh_byte = SOH;
        tx_packet->block0 = ((unsigned long)current_packet_block >> 24) & 0xff;
        tx_packet->block1 = ((unsigned long)current_packet_block >> 16) & 0xff;
        tx_packet->block2 = ((unsigned long)current_packet_block >> 8) & 0xff;
        tx_packet->block3 = current_packet_block & 0xff;

        calced_crc = crc32(packet_ptr, sizeof(SendPacket) - 4);
        tx_packet->crc0 = ((unsigned long)calced_crc >> 24) & 0xff;
        tx_packet->crc1 = ((unsigned long)calced_crc >> 16) & 0xff;
        tx_packet->crc2 = ((unsigned long)calced_crc >> 8) & 0xff;
        tx_packet->crc3 = calced_crc & 0xff;

        md5_process_block(
            tx_packet->data,
            sector_size,
            md5
        );

        read_blocks++;
    }

    if (is_fossil) {
        data_written = 0;
        while (data_written < sizeof(SendPacket)) {
            data_written += int14_write_block((char*)packet_ptr + data_written, sizeof(SendPacket) - data_written);
        }
    } else {
        for (byte = 0; byte < sizeof(SendPacket); byte++) {
            int14_send_byte(packet_ptr[byte]);
        }
    }

    //fprintf(stderr, "sent %lu.", current_packet_block);
    resend_timeout = 0;

    set_state(CHECK);
}

// 1 if there are more blocks to complete
// 0 if everything is complete
static unsigned char set_complete(unsigned long rx_block) {
    completed_blocks = rx_block;

    if ((unsigned long) completed_blocks + start_sector >= disk->total_sectors) {
        fprintf(stderr, "\nTransfer complete!");
        set_state(END);
        return 0;
    } else {
        //fprintf(stderr, "increment complete %lu %lu.", rx_block, completed_blocks);
        return 1;
    }
}

// 1 if position was incremented
// 0 if position was not incremented
static unsigned char read_next_block() {
    signed int buffer_size = read_blocks - completed_blocks;

    if ((buffer_size < MAX_BUFFERED_SEND_PACKETS) && state != ABORT) {
        current_blocks++;
        set_sector(disk, current_blocks + start_sector);
        //fprintf(stderr, "increment position %lu %lu %lu %d.", read_blocks, current_blocks, completed_blocks, buffer_size);
        return 1;
    } else {
        //fprintf(stderr, "no increment position %lu %lu %lu %d.\n", read_blocks, current_blocks, completed_blocks, buffer_size);
        return 0;
    }
}

// 1 if position was set
// 0 if position was not set
static unsigned char set_position(unsigned long new_position) {
    SendPacket* tx_packet;
    unsigned long tx_block_num;

    tx_packet = tx_packets[new_position % MAX_BUFFERED_SEND_PACKETS];
    tx_block_num = 0;
    tx_block_num |= (unsigned long)tx_packet->block0 << 24;
    tx_block_num |= (unsigned long)tx_packet->block1 << 16;
    tx_block_num |= (unsigned int)tx_packet->block2 << 8;
    tx_block_num |= tx_packet->block3;

    if (tx_block_num != new_position) {
        fprintf(stderr, "\nBuffer Overload, hash will be incorrect. Have: %lu Need: %lu\n", tx_block_num, rx_packet->block_num);
        exit(1);
        return 0;
    } else {
        current_blocks = new_position;
        set_sector(disk, new_position + start_sector);
        //fprintf(stderr, "set position %lu.", new_position);
    }
    return 1;
}

static void set_state(ProtocolState new_state) {
    if (state != ABORT || new_state == END) {
        state = new_state;
    }
}

//fprintf(stderr, ".N, %lu.", rx_packet->block_num);
/**
 * Wait for ack/nak/cancel from receiver
 */
void xmodem_state_check(void)
{
    if (receive_packets()) {
        if (rx_packet->response_code == NAK) {
            //fprintf(stderr, "\n.N, %lu %lu %lu.", rx_packet->block_num, current_blocks, completed_blocks);
            fprintf(stderr, "N");
        } else if (rx_packet->response_code == ACK) {
            //fprintf(stderr, "\n.A, %lu %lu %lu.", rx_packet->block_num, current_blocks, completed_blocks);
            fprintf(stderr, "A");
        } else if (rx_packet->response_code == SYN) {
            //fprintf(stderr, "\n.S, %lu %lu %lu.", rx_packet->block_num, current_blocks, completed_blocks);
            fprintf(stderr, "S");
        }

        //if (resent) {
        //    // reset position to response packet after a resend
        //    fprintf(stderr, "resent %lu %lu %lu %lu.\n", read_blocks, current_blocks, completed_blocks, rx_packet->block_num);
//
        //    if(set_position(rx_packet->block_num, rx_packet->response_code)) {
        //        set_state(SEND);
        //    } else {
        //        set_state(ABORT);
        //    }
        //    resent = 0;
        //}

        if (rx_packet->response_code == SYN) {
            if(set_position(rx_packet->block_num)) {
                set_state(SEND);
            } else {
                set_state(ABORT);
            }
            set_complete(rx_packet->block_num);
        }
        
        if (rx_packet->block_num < current_blocks) {
            if (rx_packet->response_code == NAK) {
                if(set_position(rx_packet->block_num)) {
                    set_state(SEND);
                } else {
                    set_state(ABORT);
                }
            }
            if (rx_packet->response_code == ACK) {
                if (set_complete(rx_packet->block_num)) {
                    if (read_next_block()) {
                        set_state(SEND);
                    } else {
                        set_state(CHECK);
                    }
                }
            }
        } else if (rx_packet->block_num == current_blocks) {
            if (rx_packet->response_code == NAK) {
                set_state(SEND);
            }
            if (rx_packet->response_code == ACK) {
                if (set_complete(rx_packet->block_num)) {
                    if (read_next_block()) {
                        set_state(SEND);
                    } else {
                        set_state(CHECK);
                    }
                }
            }
        } else {
            // rx_packet > current_blocks
            if (rx_packet->response_code == NAK) {
                if(set_position(rx_packet->block_num)) {
                    set_state(SEND);
                } else {
                    set_state(ABORT);
                }
            }
            if (rx_packet->response_code == ACK) {
                if(set_position(rx_packet->block_num)) {
                    set_state(SEND);
                } else {
                    set_state(ABORT);
                }
            }
        }
    } else {
        // no packet received
        if (read_next_block()) {
            //fprintf(stderr, "no next block");
            set_state(SEND);
        } else {
            if (resend_timeout > RESEND_TIMEOUT_MS) {
                set_state(SEND);
                resend_timeout = 0;
                resent = 1;
            } else {
                delay(1);
                resend_timeout++;
                set_state(CHECK);
            }
        }
    }

/*
has packet?
  yes
    response block < current block
      NAK
        reset position to response
        send block
      ACK
        increment complete
        increment position
        send block
    response block == current block
      NAK
        send block
      ACK
        increment position
        send block
    response block > current block
      NAK
        reset position
        send block
      ACK
        reset position
        send block
  no
    increment block
      0 state = SEND
      1 state = CHECK


*/
    
}
