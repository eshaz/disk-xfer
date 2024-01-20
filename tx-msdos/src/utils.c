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
    fprintf(stderr, "%*s%lu", get_number_length(to_align) - get_number_length(to_print), "", to_print);
}

static void print_c_s_h(CHS position, CHS geometry) {
    fprintf(stderr, "C: ");
    print_right_aligned(position.c, geometry.c);
    fprintf(stderr, " H: ");
    print_right_aligned(position.h, geometry.h);
    fprintf(stderr, " S: ");
    print_right_aligned(position.s, geometry.s);
}

static void print_block_progress(Disk* disk) {
    float progress = (float) disk->current_sector / disk->total_sectors * 100;
    fprintf(stderr, "Block ");
    print_right_aligned(disk->current_sector, disk->total_sectors);
    fprintf(stderr, " of ");
    print_right_aligned(disk->total_sectors, disk->total_sectors);
    fprintf(stderr, " (%3.2f %%)", progress);
}

static void print_separator() {
    char i;
    for (i = 0; i < 60; i++) {
        fprintf(stderr, "-");
    }
}

void print_update(
    char* prefix,
    char* message,
    Disk* disk
) {
    fprintf(stderr, prefix);
    print_block_progress(disk);
    fprintf(stderr, " ");
    print_c_s_h(disk->position, disk->geometry);
    fprintf(stderr, message);
}

void print_status(Disk* disk, double bytes_per_second) {
  double eta = (double) (disk->total_bytes - disk->current_byte) / bytes_per_second;
  fprintf(stderr, "\n");
  print_separator();
  fprintf(stderr, "\n SOURCE : 0x%02X, C: drive\n",disk->device_id);
  print_separator();
  fprintf(stderr, "\n START  : Byte: ");
  print_right_aligned(disk->current_byte, disk->total_bytes);
  fprintf(stderr, " | Block: ");
  print_right_aligned(disk->current_sector, disk->total_sectors);
  fprintf(stderr, " | ");
  print_c_s_h(disk->position, disk->geometry);
  fprintf(stderr, "\n END    : Byte: ");
  print_right_aligned(disk->total_bytes, disk->total_bytes);
  fprintf(stderr, " | Block: ");
  print_right_aligned(disk->total_sectors, disk->total_sectors);
  fprintf(stderr, " | ");
  print_c_s_h(disk->geometry, disk->geometry);
  fprintf(stderr, "\n");
  print_separator();
  fprintf(stderr, "\n ETA    : %u Hours, %u Minutes, %lu Seconds @ %.2f kB/S",
      (unsigned int)(eta / 60 / 60),
      (unsigned int)(eta / 60) % 60,
      (unsigned long)eta % 60,
      (float)bytes_per_second / 1024
    );
  fprintf(stderr, "\n");
  print_separator();
}

void print_read_errors_status(Disk* disk) {
  fprintf(stderr, "\nRead Errors...\n");
  print_separator();
  fprintf(stderr, "\n");
  print_read_errors(disk);
  print_separator();
}

static void print_help() {
  fprintf(stderr, "\n");
  print_separator();
  fprintf(stderr, "\n Press `s` for the current status.");
  fprintf(stderr, "\n Press `e` to get the list of read errors.");
  fprintf(stderr, "\n Press `CTRL-C` or `ESC` to abort the transfer.");
  fprintf(stderr, "\n Press any other key for this help menu.\n");
  print_separator();
}

void print_welcome(Disk* disk, double bytes_per_second) {
  fprintf(stderr, "Disk Image Summary...");
  print_status(disk, bytes_per_second);
  fprintf(stderr, "\n\nBefore starting...\n");
  print_separator();
  fprintf(stderr, "\n Connect your serial cable from COM1 to your Linux receiver.\n");
  print_separator();
  fprintf(stderr, "\n\nDuring the transfer...");
  print_help();
}

int prompt_user(char* msg, char default_yes, char yes_key) {
  char prompt;

  fprintf(stderr, msg);
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
  char printed_read_errors = 0;

  while (kbhit()) {
    prompt = getch();
    // CTRL-C or ESC
    if (prompt == 3 || prompt == 27) {
      return 1;
    }

    if ((prompt == 's' || prompt == 'S') && !printed_status) {
      print_status(disk, bytes_per_second);
      printed_status = 1;
    } else if ((prompt == 'e' || prompt == 'E') && !printed_read_errors) {
      print_read_errors_status(disk);
      printed_read_errors = 1;
    } else if (!printed_help) {
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
    fprintf(stderr, "\nEnter file path to save report: ");
    scanf("\n%1023[^\n]", path);
    fprintf(stderr, "\n");
    /* open a file for output */
    /* replace existing file if it exists */
    fd = open(path,
      O_WRONLY | O_CREAT | O_TRUNC | O_TEXT,
      S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP
    );
  
    if (fd == -1) {
        perror("\nUnable to open file");
        return 1;
    }
  
    if (dup2(fd, 2) == -1) {
        perror("\nUnable to read from stderr"); 
        return 1;
    }
  
    fprintf(stderr, "Disk Image Report.");

    fprintf(stderr, "\n\nStarted at...");
    set_sector(disk, start_sector);
    print_status(disk, bytes_per_second);
    set_sector(disk, current_sector);

    fprintf(stderr, "\n\nEnded at...");
    print_status(disk, bytes_per_second);
    fprintf(stderr, "\n");
    
    print_read_errors_status(disk);
    fflush(stderr);
  
    fd = close(fd);
  } else {
    fprintf(stderr, "\nNot saving report.");
  }
  return fd;
}