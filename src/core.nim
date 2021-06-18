import macros, sugar

type 
  Event* = enum
    eGrabWindow, eRunLauncher, eAddSubGroupH, eAddSubGroupV, eAddSubGroupD,
    eSelectWinU, eSelectWinD, eSelectWinL, eSelectWinR, eSelectWinF,
    eSelectWinB, eChangeOrientation, eSelectGroup1, eSelectGroup2,
    eSelectGroup3, eSelectGroup4, eSelectGroup5, eSelectGroup6, eSelectGroup7,
    eSelectGroup8, eSelectGroup9, eSelectGroup10
  Direction* = enum
    dirUp, dirDown, dirLeft, dirRight, dirFront, dirBack
  Rect*[T] = object
    x*, y*, w*, h*: T
  Size*[T] = object
    w*, h*: T
  Pos*[T] = object
    x*, y*: T
  Orientation* = enum
    oHorizontal, oVertical, oDeep

func initSize*[T](w, h: T): Size[T] = Size[T](w:w, h:h)
func initPos*[T](x, y: T): Pos[T] = Pos[T](x:x, y:y)
func initRect*[T](x, y, w, h: T): Rect[T] = Rect[T](x:x, y:y, w:w, h:h)

converter fRectToI32Rect(r: Rect[float]): Rect[int32] =
  initRect(r.x.int32, r.y.int32, r.w.int32, r.h.int32)

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


template error*(x: varargs[untyped]) =
  echo x
  quit 1

