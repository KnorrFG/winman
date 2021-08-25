import winim, core, strformat, tables, sugar

proc GetScaleFactorForMonitor*(
  hMon: HMONITOR, pScale: ptr DEVICE_SCALE_FACTOR): HRESULT
  {.stdcall, dynlib: "Shcore", importc: "GetScaleFactorForMonitor".}

proc SetProcessDpiAwarenessContext*(param: int32): bool
  {.stdcall, dynlib: "User32", importc: "SetProcessDpiAwarenessContext".}


converter f2i*(c: float): int32 = c.int32


proc getMargins*(hwnd: HWND): winim.Rect =
  var 
    winSizeWithMargins: winim.Rect
    winRect: winim.Rect
    scale: DEVICE_SCALE_FACTOR
  let res= DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
      &winSizeWithMargins, sizeof(winSizeWithMargins).DWORD)
  if res.FAILED:
    error fmt"Couldn't retrieve window size with margin 0x{res.toHex()}"
  if GetWindowRect(hwnd, &winRect).FAILED:
    error "Couldn't retrieve window size without margin"
  let mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)
  if GetScaleFactorForMonitor(mon, &scale).FAILED:
    error "Couldn't retrieve monitor scale"

  # the explorer, and possibly other windows, might leak over between monitors
  # for some strange reason, by just removing the one pixel for the margins,
  # this problem is gone, at the cost of tiny gaps, and I can live with that.
  result.left = winSizeWithMargins.left.float - winRect.left - 1
  result.top = winSizeWithMargins.top.float - winRect.top - 1
  result.right = winRect.right - winSizeWithMargins.right.float - 1
  result.bottom = winRect.bottom - winSizeWithMargins.bottom.float - 1


type MonitorTable = TableRef[HMONITOR, core.Rect[int32]]

proc monitorInfoReceiver(
    handle: HMONITOR, deviceContext: HDC, monRect: LPRECT, data: LPARAM): WINBOOL
    {.stdcall.} =
  var 
    monitorList = cast[ptr MonitorTable](data)[]
    monInfo: MONITORINFO
  monInfo.cbSize = sizeof(MONITORINFO).int32
  if GetMonitorInfo(handle, &monInfo).FAILED:
    error "couldnt retrieve monitor info"
  let rect = monInfo.rcWORK
  monitorList[handle] = initRect(
    rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)
  return true

proc getMonitorRects*(): MonitorTable =
  var table = newTable[HMONITOR, core.Rect[int32]]()
  EnumDisplayMonitors(0.HDC, nil, monitorInfoReceiver, cast[LPARAM](table.addr))
  table

