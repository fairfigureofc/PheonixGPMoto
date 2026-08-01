#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include "fragment_mono.hpp"
#include "lgfx_config.hpp"
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

constexpr int32_t ARROW_DOT_RADIUS = 4;
constexpr int32_t ARROW_DOT_STEP = 12;

void drawArrowDot(int32_t x, int32_t y, uint32_t color) {
  display.fillCircle(x, y, ARROW_DOT_RADIUS, color);
}

void drawHorizontalArrow(bool pointsLeft, uint32_t color) {
  constexpr int32_t tipX = 42;
  constexpr int32_t centerY = 137;

  for (int32_t step = 0; step <= 4; ++step) {
    const int32_t sourceX = tipX + step * ARROW_DOT_STEP;
    const int32_t x = pointsLeft ? sourceX : 240 - sourceX;
    for (int32_t row = -step; row <= step; ++row) {
      drawArrowDot(x, centerY + row * ARROW_DOT_STEP, color);
    }
  }

  for (int32_t x = 66; x <= 186; x += ARROW_DOT_STEP) {
    const int32_t mirroredX = pointsLeft ? x : 240 - x;
    drawArrowDot(mirroredX, centerY - ARROW_DOT_STEP, color);
    drawArrowDot(mirroredX, centerY, color);
    drawArrowDot(mirroredX, centerY + ARROW_DOT_STEP, color);
  }
}

void drawLeftArrow(uint32_t color) {
  drawHorizontalArrow(true, color);
}

void drawRightArrow(uint32_t color) {
  drawHorizontalArrow(false, color);
}

void drawStraightArrow(uint32_t color) {
  constexpr int32_t centerX = 120;
  constexpr int32_t tipY = 93;

  for (int32_t step = 0; step <= 4; ++step) {
    const int32_t y = tipY + step * ARROW_DOT_STEP;
    for (int32_t column = -step; column <= step; ++column) {
      drawArrowDot(centerX + column * ARROW_DOT_STEP, y, color);
    }
  }

  for (int32_t y = 141; y <= 189; y += ARROW_DOT_STEP) {
    drawArrowDot(centerX - ARROW_DOT_STEP, y, color);
    drawArrowDot(centerX, y, color);
    drawArrowDot(centerX + ARROW_DOT_STEP, y, color);
  }
}

void drawNavigation() {
  const uint32_t background = navigation.lightMode ? 0xF7F7F0 : 0x050505;
  const uint32_t foreground = navigation.lightMode ? 0x050505 : 0xF7F7F0;
  display.fillScreen(background);
  display.setTextColor(foreground, background);
  display.setTextDatum(lgfx::textdatum_t::top_center);

  display.setFont(&pheonix::fonts::FragmentMonoMedium);
  display.setTextSize(1);
  display.drawString(navigation.roadName, 120, 22);
  display.drawFastHLine(16, 58, 208, foreground);

  switch (navigation.maneuver) {
    case Maneuver::Left: drawLeftArrow(foreground); break;
    case Maneuver::Right: drawRightArrow(foreground); break;
    case Maneuver::Straight: drawStraightArrow(foreground); break;
  }

  display.setFont(&pheonix::fonts::FragmentMonoLarge);
  display.setTextSize(1);
  display.drawString(turnDistance(navigation.distanceToTurnMeters), 120, 193);
  display.drawFastHLine(16, 250, 208, foreground);

  display.setFont(&pheonix::fonts::FragmentMonoSmall);
  display.setTextSize(1);
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
  display.init();
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
