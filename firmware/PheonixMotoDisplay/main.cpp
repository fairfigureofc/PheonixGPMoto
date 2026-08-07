#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include "fragment_mono.hpp"
#if defined(PHEONIX_WAVESHARE_KNOB)
#include "waveshare_knob_display.hpp"
#else
#include "lgfx_config.hpp"
#endif
#include "navigation_packet.hpp"

constexpr char DEVICE_NAME[] = "Pheonix Moto";
constexpr char SERVICE_UUID[] = "6F4A0001-6F74-4F4D-8A48-50484F454E58";
constexpr char NAVIGATION_UUID[] = "6F4A0002-6F74-4F4D-8A48-50484F454E58";

PheonixDisplay display;
NavigationState navigation;
bool connected = false;

String turnDistance(uint32_t meters) {
  if (meters < 305) {
    const uint32_t feet = uint32_t(round(meters * 3.28084 / 10.0) * 10.0);
    return String(feet) + " FT";
  }
  return String(meters / 1000.0, 1) + " KM";
}

String remainingTime(uint32_t seconds) {
  const uint32_t minutes = seconds / 60;
  if (minutes < 60) return String(minutes) + "M";
  return String(minutes / 60) + "H " + String(minutes % 60) + "M";
}

#if defined(PHEONIX_WAVESHARE_KNOB)
constexpr int32_t DISPLAY_SIZE = 360;
constexpr int32_t DISPLAY_CENTER = 180;
constexpr int32_t ARROW_DOT_RADIUS = 5;
constexpr int32_t ARROW_DOT_STEP = 14;
constexpr int32_t ARROW_TIP_X = 94;
constexpr int32_t ARROW_CENTER_Y = 151;
constexpr int32_t ARROW_SHAFT_START = 122;
constexpr int32_t ARROW_SHAFT_END = 262;
constexpr int32_t STRAIGHT_TIP_Y = 95;
constexpr uint8_t BATTERY_ADC_PIN = 1;
constexpr uint32_t BATTERY_SAMPLE_INTERVAL_MS = 30000;
uint8_t batteryBars = 0;
uint32_t lastBatterySampleMs = 0;
#else
constexpr int32_t DISPLAY_SIZE = 240;
constexpr int32_t DISPLAY_CENTER = 120;
constexpr int32_t ARROW_DOT_RADIUS = 4;
constexpr int32_t ARROW_DOT_STEP = 12;
constexpr int32_t ARROW_TIP_X = 42;
constexpr int32_t ARROW_CENTER_Y = 137;
constexpr int32_t ARROW_SHAFT_START = 66;
constexpr int32_t ARROW_SHAFT_END = 186;
constexpr int32_t STRAIGHT_TIP_Y = 93;
#endif

#if defined(PHEONIX_WAVESHARE_KNOB)
uint32_t readBatteryMillivolts() {
  uint32_t sampleTotal = 0;
  constexpr uint8_t SAMPLE_COUNT = 8;
  for (uint8_t sample = 0; sample < SAMPLE_COUNT; ++sample) {
    sampleTotal += analogReadMilliVolts(BATTERY_ADC_PIN);
  }

  // Waveshare's battery/system-voltage input uses a 2:1 divider.
  return (sampleTotal / SAMPLE_COUNT) * 2;
}

uint8_t batteryBarCount(uint32_t millivolts) {
  if (millivolts >= 3900) return 3;
  if (millivolts >= 3700) return 2;
  if (millivolts >= 3400) return 1;
  return 0;
}

void drawBluetoothIcon(int32_t x, int32_t y, uint32_t color) {
  display.drawFastVLine(x + 4, y, 15, color);
  display.drawLine(x + 4, y, x + 9, y + 4, color);
  display.drawLine(x + 9, y + 4, x + 1, y + 11, color);
  display.drawLine(x + 1, y + 4, x + 9, y + 11, color);
  display.drawLine(x + 9, y + 11, x + 4, y + 15, color);
}

void drawBatteryBars(int32_t x, int32_t baselineY, uint32_t activeColor,
                     uint32_t inactiveColor) {
  constexpr int32_t HEIGHTS[] = {4, 7, 10};
  for (uint8_t bar = 0; bar < 3; ++bar) {
    const uint32_t color = bar < batteryBars ? activeColor : inactiveColor;
    const int32_t top = baselineY - HEIGHTS[bar] + 1;
    display.drawFastVLine(x + bar * 5, top, HEIGHTS[bar], color);
    display.drawFastVLine(x + bar * 5 + 1, top, HEIGHTS[bar], color);
  }
}
#endif

void drawArrowDot(int32_t x, int32_t y, uint32_t color) {
  display.fillCircle(x, y, ARROW_DOT_RADIUS, color);
}

void drawHorizontalArrow(bool pointsLeft, uint32_t color) {
  for (int32_t step = 0; step <= 4; ++step) {
    const int32_t sourceX = ARROW_TIP_X + step * ARROW_DOT_STEP;
    const int32_t x = pointsLeft ? sourceX : DISPLAY_SIZE - sourceX;
    for (int32_t row = -step; row <= step; ++row) {
      drawArrowDot(x, ARROW_CENTER_Y + row * ARROW_DOT_STEP, color);
    }
  }

  for (int32_t x = ARROW_SHAFT_START; x <= ARROW_SHAFT_END; x += ARROW_DOT_STEP) {
    const int32_t mirroredX = pointsLeft ? x : DISPLAY_SIZE - x;
    drawArrowDot(mirroredX, ARROW_CENTER_Y - ARROW_DOT_STEP, color);
    drawArrowDot(mirroredX, ARROW_CENTER_Y, color);
    drawArrowDot(mirroredX, ARROW_CENTER_Y + ARROW_DOT_STEP, color);
  }
}

void drawLeftArrow(uint32_t color) {
  drawHorizontalArrow(true, color);
}

void drawRightArrow(uint32_t color) {
  drawHorizontalArrow(false, color);
}

void drawStraightArrow(uint32_t color) {
  for (int32_t step = 0; step <= 4; ++step) {
    const int32_t y = STRAIGHT_TIP_Y + step * ARROW_DOT_STEP;
    for (int32_t column = -step; column <= step; ++column) {
      drawArrowDot(DISPLAY_CENTER + column * ARROW_DOT_STEP, y, color);
    }
  }

  for (int32_t y = STRAIGHT_TIP_Y + 4 * ARROW_DOT_STEP;
       y <= STRAIGHT_TIP_Y + 8 * ARROW_DOT_STEP; y += ARROW_DOT_STEP) {
    drawArrowDot(DISPLAY_CENTER - ARROW_DOT_STEP, y, color);
    drawArrowDot(DISPLAY_CENTER, y, color);
    drawArrowDot(DISPLAY_CENTER + ARROW_DOT_STEP, y, color);
  }
}

String fittedRoadName(const String& roadName, int32_t maximumWidth) {
  if (display.textWidth(roadName) <= maximumWidth) return roadName;

  String fitted = roadName;
  while (fitted.length() > 1 && display.textWidth(fitted + "...") > maximumWidth) {
    fitted.remove(fitted.length() - 1);
  }
  return fitted + "...";
}

#if defined(PHEONIX_WAVESHARE_KNOB)
struct HeaderLines {
  String first;
  String second;
};

HeaderLines wrappedHeader(const String& instruction, int32_t maximumWidth) {
  if (display.textWidth(instruction) <= maximumWidth) {
    return {instruction, ""};
  }

  HeaderLines best = {fittedRoadName(instruction, maximumWidth), ""};
  int32_t bestBalance = INT32_MAX;
  for (uint32_t index = 1; index + 1 < instruction.length(); ++index) {
    if (instruction.charAt(index) != ' ') continue;

    const String first = instruction.substring(0, index);
    const String second = instruction.substring(index + 1);
    const int32_t firstWidth = display.textWidth(first);
    const int32_t secondWidth = display.textWidth(second);
    if (firstWidth > maximumWidth || secondWidth > maximumWidth) continue;

    const int32_t balance = abs(firstWidth - secondWidth);
    if (balance < bestBalance) {
      best = {first, second};
      bestBalance = balance;
    }
  }

  return best;
}
#endif

void drawNavigation() {
  const uint32_t background = navigation.lightMode ? 0xF7F7F0 : 0x050505;
  const uint32_t foreground = navigation.lightMode ? 0x050505 : 0xF7F7F0;
  display.fillScreen(background);
  display.setTextColor(foreground, background);
  display.setTextDatum(lgfx::textdatum_t::top_center);

  display.setFont(&pheonix::fonts::FragmentMonoMedium);
  display.setTextSize(1);
#if defined(PHEONIX_WAVESHARE_KNOB)
  const uint32_t inactive = navigation.lightMode ? 0xB8B8B0 : 0x4A4A4A;
  drawBluetoothIcon(163, 14, connected ? foreground : inactive);
  drawBatteryBars(186, 29, foreground, inactive);
  const HeaderLines header = wrappedHeader(navigation.roadName, 252);
  if (header.second.isEmpty()) {
    display.drawString(header.first, DISPLAY_CENTER, 42);
  } else {
    display.drawString(header.first, DISPLAY_CENTER, 32);
    display.drawString(header.second, DISPLAY_CENTER, 52);
  }
  display.drawFastHLine(54, 80, 252, foreground);
#else
  display.drawString(navigation.roadName, 120, 22);
  display.drawFastHLine(16, 58, 208, foreground);
#endif

  switch (navigation.maneuver) {
    case Maneuver::Left: drawLeftArrow(foreground); break;
    case Maneuver::Right: drawRightArrow(foreground); break;
    case Maneuver::Straight: drawStraightArrow(foreground); break;
  }

  display.setFont(&pheonix::fonts::FragmentMonoLarge);
  display.setTextSize(1);
#if defined(PHEONIX_WAVESHARE_KNOB)
  display.drawString(turnDistance(navigation.distanceToTurnMeters), DISPLAY_CENTER, 220);
  display.drawFastHLine(54, 270, 252, foreground);
#else
  display.drawString(turnDistance(navigation.distanceToTurnMeters), 120, 193);
  display.drawFastHLine(16, 250, 208, foreground);
#endif

  display.setFont(&pheonix::fonts::FragmentMonoSmall);
  display.setTextSize(1);
#if defined(PHEONIX_WAVESHARE_KNOB)
  display.setTextDatum(lgfx::textdatum_t::top_center);
  display.drawString("TIME LEFT", 118, 280);
  display.drawString("MILES LEFT", 242, 280);
  display.drawFastVLine(DISPLAY_CENTER, 280, 48, foreground);

  display.setFont(&pheonix::fonts::FragmentMonoMedium);
  display.drawString(remainingTime(navigation.remainingSeconds), 118, 302);
  display.drawString(String(navigation.remainingMeters / 1609.344, 1) + " MI", 242, 302);
#else
  display.setTextDatum(lgfx::textdatum_t::top_left);
  display.drawString("TIME LEFT", 18, 260);
  display.drawString("MILES LEFT", 132, 260);
  display.drawFastVLine(120, 260, 43, foreground);

  display.setFont(&pheonix::fonts::FragmentMonoMedium);
  display.setTextDatum(lgfx::textdatum_t::top_left);
  display.drawString(remainingTime(navigation.remainingSeconds), 18, 280);
  display.setTextDatum(lgfx::textdatum_t::top_right);
  display.drawString(String(navigation.remainingMeters / 1609.344, 1) + " MI", 222, 280);

  display.setFont(&pheonix::fonts::FragmentMonoSmall);
  display.setTextDatum(lgfx::textdatum_t::top_right);
  display.drawString(connected ? "BLE+" : "BLE", 222, 7);
#endif
  display.flush();
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    connected = true;
    drawNavigation();
  }

  void onDisconnect(BLEServer* server) override {
    connected = false;
    drawNavigation();
    delay(250);
    server->startAdvertising();
  }
};

class NavigationCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const auto value = characteristic->getValue();
    NavigationState next;
    if (decodeNavigationPacket(
            reinterpret_cast<const uint8_t*>(value.c_str()), value.length(), next)) {
      navigation = next;
      Serial.printf("Navigation packet %u: %s\n", navigation.sequence,
                    navigation.roadName.c_str());
      drawNavigation();
    } else {
      Serial.printf("Rejected navigation packet with %u bytes\n", value.length());
    }
  }
};

void setup() {
  Serial.begin(115200);
  if (!display.init()) {
    Serial.println("Display initialization failed");
  }
  display.setRotation(0);
  display.setBrightness(180);
#if defined(PHEONIX_WAVESHARE_KNOB)
  analogReadResolution(12);
  analogSetPinAttenuation(BATTERY_ADC_PIN, ADC_11db);
  batteryBars = batteryBarCount(readBatteryMillivolts());
  lastBatterySampleMs = millis();
#endif
  drawNavigation();

  BLEDevice::init(DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);
  BLECharacteristic* navigationCharacteristic = service->createCharacteristic(
      NAVIGATION_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  navigationCharacteristic->setCallbacks(new NavigationCallbacks());
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
  Serial.println("Pheonix Moto display ready");
}

void loop() {
#if defined(PHEONIX_WAVESHARE_KNOB)
  const uint32_t now = millis();
  if (now - lastBatterySampleMs >= BATTERY_SAMPLE_INTERVAL_MS) {
    lastBatterySampleMs = now;
    const uint8_t nextBatteryBars = batteryBarCount(readBatteryMillivolts());
    if (nextBatteryBars != batteryBars) {
      batteryBars = nextBatteryBars;
      drawNavigation();
    }
  }
#endif
  delay(1000);
}
