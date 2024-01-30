#ifndef CRC_H
#define CRC_H

unsigned int crc32(const void* buf, unsigned int size);

unsigned char check_crc32(const void* buf, unsigned int size, const void* expected_crc_buf);

#endif /* CRC_H */