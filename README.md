# NeoLight : An IoT-Based Adaptive Street Lighting System

## 1. Introduction

This project presents a smart motion-based lighting system designed to optimize energy consumption and enhance public safety. Using a Flutter-based mobile application integrated with real-time monitoring and database connectivity, the system adjusts lighting intensity based on motion detection, ambient light, weather conditions, and time of day.

Traditional lighting systems often waste energy due to continuous illumination irrespective of environmental conditions or human presence. This IoT-based smart lighting solution leverages motion sensors, ambient light readings, and time-based automation to dynamically control lighting intensity, significantly reducing power usage. Designed for urban infrastructure, the project contributes to environmental sustainability.

---

## 2. Components Overview

- **ESP32 Microcontroller**
- **PIR Motion Sensors**
- **10 mm LEDs**
- **LDR Sensor**
- **Flutter App (Cross-platform)**
- **Cloud Database (Firebase or MongoDB)**
- **Wires and Connectors**

---

## 3. Working Mechanism

The system consists of three PIR sensors and corresponding LEDs installed across different locations. The LEDs operate at a base brightness of 30% to ensure visibility. When motion is detected, the corresponding LED increases its brightness to 100%. Additionally, the lighting behavior is determined by:

- **Day/Night Timing:** Based on real-time clock or system time, the system ensures lights are off during daylight unless needed.
- **Weather Conditions:** Cloudy or dark conditions can override daylight settings and turn on lights for better visibility.
- **Light Emission Levels:** Light sensors can detect ambient brightness and adjust LEDs accordingly.

All data is monitored and updated in real-time using a Flutter app, which interacts with Firebase for database operations.

---

