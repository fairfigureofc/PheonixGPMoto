#if defined(PHEONIX_WAVESHARE_KNOB)

#include "waveshare_knob_display.hpp"

#include <Arduino.h>
#include <cstring>

#include "driver/ledc.h"
#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_lcd_sh8601.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "waveshare_panel_init.h"

namespace {
constexpr int kWidth = 360;
constexpr int kHeight = 360;
constexpr int kTransferRows = 20;
constexpr int kLCDClock = 13;
constexpr int kLCDData0 = 15;
constexpr int kLCDData1 = 16;
constexpr int kLCDData2 = 17;
constexpr int kLCDData3 = 18;
constexpr int kLCDChipSelect = 14;
constexpr int kLCDReset = 21;
constexpr int kBacklight = 47;
}  // namespace

bool PheonixDisplay::onColorTransferDone(
    esp_lcd_panel_io_handle_t, esp_lcd_panel_io_event_data_t*, void* userContext) {
  auto* display = static_cast<PheonixDisplay*>(userContext);
  BaseType_t higherPriorityTaskWoken = pdFALSE;
  xSemaphoreGiveFromISR(static_cast<SemaphoreHandle_t>(display->transferComplete),
                        &higherPriorityTaskWoken);
  return higherPriorityTaskWoken == pdTRUE;
}

bool PheonixDisplay::init() {
  setColorDepth(16);
  setPsram(true);
  if (createSprite(kWidth, kHeight) == nullptr) {
    Serial.println("Unable to allocate the 360x360 display canvas in PSRAM");
    return false;
  }

  transferComplete = xSemaphoreCreateBinary();
  transferBuffer = static_cast<uint16_t*>(heap_caps_malloc(
      kWidth * kTransferRows * sizeof(uint16_t), MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL));
  if (transferComplete == nullptr || transferBuffer == nullptr) {
    Serial.println("Unable to allocate the display transfer buffer");
    return false;
  }

  spi_bus_config_t busConfig =
      SH8601_PANEL_BUS_QSPI_CONFIG(kLCDClock, kLCDData0, kLCDData1, kLCDData2,
                                  kLCDData3, kWidth * kTransferRows * 2);
  ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &busConfig, SPI_DMA_CH_AUTO));

  esp_lcd_panel_io_spi_config_t ioConfig =
      SH8601_PANEL_IO_QSPI_CONFIG(kLCDChipSelect, onColorTransferDone, this);
  ioConfig.trans_queue_depth = 1;
  esp_lcd_panel_io_handle_t ioHandle = nullptr;
  ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi(
      static_cast<esp_lcd_spi_bus_handle_t>(SPI2_HOST), &ioConfig, &ioHandle));

  sh8601_vendor_config_t vendorConfig = {};
  vendorConfig.init_cmds = waveshare_knob_init_commands();
  vendorConfig.init_cmds_size = waveshare_knob_init_command_count();
  vendorConfig.flags.use_qspi_interface = 1;

  esp_lcd_panel_dev_config_t panelConfig = {};
  panelConfig.reset_gpio_num = kLCDReset;
  panelConfig.rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB;
  panelConfig.bits_per_pixel = 16;
  panelConfig.vendor_config = &vendorConfig;

  ESP_ERROR_CHECK(esp_lcd_new_panel_sh8601(ioHandle, &panelConfig, &panelHandle));
  ESP_ERROR_CHECK(esp_lcd_panel_reset(panelHandle));
  ESP_ERROR_CHECK(esp_lcd_panel_init(panelHandle));
  ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panelHandle, true));

  ledc_timer_config_t timerConfig = {};
  timerConfig.speed_mode = LEDC_LOW_SPEED_MODE;
  timerConfig.duty_resolution = LEDC_TIMER_8_BIT;
  timerConfig.timer_num = LEDC_TIMER_3;
  timerConfig.freq_hz = 50000;
  timerConfig.clk_cfg = LEDC_AUTO_CLK;
  ESP_ERROR_CHECK(ledc_timer_config(&timerConfig));

  ledc_channel_config_t channelConfig = {};
  channelConfig.gpio_num = kBacklight;
  channelConfig.speed_mode = LEDC_LOW_SPEED_MODE;
  channelConfig.channel = LEDC_CHANNEL_1;
  channelConfig.intr_type = LEDC_INTR_DISABLE;
  channelConfig.timer_sel = LEDC_TIMER_3;
  channelConfig.duty = 255;
  channelConfig.hpoint = 0;
  ESP_ERROR_CHECK(ledc_channel_config(&channelConfig));
  return true;
}

void PheonixDisplay::setBrightness(uint8_t brightness) {
  ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1, brightness);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1);
}

void PheonixDisplay::flush() {
  if (panelHandle == nullptr || transferBuffer == nullptr) return;

  const auto* source = static_cast<const uint16_t*>(getBuffer());
  for (int y = 0; y < kHeight; y += kTransferRows) {
    const int rows = min(kTransferRows, kHeight - y);
    const int pixels = kWidth * rows;
    for (int index = 0; index < pixels; ++index) {
      transferBuffer[index] = __builtin_bswap16(source[y * kWidth + index]);
    }
    ESP_ERROR_CHECK(
        esp_lcd_panel_draw_bitmap(panelHandle, 0, y, kWidth, y + rows, transferBuffer));
    xSemaphoreTake(static_cast<SemaphoreHandle_t>(transferComplete), portMAX_DELAY);
  }
}

#endif
