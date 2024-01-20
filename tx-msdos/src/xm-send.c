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
#define MAX_READ_RETRY_COUNT 20   // number of times to retry when a read error is encountered
#define READ_RETRY_DELAY_MS  100  // delay introduced when retrying to read
#define DISK_RESET_INTERVAL  2    // interval to reset the disk heads when an error occurs

ProtocolState state=START;

unsigned char block_num=1;
char* buf;
Disk* disk;

/**
 * 1   SOH
 * 1   Block #
 * 1   Block # checksum
 * 512 Data
 * 2   CRC
 * 1   ACK/NAK
*/
unsigned int baud_rate = 9600; // TODO: expose a user parameter
unsigned char overhead_size = 6;
unsigned int sector_size = 512;
double bytes_per_second = 0;
unsigned long start_sector = 0;

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

static int catch_interrupt() {
  if (interrupt_handler(disk, bytes_per_second)) {
    fprintf(stderr, "\nReceived Interrupt. Aborting transfer.\n");
    int14_send_byte(0x18); // CANCEL
    state=END;
    return 1;
  }
  return 0;
}

void clean_up() {
  free_disk(disk);
  free(buf);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start)
{
  start_sector = start;
  bytes_per_second = (double)baud_rate / 8 - overhead_size;
  buf=malloc(sector_size);
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

  set_sector(disk, start_sector);
  print_welcome(disk, bytes_per_second);
  if (!prompt_user("\n\nStart Transfer? [y]: ", 1, 'y')) {
    fprintf(stderr, "\nAborted.");
    return;
  }

  if (int14_init()) {
    fprintf(stderr, "\nWARNING: Failed to initialize serial port.");
    fprintf(stderr, "\nWARNING: You may need to configure the serial port using `mode`.\n");
  }
  fprintf(stderr, "\nRun `rx [serial_port] [file_name]` command on Linux...\n");

  while (1)
    { 
      catch_interrupt();
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
            save_report(disk, start_sector, bytes_per_second);
            goto done;
        }
    }
  
  done:
  clean_up();
}

/**
 * Send CRC START (0x43) character and delay for 3 seconds, polling for SOH.
 */
void xmodem_state_start()
{
  unsigned int wait = 0;
  short wait_time;
  
  while (state==START) {
    fprintf(stderr, "\rWaiting for receiver... %u Seconds", wait);
    wait_time=1000;
    wait++;
    while (wait_time>=0) {
      if (catch_interrupt()) return;
      delay(1);
      wait_time--;

      if (int14_data_waiting()!=0) {
        if (int14_read_byte()=='C') {
          state=BLOCK;
          fprintf(stderr, "\nStarting Transfer.");
          return;
        }
      }
    }
  }
  
}

/**
 * Send an XMODEM-512 block with CRC
 */
void xmodem_state_block(void)
{
  short i=0;
  unsigned int read_retry = 0;
  unsigned short calced_crc;
  unsigned char read_error = int13_read_sector(disk, buf);

  // retry through read errors
  // it's normal to have known bad sectors on older disks
  // attempt to read and send something if it was output
  while (read_error && read_retry <= MAX_READ_RETRY_COUNT) {
    catch_interrupt();

    print_update("\nWarn: ", " Read Error. ", disk);
    fprintf(stderr, "%d", read_retry);
    fprintf(stderr, "\nCode: 0x%2X, %s.\n", disk->status_code, disk->status_msg);

    if (!(read_retry % DISK_RESET_INTERVAL)) {
      int13_reset_disk_system(disk);
    }

    delay(READ_RETRY_DELAY_MS);
    read_error = int13_read_sector(disk, buf);
    read_retry++;
  }
  
  if (read_error)
    {
      // retries failed
      print_update("\nErr : ", " Failed.", disk);
      fprintf(stderr, "\nErr : Data may be corrupted ... ");
      add_read_error(disk);
      int13_reset_disk_system(disk);
      // send whatever was read
      int13_read_sector(disk, buf);
    }
  else
    {
      print_update("\nSend: ", " ... ", disk);
    }

  int14_send_byte(0x01);  // SOH
  int14_send_byte(block_num); // block # (mod 256)
  int14_send_byte(0xFF-block_num); // 0xFF - BLOCK # (simple checksum)

  for (i=0;i<sector_size;i++)     // Send the data
    int14_send_byte(buf[i]);

  calced_crc=xmodem_calc_crc(buf,sector_size);
  int14_send_byte((calced_crc>>8));       // CRC Hi
  int14_send_byte(calced_crc&0xFF);       // CRC Lo

  state=CHECK;
}

/**
 * Wait for ack/nak/cancel from receiver
 */
void xmodem_state_check(void)
{
  unsigned char b;
  if (int14_data_waiting()!=0)
    {
      b=int14_read_byte();
      switch (b)
        {
        case 0x06: // ACK
          fprintf(stderr, "ACK!");
          block_num++;
          block_num&=0xff;
          state=BLOCK;
          if (disk->current_sector >= disk->total_sectors) {
            state=END;
            fprintf(stderr, "\nTransfer complete!");
          } else {
            set_sector(disk, (unsigned long)disk->current_sector + 1); // increment to read the next sector
          }
          break;
        case 0x15: // NAK
          fprintf(stderr, "NAK!");
          state=BLOCK;  // Resend.
          break;
        case 0x18: // CAN
          fprintf(stderr, "CANCEL!");
          state=END;   // end.
          break;
        default:
          fprintf(stderr, "Unknown Byte: 0x%02X: %c",b,b);
        }
    }
}
