#ifndef RUNNER_PRESSURE_PLUGIN_H_
#define RUNNER_PRESSURE_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/flutter_engine.h>
#include <windows.h>

#include <memory>
#include <mutex>

#include "wintab_defines.h"

// Native pressure plugin: captures pen pressure via Wintab API and WM_POINTER.
// Supports both Wintab (legacy tablets) and Windows Ink (modern) paths.
class PressurePlugin {
 public:
  static void RegisterWithEngine(flutter::FlutterEngine* engine);

  // Initialize Wintab context for the given window
  static bool InitWintab(HWND hwnd);

  // Clean up Wintab resources
  static void CleanupWintab();

  // Handle window messages (WM_POINTER + WT_PACKET)
  static bool HandleMessage(HWND hwnd, UINT message,
                            WPARAM wparam, LPARAM lparam);

  PressurePlugin() = default;

  // Event sink for Dart communication
  static std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  static std::mutex sink_mutex_;
  static bool initialized_;

  // Wintab state
  static HMODULE wintab_dll_;
  static HCTX wintab_context_;
  static bool wintab_available_;
  static LONG pressure_max_;

  // Wintab function pointers
  static WTINFOA_FUNC WTInfoA;
  static WTOPENA_FUNC WTOpenA;
  static WTCLOSE_FUNC WTClose;
  static WTPACKET_FUNC WTPacket;
  static WTENABLE_FUNC WTEnable;
  static WTOVERLAP_FUNC WTOverlap;
  static WTQUEUESIZESET_FUNC WTQueueSizeSet;

 private:
  // Send pressure event to Dart
  static void SendPressureEvent(const char* eventType, double x, double y,
                                double pressure, bool isPen, bool hasPressure);

  // Handle Wintab WT_PACKET message
  static bool HandleWintabPacket(HWND hwnd, WPARAM wparam, LPARAM lparam);

  // Handle WM_POINTER message (Windows Ink fallback)
  static bool HandlePointerMessage(HWND hwnd, UINT message,
                                   WPARAM wparam, LPARAM lparam);
};

#endif  // RUNNER_PRESSURE_PLUGIN_H_
