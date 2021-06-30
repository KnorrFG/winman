import winim except RECT
import core, options, sugar, strformat

type
  DisplayTreeNodeKind* = enum
    dtkLeaf, dtkContainer
  DisplayTreeNode* = ref object
    rect*: Rect[float]
    parent: Option[DisplayTreeNode]
    case kind*: DisplayTreeNodeKind
    of dtkLeaf:
      win*: HWND
    of dtkContainer:
      orientation*: Orientation
      children*: seq[DisplayTreeNode]


func newContainerNode*(orientation: Orientation, rect: Rect[float]):
    DisplayTreeNode =
  DisplayTreeNode(rect: rect, kind: dtkContainer, orientation: orientation,
                  children: @[])


func newLeafNode*(win: HWND, rect: Rect[float]): DisplayTreeNode =
  DisplayTreeNode(rect: rect, kind: dtkLeaf, win: win)


using dtn: DisplayTreeNode

proc `$`*(dtn): string =
  case dtn.kind:
    of dtkLeaf:
      fmt"Leaf(rect: {dtn.rect}, win: {dtn.win})"
    of dtkContainer:
      fmt"Container({dtn.orientation}, rect: {dtn.rect}, nChildren: {dtn.children.len})"

func parent*(dtn): DisplayTreeNode = dtn.parent.get()

proc addChild*(dtn; child: DisplayTreeNode) =
  dtn.children.add(child)
  child.parent = some(dtn)

proc forNode*[T](dtn; callback: proc(dtn: DisplayTreeNode): Option[T]):
    Option[T] =
  let res = callback dtn
  if res.isSome:
    return res
  if dtn.kind != dtkLeaf:
    for child in dtn.children:
      let childRes = child.forNode callback
      if childRes.isSome:
        return childRes

func findLeaf*(dtn; win: HWND): Option[DisplayTreeNode] =
  dtn.forNode proc(it: DisplayTreeNode): Option[DisplayTreeNode] =
    if it.kind == dtkLeaf and it.win == win:
      return some(it)

proc reposition*(dtn; newRect: Rect) =
  if dtn.rect == newRect:
    return

  case dtn.kind:
    of dtkLeaf:
      dtn.rect = newRect
    of dtkContainer:
      var offset: float = case dtn.orientation:
        of oHorizontal, oDeep: dtn.rect.x
        of oVertical: dtn.rect.y

      let factor: float = case dtn.orientation:
        of oHorizontal: newRect.w / dtn.rect.w
        of oVertical: newRect.h / dtn.rect.h
        of oDeep: 0

      for child in dtn.children:
        let newChildRect = case dtn.orientation:
          of oHorizontal:
            var tmp = child.rect
            tmp.x = offset
            tmp.w = child.rect.w * factor
            offset += child.rect.w
            tmp
          of oVertical:
            var tmp = child.rect
            tmp.y = offset
            tmp.h = child.rect.h * factor
            offset += child.rect.h
            tmp
          of oDeep:
            newRect
        child.reposition(newChildRect)
      dtn.rect = newRect

func addNewWindow*(dtn; win: HWND): DisplayTreeNode =
  if dtn.kind != dtkContainer:
    raise ValueError.newException("Only container can use this proc")

  var newWinRect = dtn.rect
  if dtn.children.len == 0:
    result = newLeafNode(win, newWinRect)
  else:
    let 
      nc = dtn.children.len.float
      factor = nc / (nc + 1.0)
      origRect = dtn.rect

    var newRect = dtn.rect
    case dtn.orientation:
      of oHorizontal: newRect.w *= factor
      of oVertical: newRect.h *= factor
      of oDeep: discard
    # This will shrink the current container
    dtn.reposition newRect

    case dtn.orientation
    of oDeep:
      discard
    of oHorizontal:
        newWinRect.x = dtn.rect.right
        newWinRect.w = dtn.rect.w / nc
    of oVertical:
        newWinRect.y = dtn.rect.bottom
        newWinRect.h = dtn.rect.h / nc

    # as we added a new window, so that it goes back to its original size, we
    # need to adjust the size to the orig size
    dtn.rect = origRect
    result = newLeafNode(win, newWinRect)
  dtn.addChild result


func getAbsVersion*(dtn; dims: Rect): DisplayTreeNode =
  let newRect = dtn.rect * dims.size + dims.pos
  case dtn.kind:
    of dtkContainer:
      result = newContainerNode(dtn.orientation, newRect)
      for child in dtn.children:
        result.addChild(child.getAbsVersion(dims))
    of dtkLeaf:
      result = newLeafNode(dtn.win, newRect)


func getRoot*(dtn): DisplayTreeNode =
  result = dtn
  while result.parent.isSome:
    result = result.parent.unsafeget


func getLeafNodes*(dtn): seq[DisplayTreeNode] =
  var leafs = result
  discard dtn.forNode proc(it: DisplayTreeNode): Option[void] =
    if it.kind == dtkLeaf:
      leafs.add it
    result = none(void)
  result = leafs
