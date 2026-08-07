#pragma once

#include <stddef.h>
#include "esp_lcd_sh8601.h"

#ifdef __cplusplus
extern "C" {
#endif

const sh8601_lcd_init_cmd_t *waveshare_knob_init_commands(void);
size_t waveshare_knob_init_command_count(void);

#ifdef __cplusplus
}
#endif

