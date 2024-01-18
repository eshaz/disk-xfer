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
#include <conio.h>
#include <stdio.h>
#include <stdlib.h>
#include "xm-send.h"

#define START_DELAY_TIME_MS  3000 // approx 3 secs.
#define BYTE_XMODEM_START    0x43 // C (for CRC)
#define MAX_READ_RETRY_COUNT 20 // number of times to retry when a read error / bad sector is encountered
#define READ_RETRY_DELAY_MS  15 // delay introduced when retrying to read

ProtocolState state=START;

unsigned char block_num=1;
char* buf;
CHS* geometry;
CHS* read_position;

unsigned long current_block = 0;
unsigned long total_blocks = 0;
unsigned long total_bytes = 0;
unsigned int baud_rate = 9600; // TODO: expose a user parameter
unsigned char device_id = 0x80; // TODO: expose a user parameter
unsigned long bits_per_second = 0;

char prompt;

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

static void print_status() {
  unsigned long total_seconds = (total_blocks - current_block) * 512 * 8 / bits_per_second;
  printf("\n");
  print_separator();
  printf(" START  : Byte: ");
  print_right_aligned(current_block * 512, total_bytes);
  printf(" | Block: ");
  print_right_aligned(current_block, total_blocks);
  printf(" | ");
  print_c_s_h(read_position, geometry);
  printf("\n END    : Byte: ");
  print_right_aligned(total_bytes, total_bytes);
  printf(" | Block: ");
  print_right_aligned(total_blocks, total_blocks);
  printf(" | ");
  print_c_s_h(geometry, geometry);
  printf("\n");
  print_separator();
  printf(" ETA    : %d Hours, %d Minutes, %d Seconds @ %.2f kB/S\n",
      (int)(total_seconds / 60 / 60),
      (int)(total_seconds / 60) % 60,
      (int)total_seconds % 60,
      (float)bits_per_second / 8 / 1024
    );
  print_separator();
}

static void print_help() {
  printf("\n");
  print_separator();
  printf(" Press `s` for the current status.\n");
  printf(" Press `CTRL-C` or `ESC` to abort the transfer.\n");
  printf(" Press any other key for this help menu.\n");
  print_separator();
}

static void print_welcome() {
  print_separator();
  printf(" SOURCE : 0x%02X, C: drive",device_id);
  print_status();
  printf("\nBefore starting...\n");
  print_separator();
  printf(" 1. Connect your serial cable.\n");
  printf(" 2. Start up `rx [serial_port] [file_name]` on Linux...\n");
  print_separator();
  printf("\nDuring the transfer...");
  print_help();
}

static int prompt_to_continue() {
  printf("\nStart Transfer? [y]: ");
  prompt = getchar();
  if (prompt != 'y' && prompt != 'Y' && prompt != '\n') {
    printf("\nAborted.");
    return 1;
  }
  return 0;
}

static void interrupt_handler() {
  char printed_status = 0;
  char printed_help = 0;

  while (kbhit()) {
    prompt = getch();
    if (prompt == 3 || prompt == 27) {
      printf("\nReceived Interrupt. Aborting transfer.\n");
      int14_send_byte(0x18); // CANCEL
      clean_up();
      exit(1);
    }

    if ((prompt == 's' || prompt == 'S') && !printed_status) {
      print_status();
      printed_status = 1;
    } else if (!printed_help) {
      print_help();
      printed_help = 1;
    }
  }
}

void clean_up() {
  free(geometry);
  free(read_position);
  free(buf);
}

/**
 * XMODEM-512 send file - main entrypoint.
 */
void xmodem_send(unsigned long start_block)
{
  buf=malloc(512);
  geometry=malloc(sizeof(CHS));
  geometry->c = 0;
  geometry->h = 0;
  geometry->s = 0;
  read_position=malloc(sizeof(CHS));
  read_position->c = 0;
  read_position->h = 0;
  read_position->s = 1;

  if (int13_disk_geometry(geometry)==1)
    {
      printf("FATAL: Could not retrieve disk geometry for device 0x%02X! Aborting.\n", device_id);
      free(buf);
      return;
    }

  total_blocks = (unsigned long)geometry->c * geometry->h * geometry->s;

  // increment disk geometry until the desired block is reached
  while (current_block<start_block)
    {
      interrupt_handler();
      xmodem_set_next_sector();
      if (state == END) {
        printf("FATAL: Start block %lu was greater than device 0x%02X length!\n", start_block, device_id);
        printf("FATAL: Device is %d blocks in length. Aborting.\n", total_blocks);
        free(buf);
        return;
      }
      current_block++;
    }
  
  bits_per_second = baud_rate - 8 * 4; // baud rate + 1x Checksum, 2x CRC, 1x ACK
  total_bytes = (total_blocks - current_block) * 512;

  print_welcome();
  if (prompt_to_continue()) return;
  
  while (state!=END)
    {
      interrupt_handler();
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
 * Send CRC START (0x43) character and delay for 3 seconds, waiting for SOH.
 */
void xmodem_state_start()
{
  short wait_time=START_DELAY_TIME_MS;
  
  while (wait_time>0)
    {
      interrupt_handler();
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
  unsigned char read_error = int13_read_sector(read_position, buf);

  // retry through read errors
  // it's normal to have known bad sectors on older disks
  // TODO: save / display a report that lists all the bad sectors after transfer completes
  while (read_error && read_retry <= MAX_READ_RETRY_COUNT) {
    interrupt_handler();
    read_retry++;
    print_update("Warn: ", "Read Error. Retrying ", geometry, read_position, current_block, total_blocks);
    printf("%2d\r", read_retry);

    delay(READ_RETRY_DELAY_MS);
    read_error = int13_read_sector(read_position, buf);
  }
  
  if (read_error)
    {
      // retries failed
      // send NULL bytes
      print_update("Err:  ", "Read Error. Limit Reached.\n", geometry, read_position, current_block, total_blocks);
      printf("Err : Sending NULL ... ");

      for (i=0;i<512;i++) // Send NULL
        buf[i] = 0;
    }
  else
    {
      print_update("Send: ", " ... ", geometry, read_position, current_block, total_blocks);
    }

  int14_send_byte(0x01);  // SOH
  int14_send_byte(block_num); // block # (mod 256)
  int14_send_byte(0xFF-block_num); // 0xFF - BLOCK # (simple checksum)

  for (i=0;i<512;i++)     // Send the data
    int14_send_byte(buf[i]);

  calced_crc=xmodem_calc_crc(buf,512);
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
          xmodem_set_next_sector();  // so if we're at end, it can be overridden.
          current_block++;
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

/**
 * Set next current_position.s (in response to ACK)
 */
void xmodem_set_next_sector(void)
{
  if (read_position->s >= geometry->s)
    {
      read_position->s=1;
      if (read_position->h >= geometry->h)
        {
          read_position->h=0;
          if (read_position->c > geometry->c)
            state=END;
          else
            read_position->c++;
        }
      else
        read_position->h++;
    }
  else
    read_position->s++;
}
