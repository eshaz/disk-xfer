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
#include "xm-send.h"

#define START_DELAY_TIME_MS  3000 // approx 3 secs.
#define BYTE_XMODEM_START    0x43 // C (for CRC)
#define MAX_READ_RETRY_COUNT 20   // number of times to retry when a read error / bad sector is encountered
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

static void catch_interrupt() {
  if (interrupt_handler(disk, bytes_per_second)) {
    printf("\nReceived Interrupt. Aborting transfer.\n");
    int14_send_byte(0x18); // CANCEL
    clean_up();
    exit(1);
  }
}

void clean_up() {
  free_disk(disk);
  free(buf);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start_sector)
{
  bytes_per_second = (double)baud_rate / 8 - overhead_size;
  buf=malloc(sector_size);
  disk=create_disk();

  if (int13_disk_geometry(disk)==1) {
    printf("FATAL: Could not retrieve disk geometry for device 0x%02X! Aborting.\n", disk->device_id);
    clean_up();
    return;
  }

  if (start_sector > disk->total_sectors) {
    printf("FATAL: Start block %lu was greater than device 0x%02X length!\n", start_sector, disk->device_id);
    printf("FATAL: Device is %lu blocks in length. Aborting.\n", disk->total_sectors);
    clean_up();
    return;
  }

  set_sector(disk, start_sector);
  if (print_welcome(disk, bytes_per_second)) return; // user aborted
  
  while (state!=END)
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
            break;
        }
    }
  
  clean_up();
}

/**
 * Send CRC START (0x43) character and delay for 3 seconds, polling for SOH.
 */
void xmodem_state_start()
{
  short wait_time=START_DELAY_TIME_MS;
  
  while (wait_time>0)
    {
      catch_interrupt();
      delay(1);
      wait_time--;
      if (int14_data_waiting()!=0)
        {
          if (int14_read_byte()=='C')
            {
              state=BLOCK;
              printf("Starting Transfer.\n");
              return;
            }
        }
    }
  printf("Waiting for receiver...\n");
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

    print_update("Warn: ", " Read Error. ", disk);
    printf("%d\n", read_retry);
    printf("Code: 0x%2X, %s.\n", disk->status_code, disk->status_msg);

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
      print_update("Err : ", " Failed.\n", disk);
      printf("Err : Data may be corrupted ... ");
      add_bad_sector(disk);
      int13_reset_disk_system(disk);
      // send whatever was read
      int13_read_sector(disk, buf);
    }
  else
    {
      print_update("Send: ", " ... ", disk);
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
          printf("ACK!\n");
          block_num++;
          block_num&=0xff;
          state=BLOCK;
          if (disk->current_sector >= disk->total_sectors) {
            state=END;
            printf("Transfer complete!\n");
          } else {
            set_sector(disk, (unsigned long)disk->current_sector + 1); // increment to read the next sector
          }
          break;
        case 0x15: // NAK
          printf("NAK!\n");
          state=BLOCK;  // Resend.
          break;
        case 0x18: // CAN
          printf("CANCEL!\n");
          state=END;   // end.
          break;
        default:
          printf("Unknown Byte: 0x%02X: %c\n",b,b);
        }
    }
}
