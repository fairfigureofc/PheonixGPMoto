#pragma once

#include <LovyanGFX.hpp>

class PheonixDisplay : public lgfx::LGFX_Device {
  lgfx::Panel_ILI9341 panel;
  lgfx::Bus_SPI bus;
  lgfx::Light_PWM backlight;

 public:
  PheonixDisplay() {
    {
      auto config = bus.config();
      config.spi_host = VSPI_HOST;
      config.spi_mode = 0;
      config.freq_write = 40000000;
      config.freq_read = 16000000;
      config.spi_3wire = false;
      config.use_lock = true;
      config.dma_channel = 1;
      config.pin_sclk = 14;
      config.pin_mosi = 13;
      config.pin_miso = 12;
      config.pin_dc = 2;
      bus.config(config);
      panel.setBus(&bus);
    }
    {
      auto config = panel.config();
      config.pin_cs = 15;
      config.pin_rst = -1; // Shared with ESP32 EN on the E32R28T.
      config.pin_busy = -1;
      config.panel_width = 240;
      config.panel_height = 320;
      config.memory_width = 240;
      config.memory_height = 320;
      config.readable = true;
      config.invert = false;
      config.rgb_order = false;
      config.dlen_16bit = false;
      config.bus_shared = false;
      panel.config(config);
    }
    {
      auto config = backlight.config();
      config.pin_bl = 21;
      config.invert = false;
      config.freq = 44100;
      config.pwm_channel = 7;
      backlight.config(config);
      panel.setLight(&backlight);
    }
    setPanel(&panel);
  }
};
