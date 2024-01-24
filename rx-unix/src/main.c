/**
 * rx - Receive image from tx
 *
 * Thomas Cherryhomes <thom.cherryhomes@gmail.com>
 *
 * Released under GPL version 3.0
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h> // needed for memset
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>
#include <errno.h>

typedef enum _state { START,
    BLOCK,
    CHECK,
    REBLOCK,
    END } ProtocolState;

#define RX_BUFFER_SIZE 1024 * 16 // max size of tio buffer
#define TX_BUFFER_SIZE 7 // size of the response packet
#define TIMEOUT_S 1 // time in 10ths of seconds to wait for data, then timeout with NAK 255 max
#define BAUD_RATE B115200 // connection baud rate
#define BLOCK_SIZE 517 // 512 + 5 XMODEM-CRC block overhead.

ProtocolState state = START;
int serial_read_fd;
int serial_write_fd;
int outfile_fd;
unsigned char b;
unsigned long block_num = 0;

unsigned char* rx_buffer;
unsigned int rx_buffer_pos;
unsigned char* tx_buffer;
struct winsize w;
unsigned int current_col = 0;

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

/**
 * Send byte
 */
void xmodem_send_byte(unsigned char b)
{
    write(serial_write_fd, &b, 1);
}

static void send_block(unsigned char response)
{
    unsigned short crc;
    char i;
    // ACK or NAK
    tx_buffer[0] = response;
    // current block number incrementing from first block recieved
    tx_buffer[1] = ((unsigned long)block_num >> 24) & 0xff;
    tx_buffer[2] = ((unsigned long)block_num >> 16) & 0xff;
    tx_buffer[3] = ((unsigned long)block_num >> 8) & 0xff;
    tx_buffer[4] = block_num & 0xff;
    // crc
    crc = xmodem_calc_crc(tx_buffer, 5);
    tx_buffer[5] = crc >> 8;
    tx_buffer[6] = crc & 0xff;

    write(serial_write_fd, tx_buffer, 7);
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
    send_block(0x15); // NAK
    print_block_status("N");
}

static void send_ack()
{
    send_block(0x06); // ACK
    print_block_status("A");
}

static void cleanup() {
    free(rx_buffer);
    free(tx_buffer);
    close(outfile_fd);
    close(serial_read_fd);
    close(serial_write_fd);
}

/**
 * xmodem start, send C, switch to BLOCK state
 */
void xmodem_state_start(void)
{
    printf("Sending Ready to Start.\n");
    b = 'C'; // Xmodem CRC start byte.
    write(serial_write_fd, &b, 1); // Write to serial port.
    state = BLOCK; // Ready to start feeding blocks.
}

/**
 * xmodem block - Get XMODEM block into buffer.
 */
void xmodem_state_block(void)
{
    int i = 0;
    int bytes_read = 0;
    int data_to_pull = 0;

    while (i < BLOCK_SIZE && rx_buffer_pos < RX_BUFFER_SIZE) {
        bytes_read = read(serial_read_fd, rx_buffer + rx_buffer_pos, RX_BUFFER_SIZE - rx_buffer_pos);
        if (bytes_read == 0)
            send_nak();

        rx_buffer_pos += bytes_read;
        i += bytes_read;
    }

    fprintf(stderr, "R\b");

    if (rx_buffer_pos == RX_BUFFER_SIZE) {
        fprintf(stderr, "Buffer full!\n");
    }

    state = CHECK;
}

/**
 * xmodem check crc - given buffer, calculate CRC, and compare against
 * stored value in block.
 */
unsigned char xmodem_check_crc(unsigned char* buf)
{
    unsigned char* data_ptr = &buf[3];
    unsigned short crc1;
    unsigned short crc2 = xmodem_calc_crc(data_ptr, 512);

    crc1 = buf[515] << 8;
    crc1 |= buf[516];

    if (crc1 == crc2)
        return 1;
    else {
        return 0;
    }
}

static void handle_error(char* message) {
        fprintf(stderr, "%s %i %s\n", message, errno, strerror(errno));
        cleanup();
        exit(1);
}

/**
 * Block is ok, write it to disk.
 */
void xmodem_write_block_to_disk(char* buf)
{
    char* data_ptr = &buf[3];
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
 * and either send ACK or NAK, return to BLOCK or END.
 */
void xmodem_state_check(void)
{
    int i;
    int offset = 0;
    unsigned char* buf;
    unsigned char block_num_byte;

    // align buffer
    while (offset < rx_buffer_pos - BLOCK_SIZE) {
        buf = rx_buffer + offset;
        block_num_byte = block_num & 0xff;

        // search for valid packets
        if (
            buf[0] == 0x01 && // SOH
            buf[1] == block_num_byte && // block sequence
            buf[1] + buf[2] == 0xFF // checksum
        ) {
            if (xmodem_check_crc(buf)) {
                send_ack();
                block_num++;
                xmodem_write_block_to_disk(buf);

                offset += BLOCK_SIZE;
            } else {
                send_nak();
                // increment to prevent resyncing on this block
                offset++;
                break;
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

    state = BLOCK;
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
        case BLOCK:
            xmodem_state_block();
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
    tio.c_cc[VTIME] = TIMEOUT_S;

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
