#ifndef INT1A_H
#define INT1A_H

#define AH_GET_SYSTEM_TIME 0x00

unsigned long int1a_get_system_time();

double int1a_system_ticks_to_seconds(unsigned long ticks);

#endif /* INT13_H */
