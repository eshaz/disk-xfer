#ifndef INT1A_H
#define INT1A_H

#define AH_GET_SYSTEM_TIME 0x00

void int1a_get_system_time(double* seconds_since_midnight, unsigned char* midnight_rollover_since_last_read);

#endif /* INT13_H */