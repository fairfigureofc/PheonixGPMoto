#pragma once

#include <Arduino.h>

enum class Maneuver : uint8_t {
  Straight = 0,
  Left = 1,
  Right = 2,
};

struct NavigationState {
  uint16_t sequence = 0;
  Maneuver maneuver = Maneuver::Left;
  bool lightMode = false;
  uint32_t distanceToTurnMeters = 152;
  uint32_t remainingMeters = 139047;
  uint32_t remainingSeconds = 6120;
  String roadName = "VAN NESS AVE";
};

inline uint16_t readUInt16LE(const uint8_t* bytes) {
  return uint16_t(bytes[0]) | uint16_t(bytes[1]) << 8;
}

inline uint32_t readUInt32LE(const uint8_t* bytes) {
  return uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 |
         uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24;
}

inline bool decodeNavigationPacket(const uint8_t* bytes, size_t length,
                                   NavigationState& output) {
  if (length != 64 || bytes[0] != 1) return false;

  const uint8_t roadLength = bytes[17];
  if (roadLength > 46) return false;

  output.sequence = readUInt16LE(bytes + 1);
  output.maneuver = static_cast<Maneuver>(bytes[3]);
  output.lightMode = (bytes[4] & 1) != 0;
  output.distanceToTurnMeters = readUInt32LE(bytes + 5);
  output.remainingMeters = readUInt32LE(bytes + 9);
  output.remainingSeconds = readUInt32LE(bytes + 13);
  output.roadName = "";
  for (uint8_t index = 0; index < roadLength; ++index) {
    output.roadName += char(bytes[18 + index]);
  }
  return true;
}
