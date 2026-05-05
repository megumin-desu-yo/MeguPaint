#include "pressure_plugin.h"

#include <flutter/encodable_value.h>

#include <map>
#include <string>
#include <iostream>

// Static member initialization
std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
    PressurePlugin::event_sink_ = nullptr;
std::mutex PressurePlugin::sink_mutex_;
bool PressurePlugin::initialized_ = false;

// Wintab static members
HMODULE PressurePlugin::wintab_dll_ = nullptr;
HCTX PressurePlugin::wintab_context_ = nullptr;
bool PressurePlugin::wintab_available_ = false;
LONG PressurePlugin::pressure_max_ = 1024;

// Wintab function pointers
WTINFOA_FUNC PressurePlugin::WTInfoA = nullptr;
WTOPENA_FUNC PressurePlugin::WTOpenA = nullptr;
WTCLOSE_FUNC PressurePlugin::WTClose = nullptr;
WTPACKET_FUNC PressurePlugin::WTPacket = nullptr;
WTENABLE_FUNC PressurePlugin::WTEnable = nullptr;
WTOVERLAP_FUNC PressurePlugin::WTOverlap = nullptr;
WTQUEUESIZESET_FUNC PressurePlugin::WTQueueSizeSet = nullptr;

void PressurePlugin::RegisterWithEngine(flutter::FlutterEngine* engine) {
  if (!engine || initialized_) return;

  // Create EventChannel for streaming pressure data to Dart
  auto channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          engine->messenger(), "com.megupaint/pressure",
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      // OnListen
      [](const flutter::EncodableValue* arguments,
         std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        std::lock_guard<std::mutex> lock(PressurePlugin::sink_mutex_);
        PressurePlugin::event_sink_ = std::move(events);
        std::cout << "[PressurePlugin] EventChannel connected" << std::endl;
        return nullptr;
      },
      // OnCancel
      [](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        std::lock_guard<std::mutex> lock(PressurePlugin::sink_mutex_);
        PressurePlugin::event_sink_ = nullptr;
        std::cout << "[PressurePlugin] EventChannel disconnected" << std::endl;
        return nullptr;
      });

  channel->SetStreamHandler(std::move(handler));

  // Create MethodChannel for querying pressure support status
  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), "com.megupaint/pressure_method",
          &flutter::StandardMethodCodec::GetInstance());

  method_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "isSupported") {
          // Wintab available OR WM_POINTER API available
          bool supported = PressurePlugin::wintab_available_;
          if (!supported) {
            HMODULE user32_mod = GetModuleHandleW(L"user32.dll");
            if (user32_mod) {
              auto fn = reinterpret_cast<BOOL(WINAPI*)(UINT32,
                                                       POINTER_INPUT_TYPE*)>(
                  GetProcAddress(user32_mod, "GetPointerType"));
              supported = (fn != nullptr);
            }
          }
          result->Success(flutter::EncodableValue(supported));
        } else if (call.method_name() == "getScreenColor") {
          // Get pixel color at screen position
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto x_it = args->find(flutter::EncodableValue("x"));
            auto y_it = args->find(flutter::EncodableValue("y"));
            if (x_it != args->end() && y_it != args->end()) {
              int x = static_cast<int>(std::get<double>(x_it->second));
              int y = static_cast<int>(std::get<double>(y_it->second));
              
              HDC hdc = GetDC(NULL);
              if (hdc) {
                COLORREF color = GetPixel(hdc, x, y);
                ReleaseDC(NULL, hdc);
                
                if (color != CLR_INVALID) {
                  flutter::EncodableMap colorMap;
                  colorMap[flutter::EncodableValue("r")] = flutter::EncodableValue(static_cast<int>(GetRValue(color)));
                  colorMap[flutter::EncodableValue("g")] = flutter::EncodableValue(static_cast<int>(GetGValue(color)));
                  colorMap[flutter::EncodableValue("b")] = flutter::EncodableValue(static_cast<int>(GetBValue(color)));
                  colorMap[flutter::EncodableValue("a")] = flutter::EncodableValue(255);
                  result->Success(flutter::EncodableValue(colorMap));
                  return;
                }
              }
            }
          }
          result->Error("INVALID_ARGS", "Failed to get screen color");
        } else {
          result->NotImplemented();
        }
      });

  // Keep channels alive via static storage
  static std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      s_channel;
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      s_method_channel;
  s_channel = std::move(channel);
  s_method_channel = std::move(method_channel);

  initialized_ = true;
  std::cout << "[PressurePlugin] Native pressure plugin registered"
            << std::endl;
}

bool PressurePlugin::InitWintab(HWND hwnd) {
  // Try to load Wintab32.dll
  wintab_dll_ = LoadLibraryA("Wintab32.dll");
  if (!wintab_dll_) {
    std::cout << "[PressurePlugin] Wintab32.dll not found, Wintab disabled"
              << std::endl;
    return false;
  }

  // Load function pointers
  WTInfoA = (WTINFOA_FUNC)GetProcAddress(wintab_dll_, "WTInfoA");
  WTOpenA = (WTOPENA_FUNC)GetProcAddress(wintab_dll_, "WTOpenA");
  WTClose = (WTCLOSE_FUNC)GetProcAddress(wintab_dll_, "WTCloseA");
  WTPacket = (WTPACKET_FUNC)GetProcAddress(wintab_dll_, "WTPacket");
  WTEnable = (WTENABLE_FUNC)GetProcAddress(wintab_dll_, "WTEnable");
  WTOverlap = (WTOVERLAP_FUNC)GetProcAddress(wintab_dll_, "WTOverlap");
  WTQueueSizeSet =
      (WTQUEUESIZESET_FUNC)GetProcAddress(wintab_dll_, "WTQueueSizeSet");

  // WTClose might be exported as "WTClose" without the A suffix
  if (!WTClose) {
    WTClose = (WTCLOSE_FUNC)GetProcAddress(wintab_dll_, "WTClose");
  }

  if (!WTInfoA || !WTOpenA || !WTClose || !WTPacket) {
    std::cout << "[PressurePlugin] Failed to load Wintab functions"
              << std::endl;
    FreeLibrary(wintab_dll_);
    wintab_dll_ = nullptr;
    return false;
  }

  // Check if Wintab is available (returns 0 if no tablet)
  UINT wintabCheck = WTInfoA(0, 0, nullptr);
  if (wintabCheck == 0) {
    std::cout << "[PressurePlugin] No Wintab device found" << std::endl;
    FreeLibrary(wintab_dll_);
    wintab_dll_ = nullptr;
    return false;
  }

  // Get pressure range
  AXIS pressureAxis = {};
  if (WTInfoA(WTI_DEVICES, DVC_NPRESSURE, &pressureAxis)) {
    pressure_max_ = pressureAxis.axMax;
    std::cout << "[PressurePlugin] Pressure range: 0 - " << pressure_max_
              << std::endl;
  }

  // Use SYSTEM context (always receives events regardless of focus)
  LOGCONTEXTA ctx = {};
  WTInfoA(WTI_DEFSYSCTX, 0, &ctx);

  // Configure context
  ctx.lcMsgBase = WT_DEFBASE;
  ctx.lcOptions |= CXO_MESSAGES | CXO_SYSTEM;
  ctx.lcPktData = PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_CURSOR | PK_BUTTONS;
  ctx.lcPktMode = 0;  // absolute mode
  ctx.lcMoveMask = PK_X | PK_Y | PK_NORMAL_PRESSURE;

  // Map output to entire screen
  ctx.lcOutOrgX = GetSystemMetrics(SM_XVIRTUALSCREEN);
  ctx.lcOutOrgY = GetSystemMetrics(SM_YVIRTUALSCREEN);
  ctx.lcOutExtX = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  ctx.lcOutExtY = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  // Open Wintab context (TRUE = enabled)
  wintab_context_ = WTOpenA(hwnd, &ctx, TRUE);
  if (!wintab_context_) {
    std::cout << "[PressurePlugin] Failed to open Wintab context" << std::endl;
    FreeLibrary(wintab_dll_);
    wintab_dll_ = nullptr;
    return false;
  }

  // Make context topmost to receive events
  if (WTOverlap) {
    WTOverlap(wintab_context_, TRUE);
  }

  // Set queue size
  if (WTQueueSizeSet) {
    WTQueueSizeSet(wintab_context_, 128);
  }

  wintab_available_ = true;
  std::cout << "[PressurePlugin] Wintab initialized successfully (max pressure: "
            << pressure_max_ << ")" << std::endl;
  return true;
}

void PressurePlugin::CleanupWintab() {
  if (wintab_context_ && WTClose) {
    WTClose(wintab_context_);
    wintab_context_ = nullptr;
  }
  if (wintab_dll_) {
    FreeLibrary(wintab_dll_);
    wintab_dll_ = nullptr;
  }
  wintab_available_ = false;
}

bool PressurePlugin::HandleMessage(HWND hwnd, UINT message,
                                   WPARAM wparam, LPARAM lparam) {
  // Handle WM_ACTIVATE: re-enable Wintab context when window gains focus
  if (message == WM_ACTIVATE && wintab_context_) {
    WORD activeState = LOWORD(wparam);
    if (WTEnable) {
      WTEnable(wintab_context_, activeState != WA_INACTIVE);
    }
    if (activeState != WA_INACTIVE && WTOverlap) {
      WTOverlap(wintab_context_, TRUE);
    }
  }

  // Priority 1: Wintab WT_PACKET messages
  if (wintab_available_ && message == WT_PACKET) {
    return HandleWintabPacket(hwnd, wparam, lparam);
  }

  // Priority 2: WM_POINTER messages (Windows Ink fallback)
  if (message == WM_POINTERUPDATE || message == WM_POINTERDOWN ||
      message == WM_POINTERUP) {
    return HandlePointerMessage(hwnd, message, wparam, lparam);
  }

  return false;
}

bool PressurePlugin::HandleWintabPacket(HWND hwnd, WPARAM wparam,
                                        LPARAM lparam) {
  if (!wintab_context_ || !WTPacket) return false;

  WINTAB_PACKET pkt = {};
  if (!WTPacket(wintab_context_, (UINT)wparam, &pkt)) {
    return false;
  }

  // Calculate normalized pressure (0.0 - 1.0)
  double pressure = 0.0;
  bool hasPressure = false;
  if (pressure_max_ > 0) {
    pressure = static_cast<double>(pkt.pkNormalPressure) /
               static_cast<double>(pressure_max_);
    hasPressure = true;
  }

  // Convert Wintab coordinates to client coordinates
  // pkX, pkY are in screen coordinates (due to our context config)
  POINT screenPt;
  screenPt.x = pkt.pkX;
  screenPt.y = pkt.pkY;
  ScreenToClient(hwnd, &screenPt);

  // Determine event type based on pressure
  const char* eventType = "move";
  static bool wasDown = false;
  if (pkt.pkNormalPressure > 0 && !wasDown) {
    eventType = "down";
    wasDown = true;
  } else if (pkt.pkNormalPressure == 0 && wasDown) {
    eventType = "up";
    wasDown = false;
  }

  SendPressureEvent(eventType,
                    static_cast<double>(screenPt.x),
                    static_cast<double>(screenPt.y),
                    pressure, true, hasPressure);
  return false;  // Don't consume, let Flutter also process
}

bool PressurePlugin::HandlePointerMessage(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam) {
  // Skip if Wintab is handling pressure
  if (wintab_available_) return false;

  UINT32 pointerId = GET_POINTERID_WPARAM(wparam);

  POINTER_INPUT_TYPE pointerType = PT_POINTER;
  if (!GetPointerType(pointerId, &pointerType)) {
    return false;
  }

  POINTER_INFO pointerInfo = {};
  if (!GetPointerInfo(pointerId, &pointerInfo)) {
    return false;
  }

  double pressure = 0.0;
  bool isPen = false;
  bool hasPressure = false;

  if (pointerType == PT_PEN) {
    POINTER_PEN_INFO penInfo = {};
    if (GetPointerPenInfo(pointerId, &penInfo)) {
      isPen = true;
      if (penInfo.penMask & PEN_MASK_PRESSURE) {
        pressure = static_cast<double>(penInfo.pressure) / 1024.0;
        hasPressure = true;
      }
    }
  } else if (pointerType == PT_TOUCH) {
    POINTER_TOUCH_INFO ti = {};
    if (GetPointerTouchInfo(pointerId, &ti)) {
      if (ti.touchMask & TOUCH_MASK_PRESSURE) {
        pressure = static_cast<double>(ti.pressure) / 1024.0;
        hasPressure = true;
      }
    }
  }

  POINT clientPt = pointerInfo.ptPixelLocation;
  ScreenToClient(hwnd, &clientPt);

  const char* eventType = "move";
  if (message == WM_POINTERDOWN) eventType = "down";
  else if (message == WM_POINTERUP) eventType = "up";

  SendPressureEvent(eventType,
                    static_cast<double>(clientPt.x),
                    static_cast<double>(clientPt.y),
                    pressure, isPen, hasPressure);
  return false;
}

void PressurePlugin::SendPressureEvent(const char* eventType, double x,
                                       double y, double pressure, bool isPen,
                                       bool hasPressure) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!event_sink_) return;

  flutter::EncodableMap data;
  data[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string(eventType));
  data[flutter::EncodableValue("pointerId")] =
      flutter::EncodableValue(0);
  data[flutter::EncodableValue("x")] =
      flutter::EncodableValue(x);
  data[flutter::EncodableValue("y")] =
      flutter::EncodableValue(y);
  data[flutter::EncodableValue("pressure")] =
      flutter::EncodableValue(pressure);
  data[flutter::EncodableValue("tiltX")] =
      flutter::EncodableValue(0.0);
  data[flutter::EncodableValue("tiltY")] =
      flutter::EncodableValue(0.0);
  data[flutter::EncodableValue("isPen")] =
      flutter::EncodableValue(isPen);
  data[flutter::EncodableValue("hasPressure")] =
      flutter::EncodableValue(hasPressure);
  data[flutter::EncodableValue("pointerType")] =
      flutter::EncodableValue(isPen ? 3 : 0);

  event_sink_->Success(flutter::EncodableValue(data));
}
