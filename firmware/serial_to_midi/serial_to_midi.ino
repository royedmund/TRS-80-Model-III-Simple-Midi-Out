/*
 * TRS-80 Model III Simple MIDI OUT — Rev 0.1
 * Classic Arduino Nano (ATmega328P, 5 V / 16 MHz).
 * MAX3232 R1OUT -> D10; D1 -> 220 ohms -> DIN pin 5.
 * D11 is required by SoftwareSerial but is left unconnected.
 * Disconnect MIDI OUT during upload/reset.
 * Prototype: not compiled or hardware tested.
 */
#include <SoftwareSerial.h>

constexpr uint8_t RS232_RX = 10;
constexpr uint8_t UNUSED_TX = 11;
constexpr unsigned long TRS_BAUD = 9600;
constexpr unsigned long MIDI_BAUD = 31250;

SoftwareSerial trs80(RS232_RX, UNUSED_TX);

void setup() {
  Serial.begin(MIDI_BAUD, SERIAL_8N1);
  trs80.begin(TRS_BAUD);
}

void loop() {
  while (trs80.available() > 0) {
    int value = trs80.read();
    if (value >= 0) {
      Serial.write(static_cast<uint8_t>(value));
    }
  }
}
