import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bridge/aegis_bridge.dart';

class ParentalControlService {
  static bool isScheduleEnabled = false;
  static TimeOfDay startSchedule = const TimeOfDay(hour: 22, minute: 0);
  static TimeOfDay endSchedule = const TimeOfDay(hour: 6, minute: 0);

  static Future<void> loadSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isScheduleEnabled = prefs.getBool('parental_schedule_enabled') ?? false;
      final startHour = prefs.getInt('parental_start_hour') ?? 22;
      final startMinute = prefs.getInt('parental_start_minute') ?? 0;
      final endHour = prefs.getInt('parental_end_hour') ?? 6;
      final endMinute = prefs.getInt('parental_end_minute') ?? 0;

      startSchedule = TimeOfDay(hour: startHour, minute: startMinute);
      endSchedule = TimeOfDay(hour: endHour, minute: endMinute);
    } catch (_) {}
  }

  static Future<void> saveSchedule({
    required bool enabled,
    required TimeOfDay start,
    required TimeOfDay end,
  }) async {
    isScheduleEnabled = enabled;
    startSchedule = start;
    endSchedule = end;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('parental_schedule_enabled', enabled);
      await prefs.setInt('parental_start_hour', start.hour);
      await prefs.setInt('parental_start_minute', start.minute);
      await prefs.setInt('parental_end_hour', end.hour);
      await prefs.setInt('parental_end_minute', end.minute);
    } catch (_) {}

    checkAndApplySchedule();
  }

  static void checkAndApplySchedule() {
    if (!isScheduleEnabled) return;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = startSchedule.hour * 60 + startSchedule.minute;
    final endMinutes = endSchedule.hour * 60 + endSchedule.minute;

    bool inSchedule = false;
    if (startMinutes <= endMinutes) {
      inSchedule =
          currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } else {
      // Overnight schedule (e.g. 22:00 to 06:00)
      inSchedule =
          currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }

    if (inSchedule) {
      // Enforce Adult & Malware categories during schedule
      AegisBridge.setCategory(3, true); // Adult category
    }
  }
}
