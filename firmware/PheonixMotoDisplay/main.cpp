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

void drawNavigation() {
  const uint32_t background = navigation.lightMode ? 0xF7F7F0 : 0x050505;
  const uint32_t foreground = navigation.lightMode ? 0x050505 : 0xF7F7F0;
  display.fillScreen(background);
  display.setTextColor(foreground, background);
  display.setTextDatum(lgfx::textdatum_t::top_center);

  display.setFont(&pheonix::fonts::FragmentMonoMedium);
  display.setTextSize(1);
#if defined(PHEONIX_WAVESHARE_KNOB)
  display.drawString(connected ? "BLE+" : "BLE", DISPLAY_CENTER, 15);
  display.drawString(fittedRoadName(navigation.roadName, 252), DISPLAY_CENTER, 40);
  display.drawFastHLine(54, 77, 252, foreground);
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
  delay(1000);
}
