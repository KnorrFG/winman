import macros, sugar, hashes, strformat

type 
  Event* = enum
    eGrabWindow, eRunLauncher, eAddSubGroupH, eAddSubGroupV, eAddSubGroupD,
    eSelectWinU, eSelectWinD, eSelectWinL, eSelectWinR, eSelectWinF,
    eSelectWinB, eChangeOrientation, eSelectGroup1, eSelectGroup2,
    eSelectGroup3, eSelectGroup4, eSelectGroup5, eSelectGroup6, eSelectGroup7,
    eSelectGroup8, eSelectGroup9, eSelectGroup10, eTouchParent, eDropWindow,
    eNextMonitor, ePrevMonitor
  Direction* = enum
    dirUp, dirDown, dirLeft, dirRight, dirFront, dirBack
  MonitorSelection* = enum
    mNext, mPrev
  Rect*[T] = object
    x*, y*, w*, h*: T
  Size*[T] = object
    w*, h*: T
  Pos*[T] = object
    x*, y*: T
  Orientation* = enum
    oHorizontal, oVertical, oDeep

template error*(x: varargs[untyped]) = echo x; quit 1

func initSize*[T](w, h: T): Size[T] = Size[T](w:w, h:h)
func initPos*[T](x, y: T): Pos[T] = Pos[T](x:x, y:y)
func initRect*[T](x, y, w, h: T): Rect[T] = Rect[T](x:x, y:y, w:w, h:h)

proc `$`*[T](x: Size[T]): string = x.repr
proc `$`*[T](x: Pos[T]): string = x.repr
proc `$`*[T](x: Rect[T]): string = x.repr
proc `$`*(x: Rect[float]): string =
  fmt"Rect({x.x:.2f}, {x.y:.2f}, {x.w:.2f}, {x.h:.2f})"
proc `$`*(x: Orientation): string =
  case x:
    of oHorizontal: "Horizontal"
    of oVertical: "Vertical"
    of oDeep: "Deep"

proc hash*[T](x: Pos[T]): Hash =
  var hash: Hash = 0
  result = !$(hash !& x.x.hash !& x.y.hash)

proc next*(o: Orientation): Orientation=
  if o == Orientation.high:
    Orientation.low
  else:
    succ o

func to*[T, T2](r: Rect[T2]): Rect[T] = initRect(r.x.T, r.y.T, r.w.T, r.h.T)
func to*[T, T2](r: Pos[T2]): Pos[T] = initPos(r.x.T, r.y.T)
func to*[T, T2](r: Size[T2]): Size[T] = initSize(r.w.T, r.h.T)

func right*[T](r: Rect[T]): T = r.x + r.w
func left*[T](r: Rect[T]): T = r.x
func top*[T](r: Rect[T]): T = r.y
func bottom*[T](r: Rect[T]): T = r.y + r.h
func size*[T](r: Rect[T]): Size[T] = initSize(r.w, r.h)
func pos*[T](r: Rect[T]): Pos[T] = initPos(r.x, r.y)

func `*`*[T, T2](r: Rect[T], s: Size[T2]): Rect[T] =
  initRect[T](T(r.x.float * s.w.float), T(r.y.float * s.h.float),
              T(r.w.float * s.w.float), T(r.h.float * s.h.float))

func `+`*[T, T2](r: Rect[T], p: Pos[T2]): Rect[T] =
  initRect[T](T(r.x + p.x), T(r.y + p.y), r.w, r.h)

func `-`*[T, T2](l: Pos[T], r: Pos[T2]): Pos[T] =
  initPos[T](T(l.x - r.x), T(l.y - r.y))

proc extend*[T](r: Rect[T], outer: Rect[T], o: Orientation): Rect[T] =
  ## Returns a version of r that either fills outer horizontally or vertically,
  ## depending on the given orientation. I.e. if r is the rect of a window, and
  ## outer is the screen, you will get r and the complete space left and right,
  ## or above and below r as result.
  case o:
    of oHorizontal:
      result = initRect(outer.left, r.top, outer.w, r.h)
    of oVertical:
      result = initRect(r.left, outer.top, r.w, outer.h)
    of oDeep:
      core.error "oDeep is not supported"


func intersects*[T](a, b: Rect[T]): bool =
  # actually, the logic dictates that it must be gt, rather than ge, but for my
  # purposes two windows cound as non overlapping on ge
  not (a.left >= b.right or b.left >= a.right or
       a.top >= b.bottom or b.top >= a.bottom)



func toOri*(d: Direction): Orientation =
  case d:
    of dirUp, dirDown: oVertical
    of dirLeft, dirRight: oHorizontal
    of dirFront, dirBack: oDeep

# ===========================================================================
# Cmp stuff
# ===========================================================================

type CmpFunc*[T] = proc(a, b: Pos[T]): int

proc cmpHorizontally[T](a, b: Pos[T]): int =
  result = cmp(a.x, b.x)
  if result == 0:
    result = cmp(a.y, b.y)

func cmpVertically[T](a, b: Pos[T]): int =
  result = cmp(a.y, b.y)
  if result == 0:
    result = cmp(a.x, b.x)

proc toCmp*[T](d: Orientation): CmpFunc[T] =
  case d:
    of oHorizontal: result = cmpHorizontally[T]
    of oVertical: result = cmpVertically[T]
    else:
      core.error "This isnt ment to be used with oDeep"
