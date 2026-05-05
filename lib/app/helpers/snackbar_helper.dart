import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Drop-in replacement for [Get.snackbar] that no-ops when a snackbar is
/// already on screen. Prevents the "100 snackbars stacked from a spammed
/// button" UX bug.
void showSnackbar(
  String title,
  String message, {
  SnackPosition? snackPosition,
  Color? backgroundColor,
  Color? colorText,
  Duration? duration,
  EdgeInsets? margin,
  EdgeInsets? padding,
  double? borderRadius,
  bool? isDismissible,
}) {
  if (Get.isSnackbarOpen) return;
  Get.snackbar(
    title,
    message,
    snackPosition: snackPosition ?? SnackPosition.TOP,
    backgroundColor: backgroundColor,
    colorText: colorText,
    duration: duration ?? const Duration(seconds: 3),
    margin: margin ?? const EdgeInsets.all(15),
    padding: padding ?? const EdgeInsets.all(16),
    borderRadius: borderRadius ?? 8,
    isDismissible: isDismissible ?? true,
  );
}
