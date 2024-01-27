#ifndef CRC_H
#define CRC_H

unsigned long crc32(const void* buf, unsigned long size);

unsigned char check_crc32(const void* buf, unsigned long size, const void* expected_crc_buf);

#endif /* CRC_H */