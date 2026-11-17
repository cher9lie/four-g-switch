#ifndef FOURG_USB_H
#define FOURG_USB_H
#include <stddef.h>
typedef struct fg_usb fg_usb;
fg_usb *fg_open(char *error, size_t capacity);
void fg_close(fg_usb *usb);
int fg_command(fg_usb *usb, const char *command, char *response, size_t capacity, unsigned timeout_ms, char *error, size_t error_capacity);
int fg_command_allowed(const char *command);
int fg_protocol_matches(int mode);
int fg_network_ready(void);
#endif
