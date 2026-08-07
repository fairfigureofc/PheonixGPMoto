#pragma once

#include <LovyanGFX.hpp>

#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"

class PheonixDisplay : public lgfx::LGFX_Sprite {
 public:
  bool init();
  void setBrightness(uint8_t brightness);
  void flush();

 private:
  static bool onColorTransferDone(esp_lcd_panel_io_handle_t panelIO,
                                  esp_lcd_panel_io_event_data_t* eventData,
                                  void* userContext);

  esp_lcd_panel_handle_t panelHandle = nullptr;
  void* transferComplete = nullptr;
  uint16_t* transferBuffer = nullptr;
};
