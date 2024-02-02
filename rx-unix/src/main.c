/**
 * rx - Receive image from tx
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Released under GPL version 3.0
 */

#include "crc.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h> // needed for memset
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

typedef enum _state { START,
    SEND,
    CHECK,
    REBLOCK,
    END } ProtocolState;

#define BLOCK_SIZE 521 // XMODEM-CRC block overhead.
#define RX_BUFFER_SIZE BLOCK_SIZE * 16 // max size of tio buffer
#define TX_BUFFER_SIZE 9 // size of the response packet
#define BAUD_RATE B115200 // connection baud rate
#define READ_DELAY_US (115200 / 9) // amount of time to sleep between reads (allow the serial port buffer to fill)

ProtocolState state = START;
int serial_read_fd;
int serial_write_fd;
int outfile_fd;
unsigned char b;
unsigned int block_num = 0;
unsigned int acked_block = 0;

unsigned char* rx_buffer;
unsigned int rx_buffer_pos;
unsigned char* tx_buffer;
struct winsize w;
unsigned int current_col = 0;

/**
 * Send byte
 */
void xmodem_send_byte(unsigned char b)
{
    write(serial_write_fd, &b, 1);
}

static void send_block(unsigned char response, unsigned int block)
{
    unsigned int crc;
    char i;
    // ACK or NAK
    tx_buffer[0] = response;
    // current block number incrementing from first block recieved
    tx_buffer[1] = ((unsigned int)block >> 24) & 0xff;
    tx_buffer[2] = ((unsigned int)block >> 16) & 0xff;
    tx_buffer[3] = ((unsigned int)block >> 8) & 0xff;
    tx_buffer[4] = block & 0xff;
    // crc
    crc = crc32(tx_buffer, 5);
    tx_buffer[5] = ((unsigned int)crc >> 24) & 0xff;
    tx_buffer[6] = ((unsigned int)crc >> 16) & 0xff;
    tx_buffer[7] = ((unsigned int)crc >> 8) & 0xff;
    tx_buffer[8] = crc & 0xff;

    fprintf(stderr, "send ");
    for (i = 0; i < 9; i++)
        fprintf(stderr, "%02X ", tx_buffer[i]);
    fprintf(stderr, "\n");

    write(serial_write_fd, tx_buffer, TX_BUFFER_SIZE);
}

static void print_block_status(char* status)
{
    fprintf(stderr, status);
    current_col++;
    if (current_col > w.ws_col) {
        fprintf(stderr, "\n");
        current_col = 0;
    }
}

static void send_nak()
{
    send_block(0x15, block_num); // NAK
    print_block_status("N");
}

static void send_ack()
{
    send_block(0x06, block_num); // ACK
    print_block_status("A");
}

static void send_syn()
{
    send_block(0x16, acked_block); // SYN
    print_block_status("S");
}

static void cleanup()
{
    free(rx_buffer);
    free(tx_buffer);
    close(outfile_fd);
    close(serial_read_fd);
    close(serial_write_fd);
}

/**
 * xmodem start, send C, switch to SEND state
 */
void xmodem_state_start(void)
{
    printf("Sending Ready to Start.\n");
    b = 'C'; // Xmodem CRC start byte.
    write(serial_write_fd, &b, 1); // Write to serial port.
    state = SEND; // Ready to start feeding blocks.
}

/**
 * xmodem block - Get XMODEM block into buffer.
 */
void xmodem_state_send(void)
{
    int i = 0;
    int bytes_read = -1;
    int data_to_pull = 0;

    usleep(READ_DELAY_US);
    while (bytes_read != 0 && rx_buffer_pos < RX_BUFFER_SIZE) {
        bytes_read = read(serial_read_fd, rx_buffer + rx_buffer_pos, RX_BUFFER_SIZE - rx_buffer_pos);

        rx_buffer_pos += bytes_read;
        i += bytes_read;
    }

    fprintf(stderr, "R\b");
    //fprintf(stderr, "\nbytes read %u", i);

    if (rx_buffer_pos == RX_BUFFER_SIZE) {
        fprintf(stderr, "Buffer full!\n");
    }

    state = CHECK;
}

static void handle_error(char* message)
{
    fprintf(stderr, "%s %i %s\n", message, errno, strerror(errno));
    cleanup();
    exit(1);
}

/**
 * Block is ok, write it to disk.
 */
void xmodem_write_block_to_disk(char* buf)
{
    char* data_ptr = &buf[5];
    int bytes_written = 0;

    bytes_written = write(outfile_fd, data_ptr, 512);

    if (bytes_written < 0) {
        handle_error("Write error! ");
    }
    if (bytes_written != 512) {
        handle_error("All data was not written! ");
    }
}

/**
 * xmodem check - Check buffer for well formedness
 * and either send ACK or NAK, return to SEND or END.
 */
void xmodem_state_check(void)
{
    int i;
    int offset = 0;
    unsigned char* buf;
    unsigned int rx_block_num;
    unsigned char crc_result;

    //fprintf(stderr, "rx buffer start %u\n", rx_buffer_pos);
    // align buffer
    while (rx_buffer_pos >= offset + BLOCK_SIZE) {
        buf = rx_buffer + offset;

        // search for valid packets on SOH
        if (buf[0] == 0x01) {
            crc_result = check_crc32(buf, BLOCK_SIZE - 4, buf + BLOCK_SIZE - 4);
            
            rx_block_num = 0;
            rx_block_num |= (unsigned int)buf[1] << 24;
            rx_block_num |= (unsigned int)buf[2] << 16;
            rx_block_num |= (unsigned int)buf[3] << 8;
            rx_block_num |= buf[4];

            if (crc_result) {
                // valid block
                //fprintf(stderr, " rx block %u %u ", rx_block_num, block_num);

                if (rx_block_num == block_num) {
                    // blocks are synced
                    send_ack();
                    fprintf(stderr, " %u %u", rx_block_num, block_num);
                    acked_block = block_num;
                    block_num++;
                    xmodem_write_block_to_disk(buf);
                    offset += BLOCK_SIZE;
                } else if (rx_block_num > block_num) {
                    // blocks are not synced
                    if (acked_block == 0 && block_num == 0) {
                        // nothing sent
                        send_nak();
                    } else {
                        send_syn();
                    }
                    //fprintf(stderr, "%s syn %u %u", tx_buffer[0] == 0x06 ? "A" : "N", rx_block_num, block_num);
                    offset += BLOCK_SIZE;
                } else {
                    // rx_block_num < block_num
                    // catching up from previous NAKs
                    send_ack();
                    //fprintf(stderr, " old %u %u", rx_block_num, block_num);
                    offset += BLOCK_SIZE;
                }
            } else {
                // probably aligned, sent NAK
                if (rx_block_num == block_num) {
                    send_nak();
                    //fprintf(stderr, " crc %u %u", rx_block_num, block_num);
                }
                // increment to prevent resyncing on this block
                offset++;
            }
        } else {
            // keep searching
            offset++;
        }
    }

    // shift away the read data
    for (i = 0; i < rx_buffer_pos; i++) {
        rx_buffer[i] = rx_buffer[i + offset];
    }
    rx_buffer_pos -= offset;

    state = SEND;
}

/**
 * Main protocol entry point
 */
int xmodem_receive(char* filename)
{
    unlink(filename);

    outfile_fd = open(
        filename,
        O_CREAT | O_TRUNC | O_WRONLY | S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    if (outfile_fd < 1) {
        handle_error("Failed to open file! ");
    }

    rx_buffer = malloc(RX_BUFFER_SIZE);
    tx_buffer = malloc(TX_BUFFER_SIZE);

    while (state != END) {
        switch (state) {
        case START:
            xmodem_state_start();
            break;
        case SEND:
            xmodem_state_send();
            break;
        case CHECK:
            xmodem_state_check();
            break;
        case REBLOCK:
            break;
        case END:
            break;
        }
    }

    // We're done.
    cleanup();
    return 0;
}

/**
 * Initialize serial port
 */
int termio_init(char* serial_filename)
{
    struct termios tio;
    memset(&tio, 0, sizeof(tio));
    tio.c_iflag = 0;
    tio.c_oflag = 0;
    tio.c_cflag = CS8 | CREAD | CLOCAL;
    tio.c_lflag &= ~ICANON;
    tio.c_lflag &= ~ISIG;
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 0;

    serial_read_fd = open(serial_filename, O_RDONLY);
    serial_write_fd = open(serial_filename, O_WRONLY);
    cfsetospeed(&tio, BAUD_RATE);
    cfsetispeed(&tio, BAUD_RATE);

    tcsetattr(serial_read_fd, TCSANOW, &tio);
    tcsetattr(serial_write_fd, TCSANOW, &tio);
    return 0;
}

/**
 * print args if less than two args on cmd line.
 */
void print_args(void)
{
    printf("rx /dev/ttySx destination_image_name.img\n");
}

int main(int argc, char* argv[])
{
    ioctl(STDERR_FILENO, TIOCGWINSZ, &w);
    // Display args if not provided.
    if (argc != 3) {
        print_args();
        exit(1);
    } else {
        termio_init(argv[1]);
        return xmodem_receive(argv[2]);
    }
}
