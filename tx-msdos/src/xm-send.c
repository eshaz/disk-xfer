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
#define MAX_READ_RETRY_COUNT 32 // number of times to retry when a read error is encountered (up to 255)
#define READ_RETRY_DELAY_MS 100 // delay introduced when retrying to read
#define DISK_RESET_INTERVAL 1 // interval to reset the disk heads when an error occurs
#define MAX_BUFFERED_BLOCKS 4 // number of blocks permitted to be buffered (Linux terminal interfaces allows up to 4096 bytes)

ProtocolState state = START;

SendPacket* tx_packet;
ReceivePacket* rx_packet;
Disk* disk;

unsigned char* rx_buffer;
const char rx_buffer_size = 6;
unsigned char rx_buffer_pos;

unsigned char is_fossil = 0;

/**
 * 1   SOH
 * 1   Block #
 * 1   Block # checksum
 * 512 Data
 * 2   CRC
 * 1   ACK/NAK
 */
unsigned char overhead_size = 6;
unsigned int sector_size = 512;
unsigned long start_sector = 0;

static char catch_interrupt()
{
    if (interrupt_handler(disk, start_sector)) {
        fprintf(stderr, "\nReceived Interrupt. Aborting transfer.\n");
        state = END;
        return 1;
    }
    return 0;
}

static void update_read_status(unsigned char retry_count)
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
            add_read_log(disk, retry_count);
        } else {
            // same error, update the retry count
            update_read_log(disk, retry_count);
        }
    } else if (retry_count > 0) {
        // there is a success, but only after retrying
        fprintf(stderr, ".Recovered: 0x%02X, %s.", disk->status_code, disk->status_msg);
        add_read_log(disk, retry_count);
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
    free_disk(disk);
    free(tx_packet);
    free(rx_buffer);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start, unsigned long baud_rate)
{
    start_sector = start;
    // data to send
    tx_packet = malloc(sizeof(SendPacket));
    tx_packet->soh_byte = SOH;
    // data to receieve
    rx_packet = malloc(sizeof(ReceivePacket));
    // buffer for recieve data
    rx_buffer = malloc(rx_buffer_size);
    rx_buffer_pos = 0;
    rx_packet->block_num = 0;

    disk = create_disk();

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
    print_welcome(disk, (double)baud_rate / 9 - overhead_size);
    if (!prompt_user("\n\nStart Transfer? [y]: ", 1, 'y')) {
        fprintf(stderr, "\nAborted.");
        return;
    }
    fprintf(stderr, "\nRun `rx [serial_port] [file_name]` command on Linux...\n");

    while (1) {
        catch_interrupt();
        // update time every once in a while to avoid midnight rollover issues
        if (tx_packet->block == 0)
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
    unsigned char sum = 0;
    unsigned char i = 0;
    unsigned long new_sector;
    unsigned long max_sector;

    if (!(rx_buffer[0] == ACK || rx_buffer[0] == NAK)) {
        return 1;
    }

    // validate checksum
    for (; i < rx_buffer_size; i++)
        sum += (unsigned char)rx_buffer[i];

    if (sum != 0xff) {
        return 1;
    }

    new_sector = (unsigned long)(rx_buffer[1] << 24) | (rx_buffer[2] << 16) | (rx_buffer[3] << 8) | rx_buffer[4];
    max_sector = (unsigned long)disk->total_sectors - start_sector;

    // validate block number
    if (new_sector > max_sector) {
        return 1;
    }

    return 0;
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
    rx_packet->block_num = (unsigned long)(rx_buffer[1] << 24) | (rx_buffer[2] << 16) | (rx_buffer[3] << 8) | rx_buffer[4];

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
    unsigned char* packet_ptr = (unsigned char*)tx_packet;
    unsigned char* buf = &(tx_packet->data);

    short i = 0;
    unsigned short calced_crc;
    unsigned char read_error;
    unsigned long data_written;
    unsigned char retry_count = 0;
    ReadLog* rl;

    // try to read the data
    read_error = int13_read_sector(disk, buf);

    // retry on error
    if (read_error) {
        rl = get_read_log_for_current_sector(disk);
        if (rl) {
            fprintf(stderr, ".not retrying %lu since it was already tried...\n", rl->sector);
        }
        // don't do retry logic if this sector was already tried, just resend it
        if (!(rx_packet->response_code == NAK && rl != NULL)) {
            // retry through errors
            while (read_error && retry_count < MAX_READ_RETRY_COUNT) {
                if (catch_interrupt())
                    return;
        
                update_read_status(retry_count);
                fprintf(stderr, "R\b");
                // reset the disk periodically to reposition the drive heads for a successful read
                if (!(retry_count % DISK_RESET_INTERVAL)) {
                    int13_reset_disk_system(disk);
                }
        
                delay(READ_RETRY_DELAY_MS);
                read_error = int13_read_sector(disk, buf);
                retry_count++;
            }
        
            if (read_error) {
                // retries failed
                fprintf(stderr, "E");
            } else {
                update_read_status(retry_count);
                fprintf(stderr, "S\b");
            }

            // clear out any NAKs received during retries
            while (int14_data_waiting())
                get_receive_packet();
        }
    }
    
    calced_crc = xmodem_calc_crc(buf, sector_size);
    tx_packet->block = (disk->current_sector - start_sector) & 0xff;
    tx_packet->block_checksum = (unsigned char)0xFF - tx_packet->block;
    tx_packet->crc_hi = calced_crc >> 8;
    tx_packet->crc_lo = calced_crc & 0xFF;

    if (is_fossil) {
        data_written = 0;
        while (data_written < sizeof(SendPacket)) {
            data_written += int14_write_block((char*)packet_ptr + data_written, sizeof(SendPacket) - data_written);
        }
    } else {
        for (i = 0; i < sizeof(SendPacket); i++) {
            int14_send_byte(packet_ptr[i]);
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
    } else if ((signed long)disk->current_sector - start_sector - rx_packet->block_num <= MAX_BUFFERED_BLOCKS) {
        // send more data
        state = BLOCK;
    }
}
