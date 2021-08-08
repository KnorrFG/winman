import winim except RECT
import core, options, sugar, strformat, sequtils, strutils

type
  DisplayTreeNodeKind* = enum
    dtkLeaf, dtkContainer
  DisplayTreeNode* = ref object
    rect*: Rect[float]
    parent*: Option[DisplayTreeNode]
    case kind*: DisplayTreeNodeKind
    of dtkLeaf:
      win*: HWND
    of dtkContainer:
      orientation*: Orientation
      children*: seq[DisplayTreeNode]


const defaultRect = initRect[float](0, 0, 0, 0)

func newContainerNode*(orientation: Orientation, rect: Rect[float]):
    DisplayTreeNode =
  DisplayTreeNode(rect: rect, kind: dtkContainer, orientation: orientation,
                  children: @[])


func newLeafNode*(win: HWND, rect: Rect[float] = defaultRect): DisplayTreeNode =
  DisplayTreeNode(rect: rect, kind: dtkLeaf, win: win)


using dtn: DisplayTreeNode

proc `$`*(dtn): string =
  case dtn.kind:
    of dtkLeaf:
      fmt"Leaf(rect: {dtn.rect}, win: {dtn.win})"
    of dtkContainer:
      fmt"Container({dtn.orientation}, rect: {dtn.rect}, nChildren: {dtn.children.len})"


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
  ## Resizes all elements of an container proportionally to match its new size.
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
            var tmp = newRect
            tmp.x = offset
            tmp.w = child.rect.w * factor
            offset += tmp.w
            tmp
          of oVertical:
            var tmp = newRect
            tmp.y = offset
            tmp.h = child.rect.h * factor
            offset += tmp.h
            tmp
          of oDeep:
            newRect
        child.reposition(newChildRect)
      dtn.rect = newRect

proc addNode*(dtn; newNode: DisplayTreeNode)=
  if dtn.kind != dtkContainer:
    raise ValueError.newException("Only container can use this proc")

  var newWinRect = dtn.rect
  if dtn.children.len == 0:
    newNode.rect = newWinRect
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
    newNode.rect = newWinRect
  dtn.addChild newNode


func getAbsVersion*(dtn; dims: Rect): DisplayTreeNode =
  let newRect = dtn.rect * dims.size + dims.pos
  case dtn.kind:
    of dtkContainer:
      result = newContainerNode(dtn.orientation, newRect)
      for child in dtn.children:
        result.addChild(child.getAbsVersion(dims))
    of dtkLeaf:
      result = newLeafNode(dtn.win, newRect)


func isRoot(dtn): bool = dtn.parent.isNone

func getRoot*(dtn): DisplayTreeNode =
  result = dtn
  while not result.isRoot:
    result = result.parent.unsafeget

func getLeafNodes*(dtn): seq[DisplayTreeNode] =
  var leafs = result
  discard dtn.forNode proc(it: DisplayTreeNode): Option[void] =
    if it.kind == dtkLeaf:
      leafs.add it
    result = none(void)
  result = leafs

proc removeFromTree*(dtn) =
  ## Removes one element from the tree, and then resizes the rest. As this
  ## would becok

  # If the current window is the only child of a container, the container is
  # removed instead, but only if it isnt the root
  if dtn.isRoot():
    error "you cannot remove the root node"
  let parent = dtn.parent.unsafeget()
  if not parent.isRoot and parent.children.len() == 1:
    parent.removeFromTree()
    return

  parent.children.del(parent.children.find(dtn))

  let origRect = parent.rect
  case parent.orientation:
    of oDeep: return
    of oHorizontal:
      parent.rect.w -= dtn.rect.w
    of oVertical:
      parent.rect.h -= dtn.rect.h
  parent.reposition origRect

proc printTree*(dtn; indentLevel=0)=
  if indentLevel == 0:
    echo "\p"
  echo("  ".repeat(indentLevel).join() & $dtn)
  if dtn.kind == dtkContainer:
    for child in dtn.children:
      child.printTree(indentLevel + 1)
