#include <conio.h>
#include <stdio.h>
#include "utils.h"

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

static void print_c_s_h(CHS position, CHS geometry) {
    printf("C: ");
    print_right_aligned(position.c, geometry.c);
    printf(" H: ");
    print_right_aligned(position.h, geometry.h);
    printf(" S: ");
    print_right_aligned(position.s, geometry.s);
}

static void print_block_progress(Disk* disk) {
    float progress = (float) disk->current_sector / disk->total_sectors * 100;
    printf("Block ");
    print_right_aligned(disk->current_sector, disk->total_sectors);
    printf(" of ");
    print_right_aligned(disk->total_sectors, disk->total_sectors);
    printf(" (%3.2f %%)", progress);
}

static void print_separator() {
    char i;
    for (i = 0; i < 60; i++) {
        printf("-");
    }
    printf("\n");
}

void print_update(
    char* prefix,
    char* message,
    Disk* disk
) {
    printf(prefix);
    print_block_progress(disk);
    printf(" ");
    print_c_s_h(disk->position, disk->geometry);
    printf(message);
}

static void print_status(Disk* disk, double avg_bytes_per_sec) {
  unsigned long total_seconds = (disk->total_bytes - disk->current_byte) / avg_bytes_per_sec;
  printf("\n");
  print_separator();
  printf(" START  : Byte: ");
  print_right_aligned(disk->current_byte, disk->total_bytes);
  printf(" | Block: ");
  print_right_aligned(disk->current_sector, disk->total_sectors);
  printf(" | ");
  print_c_s_h(disk->position, disk->geometry);
  printf("\n END    : Byte: ");
  print_right_aligned(disk->total_bytes, disk->total_bytes);
  printf(" | Block: ");
  print_right_aligned(disk->total_sectors, disk->total_sectors);
  printf(" | ");
  print_c_s_h(disk->geometry, disk->geometry);
  printf("\n");
  print_separator();
  printf(" ETA    : %d Hours, %d Minutes, %d Seconds @ %.2f kB/S\n",
      (int)(total_seconds / 60 / 60),
      (int)(total_seconds / 60) % 60,
      (int)total_seconds % 60,
      (float)avg_bytes_per_sec / 1024
    );
  print_separator();
}

static void print_bad_sectors_status(Disk* disk) {
  printf("\nBad Sectors...\n");
  print_separator();
  print_bad_sectors(disk);
  print_separator();
}

static void print_help() {
  printf("\n");
  print_separator();
  printf(" Press `s` for the current status.\n");
  printf(" Press `b` to get the list of bad sectors.\n");
  printf(" Press `CTRL-C` or `ESC` to abort the transfer.\n");
  printf(" Press any other key for this help menu.\n");
  print_separator();
}

int print_welcome(Disk* disk, double avg_bytes_per_sec) {
  char prompt;

  print_separator();
  printf(" SOURCE : 0x%02X, C: drive",disk->device_id);
  print_status(disk, avg_bytes_per_sec);
  printf("\nBefore starting...\n");
  print_separator();
  printf(" 1. Connect your serial cable.\n");
  printf(" 2. Start up `rx [serial_port] [file_name]` on Linux...\n");
  print_separator();
  printf("\nDuring the transfer...");
  print_help();
  printf("\nStart Transfer? [y]: ");

  prompt = getchar();
  if (prompt != 'y' && prompt != 'Y' && prompt != '\n') {
    printf("\nAborted.");
    return 1;
  }
  return 0;
}

int interrupt_handler(Disk* disk, double avg_bytes_per_sec) {
  char prompt;
  char printed_status = 0;
  char printed_help = 0;
  char printed_bad_sectors = 0;

  while (kbhit()) {
    prompt = getch();
    if (prompt == 3 || prompt == 27) {
      return 1;
    }

    if ((prompt == 's' || prompt == 'S') && !printed_status) {
      print_status(disk, avg_bytes_per_sec);
      printed_status = 1;
    } else if ((prompt == 'b' || prompt == 'B') && !printed_bad_sectors) {
      print_bad_sectors_status(disk);
      printed_bad_sectors = 1;
    } else if (!printed_help) {
      print_help();
      printed_help = 1;
    }
  }
  return 0;
}