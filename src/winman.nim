import tables, sequtils, sets, strutils, options, sugar
import winim except RECT
import core, display_tree, winapiutils

const numAreas = 10

type 
  Hotkey = object
    key: int
    modifiers: HashSet[int]
  State = object
    trees: array[numAreas, DisplayTreeNode]
    managedWindows: TableRef[HWND, DisplayTreeNode]
    lastUsedWindow: Option[HWND]
    containerOrientationFlag: tuple[id: uint64, orient: Orientation] ## \
      ## The basic idea here is, that every command will have an id attached,
      ## which will start with 0 and then be increased with every command. And
      ## a grab window comand will look at the orientation, and respect it, if
      ## it was used as the last command. If it was longer ago, itl be ignored
    currentCommandId: uint64
    activeGroup: 1..10
  EventFunc = proc(s: var State){.gcSafe, closure.}
    
    
func getActiveTree(s: State): DisplayTreeNode = s.trees[s.activeGroup - 1]


func initHotkey(key: int, modifiers: HashSet[int]): Hotkey =
  Hotkey(key:key, modifiers:modifiers)


const modNames = {
  MOD_CONTROL: "CTRL",
  MOD_SHIFT: "SHIFT",
  MOD_ALT: "ALT"
}.toTable


func `$`(h: Hotkey): string =
  let mn = h.modifiers.toSeq.mapIt(modNames.getOrDefault(it, "?")).join(" + ")
  mn & " + " & h.key.char


func mergedModifiers(h: Hotkey): UINT =
  h.modifiers.toSeq.foldl(a or b, MOD_NOREPEAT)


proc register(hk: Hotkey, ev: Event): bool =
  RegisterHotkey(0, ev.ord.int32, hk.mergedModifiers, hk.key.UINT) != 0


func getHotkeys(): Table[Event, Hotkey] =
  let dm = [MOD_CONTROL, MOD_ALT, MOD_SHIFT].toHashSet
  func hk(key: char): Hotkey = initHotkey(key.ord, dm)
  {
    eGrabWindow: hk('G'),
    eRunLauncher: hk('R'),
    eAddSubGroupH: hk('Z'),
    eAddSubGroupV: hk('V'),
    eAddSubGroupD: hk('D'),
    eSelectWinU: hk('K'),
    eSelectWinD: hk('J'),
    eSelectWinL: hk('H'),
    eSelectWinR: hk('L'),
    eSelectWinF: hk('F'),
    eSelectWinB: hk('B'),
    eChangeOrientation: hk('C'),
    eSelectGroup1: hk('1'),
    eSelectGroup2: hk('2'),
  }.toTable

proc getMonitorRect(): Rect[int32] =
  var res: winim.RECT
  if SystemParametersInfo(SPI_GETWORKAREA, 0, &res, 0) == 0:
    error "Couldn't retrieve work area rect"
  initRect(res.left, res.top, res.right - res.left, res.bottom - res.top) 


template getForegroundWindowOrReturn(s: State, mustBeManaged: bool): untyped =
  let curWin = GetForegroundWindow()
  if curWin == 0 or (mustBeManaged and not (curWin in s.managedWindows)):
    return
  else:
    curWin


proc positionWindows(dtn: DisplayTreeNode) =
  for child in dtn.children:
    case child.kind:
      of dtkContainer: child.positionWindows()
      of dtkLeaf:
        discard
    
    var flags: UINT = SWP_ASYNCWINDOWPOS

    if dtn.orientation == oDeep:
      flags = flags or SWP_NOACTIVATE
    else:
      flags = flags or SWP_SHOWWINDOW

    let 
      cr = child.rect
      margin = getMargins(child.win)

    SetWindowPos(child.win, HWND_TOP, cr.x - margin.left,
                 cr.y - margin.top, cr.w + margin.left + margin.right - 1,
                 cr.h + margin.top + margin.bottom - 1, flags)


proc wrapLastWinInNewContainer(s: var State): DisplayTreeNode =
  let 
    lastWinNode = s.managedWindows[s.lastUsedWindow.get]
    newContainer = newContainerNode(s.containerOrientationFlag.orient,
                                    lastWinNode.rect)
    oldParent = lastWinNode.parent.get()

  oldParent.children.delete(oldParent.children.find(lastWinNode))
  newContainer.addChild lastWinNode
  oldParent.addChild newContainer
  newContainer


proc makeGrabWindow(): EventFunc =
  # While it looks completely unnecessary to return an anoymous proc here, it
  # is necessary, because this can be .closure. and either all or no
  # eventFunctions must have closures. And since the others have ...
  result = proc(s: var State) =
    let curWin = GetForegroundWindow()
    if curWin in s.managedWindows:
      return

    let curContainer =
      # if the user pressed one of the orentation keys, wrap the last window in a
      # container
      if s.containerOrientationFlag.id == s.currentCommandId - 1 and
          s.lastUsedWindow.isSome and
          s.lastUsedWindow.get in s.managedWindows:
        wrapLastWinInNewContainer s
      else:
        if s.lastUsedWindow.isSome and s.lastUsedWindow.get in s.managedWindows:
          s.managedWindows[s.lastUsedWindow.unsafeGet].parent.get()
        else:
          s.getActiveTree

    let newLeaf = curContainer.addNewWindow curWin
    s.managedWindows[curWin] = newLeaf
    curContainer.getAbsVersion(getMonitorRect()).positionWindows


proc makeOrientationFlagSetter(orient: Orientation): EventFunc =
  result = proc (s: var State) =
    s.containerOrientationFlag = (id: s.currentCommandId, orient: orient)


proc selectWin2D(s: var State, dir: Direction, targetOri: Orientation,
                 child: DisplayTreeNode) =
  assert targetOri in [oVertical, oHorizontal]
  let 
    root = child.getRoot
    areaOfInterest = child.rect.extend(initRect[float](0, 0, 1, 1), targetOri)
    candidates = root.getLeafNodes().
      filterIt(it.rect.intersects areaOfInterest)
    # the idea is, that the corners of all candidates windows are compared to
    # the currently selected window. Then they are either sorted horizontally
    # or vertically, and the smallest element, that is bigger than the
    # current window, or the biggest element that is smaller than the current
    # window is used.
    relWinCorners = collect(initTable(candidates.len)):
      for c in candidates:
        {c.rect.pos - child.rect.pos: c}
    comperator = toCmp[float](targetOri)
    (cmpTarget, getter) = case dir:
      of dirLeft, dirUp: (-1, (x: seq[Pos[float]]) => x[^1])
      of dirRight, dirDown: (1, (x: seq[Pos[float]]) => x[0])
      else:
        error "this should never happen"
    filteredCorners = toSeq(relWinCorners.keys).
      filterIt(comperator(it, initPos(0.0, 0.0)) == cmpTarget)

  # We either first filter all smaller corners, and get the largest, or all
  # larger ones and get the smallest. 
  if filteredCorners.len > 0:
    let newWin = relWinCorners[filteredCorners.getter]
    SetForegroundWindow newWin.win


proc selectWinDeep(s: var State, dir: Direction, child: DisplayTreeNode) =
  assert dir in [dirFront, dirBack]
  # this is very simple, we just go up the tree, until we finde a deep container,
  # und select the next or the previous child
  var 
    deepParent = none(DisplayTreeNode)
    currentNode = child
    lastNode = child
  while deepParent.isNone and currentNode.parent.isSome:
    lastNode = currentNode
    currentNode = currentNode.parent.get
    if currentNode.kind == dtkContainer and currentNode.orientation == oDeep:
      deepParent = some(currentNode)

  if deepParent.isSome:
    # nim follows the c tradition of the mod operator not actually implementing
    # modulo. -1 mod 3 should result in 2, but will result in -1. So I add the
    # length of the children once, to avoid negative numbers
    let 
      curIndex = deepParent.unsafeGet.children.find lastNode
      offset = if dir == dirFront: -1 else: 1
      nChildren = deepParent.unsafeGet.children.len
      newIndex = (curIndex + offset + nChildren) mod nChildren
    
    # the next child might be a container again, so we will go down to the
    # first leaf
    currentNode = deepParent.unsafeGet.children[newIndex]
    while currentNode.kind != dtkLeaf:
      currentNode = currentNode.children[0]
    SetForegroundWindow currentNode.win



proc selectWindowByDirection(s: var State, dir: Direction) =
  let 
    curWin = s.getForegroundWindowOrReturn(mustBeManaged=true)
    targetOri = dir.toOri
    child = s.managedWindows[curWin]

  if targetOri == oDeep:
    selectWinDeep s, dir, child
  else:
    selectWin2D s, dir, targetOri, child


proc makeSelectFunction(d: Direction): EventFunc =
  (s: var State) => selectWindowByDirection(s, d)

proc dispatch(ev: Event): EventFunc =
  case ev:
    of eGrabWindow: makeGrabWindow()
    of eAddSubGroupD: makeOrientationFlagSetter(oDeep)
    of eAddSubGroupH: makeOrientationFlagSetter(oHorizontal)
    of eAddSubGroupV: makeOrientationFlagSetter(oVertical)
    of eSelectWinU: makeSelectFunction(dirUp)
    of eSelectWinD: makeSelectFunction(dirDown)
    of eSelectWinL: makeSelectFunction(dirLeft)
    of eSelectWinR: makeSelectFunction(dirRight)
    of eSelectWinF: makeSelectFunction(dirFront)
    of eSelectWinB: makeSelectFunction(dirBack)
    else:
      error "Not Implemented"


proc initState(): State =
  # The state should store relative sizes, which get concretized, once its
  # clear on which monitor the windows should be displayed
  result = State(
      managedWindows: newTable[HWND, DisplayTreeNode](),
      containerOrientationFlag: (id: 0.uint64, orient: oHorizontal),
      currentCommandId: 2.uint64,
        # start at 2, so the initial orientation is ignored
      activeGroup: 1,
    )

  for i in 0..<numAreas:
    result.trees[i] = newContainerNode(oHorizontal, initRect[float](0, 0, 1, 1))


proc main()=
  echo "Started"
  let hotkeys = getHotkeys()
  for event, hk in hotkeys:
    if not hk.register(event):
      error "Couldn't register hotkey: ", hk

  var
    state = initState()
    run = true
    msg: MSG

  while run:
    GetMessage(msg, 0, 0, 0) 
    if msg.message == WM_HOTKEY:
      let handler = dispatch Event(msg.wparam)
      handler(state)
      state.currentCommandId.inc
      let curWin = GetForegroundWindow()
      if curWin in state.managedWindows:
        state.lastUsedWindow = if curWin != 0: some(curWin) else: none(HWND)


when isMainModule:
  main()
