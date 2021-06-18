import winim, core

proc GetScaleFactorForMonitor*(hMon: HMONITOR, pScale: ptr DEVICE_SCALE_FACTOR): HRESULT
  {.stdcall, dynlib: "Shcore", importc: "GetScaleFactorForMonitor".}

proc SetProcessDpiAwarenessContext*(param: int32): bool
  {.stdcall, dynlib: "User32", importc: "SetProcessDpiAwarenessContext".}


converter f2i*(c: float): int32 = c.int32


proc getMargins*(hwnd: HWND): winim.Rect =
  var 
    winSizeWithMargins: winim.Rect
    winRect: winim.Rect
    scale: DEVICE_SCALE_FACTOR
  if DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
      &winSizeWithMargins, sizeof(winSizeWithMargins).DWORD).FAILED:
    error "Couldn't retrieve window size with margin"
  if GetWindowRect(hwnd, &winRect).FAILED:
    error "Couldn't retrieve window size without margin"
  let mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)
  if GetScaleFactorForMonitor(mon, &scale).FAILED:
    error "Couldn't retrieve monitor scale"

  result.left = winSizeWithMargins.left.float - winRect.left
  result.top = winSizeWithMargins.top.float - winRect.top
  result.right = winRect.right - winSizeWithMargins.right.float
  result.bottom = winRect.bottom - winSizeWithMargins.bottom.float
