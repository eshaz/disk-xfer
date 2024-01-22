/**
 * tx - disk-send
 * 
 * XMODEM-512 (512K block) routines
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Licensed under GPL Version 3.0
 */

#include <i86.h>
#include <stdio.h>
#include <stdlib.h>
#include "utils.h"
#include "int14.h"
#include "xm-send.h"

#define BYTE_XMODEM_START    0x43 // C (for CRC)
#define MAX_READ_RETRY_COUNT 32   // number of times to retry when a read error is encountered (up to 255)
#define READ_RETRY_DELAY_MS  100  // delay introduced when retrying to read
#define DISK_RESET_INTERVAL  1    // interval to reset the disk heads when an error occurs

ProtocolState state=START;

unsigned char response=0;
Packet* packet;
Disk* disk;

unsigned char is_fossil=0;
size_t data_written = 0;

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

static char catch_interrupt() {
  if (interrupt_handler(disk, start_sector)) {
    fprintf(stderr, "\nReceived Interrupt. Aborting transfer.\n");
    state=END;
    return 1;
  }
  return 0;
}

static void update_read_status(unsigned char retry_count) {
  if (disk->status_code) {
    // there is an error
    if (
      disk->read_log_tail == 0 || // read log is empty
      disk->read_log_tail->status_code != disk->status_code || // error status is different
      disk->read_log_tail->sector != disk->current_sector // error sector is different
    ) {
      // new error, add to the read log
      fprintf(stderr, "\nRead Error: 0x%02X, %s.\n", disk->status_code, disk->status_msg);
      add_read_log(disk, retry_count);
    } else {
      // same error, update the retry count
      update_read_log(disk, retry_count);
    }
  } else if (retry_count > 0) {
    // there is a success, but only after retrying
    fprintf(stderr, "\nError Recovered: 0x%02X, %s.\n", disk->status_code, disk->status_msg);
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

  crc=0;
  while (--count >= 0)
    {
      crc = crc ^ (unsigned short) *ptr++ << 8;
      i=8;
      do {
        if (crc & 0x8000)
          crc = crc << 1 ^ 0x1021;
        else
          crc = crc << 1;
      } while (--i);
    }
  return crc;
}

void clean_up() {
  free_disk(disk);
  free(packet);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start, unsigned long baud_rate)
{
  start_sector = start;
  packet=malloc(sizeof(Packet));
  packet->soh_byte=1;
  packet->block=1;
  
  disk=create_disk();

  if (int13_disk_geometry(disk)==1) {
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

  while (1)
    { 
      catch_interrupt();
      // update time every once in a while to avoid midnight rollover issues
      if (packet->block==0) update_time_elapsed(disk, start_sector);
      switch (state)
        {
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

/**
 * Send CRC START (0x43) character and delay for 3 seconds, polling for SOH.
 */
void xmodem_state_start()
{
  unsigned int wait = 0;
  short wait_time;
  
  fprintf(stderr, "\nWaiting for receiver");
  while (state==START) {
    wait_time=1000;
    wait++;
    while (wait_time>=0) {
      if (catch_interrupt()) return;
      delay(1);
      wait_time--;

      if (int14_data_waiting()!=0) {
        if (int14_read_byte()=='C') {
          state=BLOCK;
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
  char* packet_ptr= (unsigned char*)packet;
  char* buf = &(packet->data);

  short i=0;
  unsigned short calced_crc;
  unsigned char retry_count = 0;
  unsigned char read_error = int13_read_sector(disk, buf);

  // retry through errors
  // it's normal to have known bad sectors on older disks
  // attempt to read and send something if it was written to the buffer
  while (
    response != 0x15 && // don't do retries after a NAK response since the block was already retried
    read_error &&
    retry_count < MAX_READ_RETRY_COUNT
  ) {
    if (catch_interrupt()) return;

    update_read_status(retry_count);
    fprintf(stderr, "R\b");

    if (!(retry_count % DISK_RESET_INTERVAL)) {
      int13_reset_disk_system(disk);
    }

    delay(READ_RETRY_DELAY_MS);
    read_error = int13_read_sector(disk, buf);
    retry_count++;
  }
  
  if (read_error)
    {
      // retries failed
      fprintf(stderr, "E");
    }
  else
    {
      update_read_status(retry_count);
      fprintf(stderr, "S\b");
    }

  calced_crc=xmodem_calc_crc(buf,sector_size);

  packet->block_checksum=0xFF-packet->block;
  packet->crc_hi = calced_crc>>8;
  packet->crc_lo = calced_crc&0xFF;

  if (is_fossil) {
    data_written = 0;
    while(data_written < sizeof(Packet)) {
      data_written += int14_write_block(packet_ptr + data_written, sizeof(Packet) - data_written);
    }
  } else {
    for (i=0; i < sizeof(Packet); i++) {
      int14_send_byte(packet_ptr[i]);
    }
  }

  // discard anything received while this block was being sent
  while (int14_data_waiting()) {
    int14_read_byte();
  }

  state=CHECK;
}

/**
 * Wait for ack/nak/cancel from receiver
 */
void xmodem_state_check(void)
{
  if (int14_data_waiting()!=0) {
    response=int14_read_byte();

    switch (response) {
      case 0x00: break; // no response
      case 0x06: // ACK
        fprintf(stderr, "A");
        if (disk->current_sector >= disk->total_sectors) {
          state=END;
          fprintf(stderr, "\nTransfer complete!");
        } else {
          state=BLOCK;
          packet->block++;
          packet->block&=0xff;
          set_sector(disk, (unsigned long)disk->current_sector + 1); // increment to read the next sector
        }
        break;
      case 0x15: // NAK
        fprintf(stderr, "N");
        delay(50); // wait for receiver to flush buffer
        state=BLOCK;  // Resend.
        break;
      case 0x18: // CAN
        fprintf(stderr, "C");
        state=END;   // end.
        break;
      default:
        fprintf(stderr, "Unknown Byte: 0x%02X: %c",response,response);
    }
  }
}
