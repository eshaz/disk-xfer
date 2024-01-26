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
#include "int14.h"
#include "utils.h"
#include <i86.h>
#include <stdio.h>
#include <stdlib.h>

#define BYTE_XMODEM_START 0x43 // C (for CRC)
#define MAX_READ_RETRY_COUNT 128 // number of times to retry when a read error is encountered (up to 255)
#define READ_RETRY_DELAY_MS 100 // delay introduced when retrying to read
#define DISK_RESET_INTERVAL 2 // interval to reset the disk heads when an error occurs
#define MAX_BUFFERED_BLOCKS 8 // number of blocks permitted to be buffered (recommend 8, we'll only send a max of MAX_BUFFERED_BLOCKS / 2, but keep 4 extra in case of a NAK that goes further back)

ProtocolState state = START;

SendPacket* tx_packets[MAX_BUFFERED_BLOCKS];
ReceivePacket* rx_packet;
Disk* disk;

unsigned char* rx_buffer;
const char rx_buffer_size = 7;
unsigned char rx_buffer_pos;
unsigned char is_fossil = 0;

/**
 * 1   SOH
 * 1   Block #
 * 1   Block # checksum
 * 512 Data
 * 2   CRC
 */
unsigned int sector_size = 512; // may be different if disk geometry specifies something else
unsigned long start_sector = 0;
unsigned char* retry_bits;

static char catch_interrupt()
{
    if (interrupt_handler(disk, start_sector)) {
        fprintf(stderr, "\nReceived Interrupt. Aborting transfer.\n");
        state = END;
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

/**
 * Calculate 16-bit CRC
 */
unsigned short xmodem_calc_crc(char* ptr, short count)
{
    unsigned short crc;
    char i;

    crc = 0;
    while (--count >= 0) {
        crc = crc ^ (unsigned short)*ptr++ << 8;
        i = 8;
        do {
            if (crc & 0x8000)
                crc = crc << 1 ^ 0x1021;
            else
                crc = crc << 1;
        } while (--i);
    }
    return crc;
}

void clean_up()
{
    unsigned char i;
    for (i = 0; i < MAX_BUFFERED_BLOCKS; i++)
        free(tx_packets[i]);

    free_disk(disk);
    free(retry_bits);
    free(rx_buffer);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start, unsigned long baud_rate)
{
    // ring buffer for sent data
    unsigned char i;
    for (i = 0; i < MAX_BUFFERED_BLOCKS; i++) {
        tx_packets[i] = malloc(sizeof(SendPacket));
        // initialize to invalid packet so it does not appear buffered
        tx_packets[i]->block = 0;
        tx_packets[i]->block_checksum = 0;
    }

    // ring buffer for recieve data
    rx_buffer = malloc(rx_buffer_size);
    rx_buffer_pos = 0;
    rx_packet->block_num = 0;

    // data to store recieved data
    rx_packet = malloc(sizeof(ReceivePacket));

    // retry buffer
    retry_bits = malloc(8 * sector_size);

    // disk structure
    disk = create_disk();

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
        if (disk->current_sector % 0xff)
            update_time_elapsed(disk, start_sector);
        switch (state) {
        case START:
            xmodem_state_start();
            break;
        case BLOCK:
            xmodem_state_block();
            break;
        case CHECK:
            xmodem_state_check();
            break;
        case REBLOCK:
        case END:
            save_report(disk, start_sector);
            clean_up();
            return;
        }
    }
}

static char validate_receive_packet()
{
    unsigned short crc1;
    unsigned short crc2;

    if (rx_buffer[0] == ACK || rx_buffer[0] == NAK) {
        crc2 = xmodem_calc_crc(rx_buffer, 5);
        crc1 = rx_buffer[5] << 8;
        crc1 |= rx_buffer[6];

        if (crc1 == crc2) {
            return 0;
        }
    }

    return 1;
}

static unsigned char get_receive_packet()
{
    unsigned char i;
    unsigned char bytes_read = 0;

    // fill the current buffer
    while (rx_buffer_pos < rx_buffer_size) {
        bytes_read = int14_read_block(rx_buffer + rx_buffer_pos, rx_buffer_size - rx_buffer_pos);
        if (bytes_read == 0)
            return 0;

        rx_buffer_pos += bytes_read;
    }

    // shift the buffer left and read another byte to resync while response is invalid
    while (validate_receive_packet()) {
        // shift buffer left
        for (i = 1; i < rx_buffer_size; i++)
            rx_buffer[i - 1] = rx_buffer[i];

        rx_buffer_pos = rx_buffer_size - 1;

        bytes_read = int14_read_block(rx_buffer + rx_buffer_size - 1, 1);

        if (bytes_read == 0)
            return 0;
        rx_buffer_pos++;
    }

    // found valid packet, save it
    rx_packet->response_code = rx_buffer[0];
    rx_packet->block_num = 0;
    rx_packet->block_num |= (unsigned long)rx_buffer[1] << 24;
    rx_packet->block_num |= (unsigned long)rx_buffer[2] << 16;
    rx_packet->block_num |= (unsigned int)rx_buffer[3] << 8;
    rx_packet->block_num |= rx_buffer[4];

    // remove this packet from the buffer
    rx_buffer_pos = 0;
    return 1;
}

/**
 * Send CRC START (0x43) character and delay for 3 seconds, polling for SOH.
 */
void xmodem_state_start()
{
    unsigned int wait = 0;
    short wait_time;

    fprintf(stderr, "\nWaiting for receiver");
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
                    state = BLOCK;
                    fprintf(stderr, "\nStarting Transfer!\n");
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
void xmodem_state_block(void)
{
    SendPacket* tx_packet;
    unsigned char next_block;
    unsigned char next_block_checksum;
    unsigned char* packet_ptr;
    unsigned char* buf;

    unsigned short calced_crc;
    unsigned char read_error;
    unsigned long data_written;
    unsigned char read_count = 0;

    unsigned char* retry_bit;
    short byte;

    // get tx packet if it's buffered
    next_block = ((unsigned long)disk->current_sector - start_sector) & 0xFF;
    next_block_checksum = 0xFF - next_block;

    tx_packet = tx_packets[next_block % MAX_BUFFERED_BLOCKS];
    packet_ptr = (unsigned char*)tx_packet;
    buf = &(tx_packet->data);

    // only read this block if we don't have it buffered
    // validate the block checksum so uninitialized blocks are not considered buffered
    if (tx_packet->block != next_block || tx_packet->block_checksum != next_block_checksum) {
        // read the data
        read_error = int13_read_sector(disk, buf);
        read_count++;

        // retry on error
        if (read_error) {
            // clear out retry buffer
            for (byte = 0; byte < sector_size * 8; byte++)
                retry_bits[byte] = 0;

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

                // set the sent data to the average of each bit in the read sectors
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

            // clear out any NAKs received during retries
            while (int14_data_waiting())
                get_receive_packet();
        }

        calced_crc = xmodem_calc_crc(buf, sector_size);
        tx_packet->soh_byte = SOH;
        tx_packet->block = next_block;
        tx_packet->block_checksum = next_block_checksum;
        tx_packet->crc_hi = calced_crc >> 8;
        tx_packet->crc_lo = calced_crc & 0xFF;
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

    if (disk->current_sector < disk->total_sectors) {
        set_sector(disk, (unsigned long)disk->current_sector + 1); // increment to read the next sector
    }

    state = CHECK;
}

/**
 * Wait for ack/nak/cancel from receiver
 */
void xmodem_state_check(void)
{
    unsigned long new_sector;
    if (get_receive_packet()) {
        switch (rx_packet->response_code) {
        case ACK:
            fprintf(stderr, "A");
            if (disk->current_sector >= disk->total_sectors) {
                state = END;
                fprintf(stderr, "\nTransfer complete!");
                update_time_elapsed(disk, start_sector);
                print_status(disk);
            }
            break;
        case NAK:
            new_sector = (unsigned long)start_sector + rx_packet->block_num;
            set_sector(disk, new_sector); // reset to the nak'd block
            fprintf(stderr, "N");
            state = BLOCK; // Resend.
            break;
        default:
            fprintf(stderr, "Unknown Byte: 0x%02X: %c", rx_packet->response_code, rx_packet->response_code);
        }
    } else if ((signed long)disk->current_sector - start_sector - rx_packet->block_num <= MAX_BUFFERED_BLOCKS / 2) {
        // send more data
        state = BLOCK;
    } else {
        // buffering
    }
}
