#pragma once
#include "AltSoftSerial.h"
struct SoftwareSerial:Port { bool over=false; SoftwareSerial(int rx,int tx){(void)rx;(void)tx;} bool overflow(){bool b=over;over=false;return b;} };
