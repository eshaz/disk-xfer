#include <conio.h>
#include <stdio.h>
#include <io.h>
#include <fcntl.h>
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

void print_status(Disk* disk, double bytes_per_second) {
  double eta = (double) (disk->total_bytes - disk->current_byte) / bytes_per_second;
  print_separator();
  printf(" SOURCE : 0x%02X, C: drive\n",disk->device_id);
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
  printf(" ETA    : %u Hours, %u Minutes, %lu Seconds @ %.2f kB/S\n",
      (unsigned int)(eta / 60 / 60),
      (unsigned int)(eta / 60) % 60,
      (unsigned long)eta % 60,
      (float)bytes_per_second / 1024
    );
  print_separator();
}

void print_bad_sectors_status(Disk* disk) {
  printf("Bad Sectors...\n");
  print_separator();
  print_bad_sectors(disk);
  print_separator();
}

static void print_help() {
  print_separator();
  printf(" Press `s` for the current status.\n");
  printf(" Press `b` to get the list of bad sectors.\n");
  printf(" Press `CTRL-C` or `ESC` to abort the transfer.\n");
  printf(" Press any other key for this help menu.\n");
  print_separator();
}

void print_welcome(Disk* disk, double bytes_per_second) {
  print_status(disk, bytes_per_second);
  printf("\nBefore starting...\n");
  print_separator();
  printf(" Connect your serial cable from COM1 to your Linux receiver.\n");
  print_separator();
  printf("\nDuring the transfer...\n");
  print_help();
}

int prompt_user(char* msg, char default_yes, char yes_key) {
  char prompt;

  printf(msg);
  prompt = getchar();
  if (prompt == yes_key || (default_yes && prompt == '\n')) {
    return 1;
  }
  return 0;
}

int interrupt_handler(Disk* disk, double bytes_per_second) {
  char prompt;
  char printed_status = 0;
  char printed_help = 0;
  char printed_bad_sectors = 0;

  while (kbhit()) {
    prompt = getch();
    // CTRL-C or ESC
    if (prompt == 3 || prompt == 27) {
      return 1;
    }

    if ((prompt == 's' || prompt == 'S') && !printed_status) {
      printf("\n");
      print_status(disk, bytes_per_second);
      printed_status = 1;
    } else if ((prompt == 'b' || prompt == 'B') && !printed_bad_sectors) {
      printf("\n");
      print_bad_sectors_status(disk);
      printed_bad_sectors = 1;
    } else if (!printed_help) {
      printf("\n");
      print_help();
      printed_help = 1;
    }
  }
  return 0;
}

int save_report(Disk* disk, unsigned long start_sector, double bytes_per_second) {
  int fd = 0;
  unsigned long current_sector = disk->current_sector;
  char path[1024];

  if (prompt_user("\nPress `s` to save a status report, any other key to quit?: ", 0, 's')) {
    printf("\nEnter file path to save report: ");
    scanf("\n%1023[^\n]", path);
    printf("\n");
    /* open a file for output */
    /* replace existing file if it exists */
    fd = open(path,
      O_WRONLY | O_CREAT | O_TRUNC | O_TEXT,
      S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP
    );
  
    if (fd == -1) {
        perror("Unable to open file");
        return 1;
    }
  
    if (dup2(fd, 1) == -1) {
        perror("Unable to read from stdout"); 
        return 1;
    }
  
    printf("\n");
    print_separator();
    printf("Disk Image Report.\n");
    print_separator();

    printf("Started at...\n");
    set_sector(disk, start_sector);
    print_status(disk, bytes_per_second);
    set_sector(disk, current_sector);

    printf("\n");
    printf("Ended at...\n");
    print_status(disk, bytes_per_second);
    printf("\n");
    
    print_bad_sectors_status(disk);
    fflush(stdout);
  
    fd = close(fd);
  } else {
    printf("\nNot saving report.");
  }
  return fd;
}