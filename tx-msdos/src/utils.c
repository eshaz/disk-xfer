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

static void print_drive_summary(Disk* disk) {
  fprintf(stderr, "\n SOURCE : 0x%02X, C: drive",disk->device_id);
}

static void print_start_blocks(Disk* disk) {
  fprintf(stderr, "\n START  : Byte: ");
  print_right_aligned(disk->current_byte, disk->total_bytes);
  fprintf(stderr, " | Block: ");
  print_right_aligned(disk->current_sector, disk->total_sectors);
  fprintf(stderr, " | ");
  print_c_s_h(disk->position, disk->geometry);
}

static void print_end_blocks(Disk* disk) {
  fprintf(stderr, "\n END    : Byte: ");
  print_right_aligned(disk->total_bytes, disk->total_bytes);
  fprintf(stderr, " | Block: ");
  print_right_aligned(disk->total_sectors, disk->total_sectors);
  fprintf(stderr, " | ");
  print_c_s_h(disk->geometry, disk->geometry);
}

static void print_elapsed(Disk* disk, double time, double bytes_per_second) { 
  fprintf(stderr, "\n Elapsed: %u Hours, %u Minutes, %lu Seconds",
    (unsigned int)(time / 60 / 60),
    (unsigned int)(time / 60) % 60,
    (unsigned long)time % 60
  );
  if (bytes_per_second != -1) {
    fprintf(stderr, " @ %.2f B/s", bytes_per_second);
  }
}

static void print_estimated(Disk* disk, double bytes_per_second) {
  double time = (double) (disk->total_bytes - disk->current_byte) / bytes_per_second;

  fprintf(stderr, "\n ETA    : %u Hours, %u Minutes, %lu Seconds @ %.2f B/s",
    (unsigned int)(time / 60 / 60),
    (unsigned int)(time / 60) % 60,
    (unsigned long)time % 60,
    bytes_per_second
  );
}

void print_status(Disk* disk, double bytes_per_second, double time_elapsed) {
  fprintf(stderr, "\n");
  print_separator();
  print_drive_summary(disk);
  fprintf(stderr, "\n");

  print_separator();
  print_start_blocks(disk);
  print_end_blocks(disk);
  fprintf(stderr, "\n");

  print_separator();
  print_estimated(disk, bytes_per_second);
  fprintf(stderr, "\n");

  print_separator();
  print_elapsed(disk, time_elapsed, (double)-1);
  fprintf(stderr, "\n");

  print_separator();
}

void print_read_logs_status(Disk* disk) {
  fprintf(stderr, "\nRead Log...\n");
  print_separator();
  print_read_logs(disk);
  fprintf(stderr, "\n");
  print_separator();
}

static void print_help() {
  fprintf(stderr, "\n");
  print_separator();
  fprintf(stderr, "\n Press `s` for the current status.");
  fprintf(stderr, "\n Press `l` to show the read log.");
  fprintf(stderr, "\n Press `ESC` to abort the transfer.");
  fprintf(stderr, "\n Press any other key for this help menu.\n");
  print_separator();
}

void print_welcome(Disk* disk, double bytes_per_second) {
  fprintf(stderr, "Disk Image Summary...");
  fprintf(stderr, "\n");
  print_separator();
  print_drive_summary(disk);
  fprintf(stderr, "\n");

  print_separator();
  print_start_blocks(disk);
  print_end_blocks(disk);
  fprintf(stderr, "\n");

  print_separator();
  print_estimated(disk, bytes_per_second);
  fprintf(stderr, "\n");
  print_separator();

  fprintf(stderr, "\n\nBefore starting...\n");
  print_separator();
  fprintf(stderr, "\n Connect your serial cable from COM1 to your Linux receiver.\n");
  print_separator();
  fprintf(stderr, "\n\nDuring the transfer...");
  print_help();
}

int prompt_user(char* msg, char default_yes, char yes_key) {
  char prompt;

  fflush(stdin);
  fprintf(stderr, msg);
  prompt = getchar();
  if (prompt == yes_key || (default_yes && prompt == '\n')) {
    return 1;
  }
  return 0;
}

int interrupt_handler(Disk* disk, double bytes_per_second, double time_elapsed) {
  char prompt;
  char printed_status = 0;
  char printed_help = 0;
  char printed_read_logs = 0;

  while (kbhit()) {
    prompt = getch();
    // CTRL-C or ESC
    if (prompt == 3 || prompt == 27) {
      return 1;
    }

    if ((prompt == 's' || prompt == 'S') && !printed_status) {
      print_status(disk, bytes_per_second, time_elapsed);
      printed_status = 1;
    } else if ((prompt == 'l' || prompt == 'L') && !printed_read_logs) {
      print_read_logs_status(disk);
      printed_read_logs = 1;
    } else if (!printed_help) {
      print_help();
      printed_help = 1;
    }
  }
  return 0;
}

static void print_report(Disk* disk, unsigned long start_sector, double bytes_per_second, double time_elapsed) {
  CHS geometry = disk->geometry;
  CHS position = disk->position;
  unsigned long current_sector = disk->current_sector;

  fprintf(stderr, "Disk Image Report for...\n");
  print_separator();
  print_drive_summary(disk);
  print_elapsed(disk, time_elapsed, bytes_per_second);
  fprintf(stderr, "\n");
  print_separator();

  // set position to start to show requested image
  set_sector(disk, start_sector);
  fprintf(stderr, "\n\nRequested Image...\n");
  print_separator();
  print_start_blocks(disk);
  print_end_blocks(disk);
  fprintf(stderr, "\n");
  print_separator();
  
  // set position to show end of copy
  // manually change geometry to print the correct values for the end
  disk->geometry = position;
  disk->total_bytes = disk->current_byte;
  disk->total_sectors = current_sector;

  fprintf(stderr, "\n\nTransferred Image...\n");
  print_separator();
  print_start_blocks(disk);
  print_end_blocks(disk);
  fprintf(stderr, "\n");
  print_separator();

  // put everything back
  set_geometry(disk, geometry);
  set_sector(disk, current_sector);

  fprintf(stderr, "\n\nBlocks Sent...\n");
  print_separator();
  print_update("\n ", "\n", disk);
  print_separator();
  fprintf(stderr, "\n");

  print_read_logs_status(disk);
  fflush(stderr);
}

void save_report(Disk* disk, unsigned long start_sector, double bytes_per_second, double time_elapsed) {
  int fd = 0;
  int stderr_copy = 0;
  int error = 0;
  char path[1024];

  while (prompt_user("\nPress `s` to save a status report, any other key to quit?: ", 0, 's')) {
    fprintf(stderr, "\nEnter file path to save report: ");
    scanf("\n%1023[^\n]", path);

    fd = open(path,
      O_WRONLY | O_CREAT | O_TRUNC | O_TEXT,
      S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP
    );
  
    if (fd < 0) {
        fprintf(stderr, "\nUnable to open file");
        continue;
    }
  
    stderr_copy = dup(2);
    if (dup2(fd, 2) < 0) {
        fprintf(stderr, "\nUnable to read from stderr"); 
        break;
    }
    
    print_report(disk, start_sector, bytes_per_second, time_elapsed);

    if (dup2(stderr_copy, 2) < 0) {
      fprintf(stderr, "\nUnable to replace stderr"); 
      break;
    }
    error = close(fd);
    close(stderr_copy);

    if (error) {
      fprintf(stderr, "\nError writing report. Try again?");
    } else {
      return;
    }
  }
  fprintf(stderr, "\nNot saving report.");
}