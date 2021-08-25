import tables, sequtils, sets, strutils, options, sugar, std/monotimes, times,
  os, strutils
import winim except RECT
import core, display_tree, winapiutils

const numAreas = 10

type 
  Hotkey = object
    key: int
    modifiers: HashSet[int]
  GroupId = range[1..10]
  State = object
    trees: TableRef[GroupId, DisplayTreeNode]
    lastUsedWindow: TableRef[GroupId, Option[HWND]]
    monitorRects: TableRef[HMONITOR, Rect[int32]]
    monitorMap: TableRef[GroupId, HMONITOR]
    managedWindows: TableRef[HWND, DisplayTreeNode]
    containerOrientationFlag: tuple[id: uint64, orient: Orientation] ## \
      ## The basic idea here is, that every command will have an id attached,
      ## which will start with 0 and then be increased with every command. And
      ## a grab window comand will look at the orientation, and respect it, if
      ## it was used as the last command. If it was longer ago, itl be ignored
    currentCommandId: uint64
    currentMonitor: HMONITOR
    activeGroup: GroupId
    lastWindowCheck: MonoTime
  Config = object
    windowCheckInterval: Duration
  EventFunc = proc(s: var State): Option[HWND]{.gcSafe, closure.}
    
    
proc initState(): State =
  # The state should store relative sizes, which get concretized, once its
  # clear on which monitor the windows should be displayed
  let monRects = getMonitorRects()
  result = State(
      trees: newTable[GroupId, DisplayTreeNode](),
      managedWindows: newTable[HWND, DisplayTreeNode](),
      containerOrientationFlag: (id: 0.uint64, orient: oHorizontal),
      currentCommandId: 2.uint64,
        # start at 2, so the initial orientation is ignored
      activeGroup: 1,
      lastWindowCheck: getMonoTime(),
      lastUsedWindow: newTable[GroupId, Option[HWND]](),
      monitorRects: monRects,
      monitorMap: newTable[GroupId, HMONITOR](),
      currentMonitor: toSeq(monRects.keys)[0]
      )

  for x in GroupId.low..GroupId.high:
    result.lastUsedWindow[x] = none(HWND)
    result.trees[x] = newContainerNode(oHorizontal, initRect[float](0, 0, 1, 1))
    result.monitorMap[x] = toSeq(result.monitorRects.keys)[0]


proc initConfig(): Config =
  Config(
   windowCheckInterval: initDuration(milliseconds=500)
  )

func getActiveTree(s: State): DisplayTreeNode = s.trees[s.activeGroup]

proc getLastUsedWindowForActiveGroup(s: State): Option[HWND] =
  s.lastUsedWindow[s.activeGroup]

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


const otherKeyMappings = {
  '.': VK_OEM_PERIOD,
  ',': VK_OEM_COMMA,
  '+': VK_OEM_PLUS,
  '-': VK_OEM_MINUS,
}.toTable

proc toKeyCode(key: char): int =
  if key in 'A'..'Z' or key in '0'..'9':
    key.ord
  elif key in 'a'..'z':
    key.toUpperAscii.ord
  elif key in otherKeyMappings:
    otherKeyMappings[key]
  else:
    error "unrecognized key " & $key

proc getHotkeys(): Table[Event, Hotkey] =
  let dm = [MOD_ALT].toHashSet
  #let dm = [MOD_CONTROL, MOD_ALT, MOD_SHIFT].toHashSet
  proc hk(key: char): Hotkey = initHotkey(key.toKeyCode, dm)
  {
    eGrabWindow: hk('G'),
    eDropWindow: hk('E'),
    eTouchParent: hk('P'),
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
    eSelectGroup3: hk('3'),
    eSelectGroup4: hk('4'),
    eSelectGroup5: hk('5'),
    eSelectGroup6: hk('6'),
    eSelectGroup7: hk('7'),
    eSelectGroup8: hk('8'),
    eSelectGroup9: hk('9'),
    eSelectGroup10: hk('0'),
    eNextMonitor: hk('.'),
    ePrevMonitor: hk(',')
  }.toTable

proc getMonitorRect(): Rect[int32] =
  var res: winim.RECT
  if SystemParametersInfo(SPI_GETWORKAREA, 0, &res, 0) == 0:
    error "Couldn't retrieve work area rect"
  initRect(res.left, res.top, res.right - res.left, res.bottom - res.top) 

proc getCurrentMonitorRect(s: State): Rect[int32] =
  ## This function will be relevant later, when I support multiple Monitors
  s.monitorRects[s.monitorMap[s.activeGroup]]

template getForegroundWindowOrReturn(s: State, mustBeManaged: bool): untyped =
  let curWin = GetForegroundWindow()
  if curWin == 0 or (mustBeManaged and not (curWin in s.managedWindows)):
    return s.getLastUsedWindowForActiveGroup()
  else:
    curWin

proc positionWindows(dtn: DisplayTreeNode) =
  assert dtn.kind == dtkContainer
  for child in dtn.children:
    case child.kind:
      of dtkContainer:
        child.positionWindows()
        return
      of dtkLeaf:
        discard
    
    let (zPos, flags) = if dtn.orientation == oDeep:
      (HWND_TOP, SWP_NOACTIVATE.UINT)
    else:
      (HWND_TOPMOST, 0.UINT)

    let 
      cr = child.rect
      margin = getMargins(child.win)

    # Relevant Winapi quirks:
    #
    # 1. There are many functions, to bring a window to the top of the display
    # stack, but for some reason they dont work. The most reliable thing seems
    # to be to make a window topmost, which means its always on top, even if it
    # overlaps with the active window, and then remove topmost again
    # immediately.
    #
    # 2. The window size is larger than what is displayed, if you just tell the
    # windows to have the size you want, you will actually see gaps, when there
    # should be none, this is addressed by the margins.
    #
    # 3. If you move windows between monitors with different scaling, the size
    # will be computed according to the scale of the source monitor, and
    # consequently, the size will be wrong on the target monitor. Therefore
    # SetWindowPos is called twice, first moving the window, and then changing
    # its size. This will circumwent the provlem, although you will be able to
    # see them moving and then resizing, which is not nice, but the best I
    # could do in Windows
   
    SetWindowPos(child.win, zPos, cr.x - margin.left,
                 cr.y - margin.top, cr.w + margin.left + margin.right,
                 cr.h + margin.top + margin.bottom, flags or SWP_NOSIZE)
    SetWindowPos(child.win, zPos, cr.x - margin.left,
                 cr.y - margin.top, cr.w + margin.left + margin.right,
                 cr.h + margin.top + margin.bottom, flags or SWP_NOMOVE)
    if zPos == HWND_TOPMOST:
      SetWindowPos(
        child.win, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOSIZE or SWP_NOMOVE)

proc positionWindowsInActiveTree(s: State) =
    s.getActiveTree.getAbsVersion(s.getCurrentMonitorRect()).positionWindows

proc wrapLastWinInNewContainer(s: var State): DisplayTreeNode =
  let 
    lastWinNode = s.managedWindows[s.getLastUsedWindowForActiveGroup.get]
    newContainer = newContainerNode(s.containerOrientationFlag.orient,
                                    lastWinNode.rect)
    oldParent = lastWinNode.parent.get()

  oldParent.children.delete(oldParent.children.find(lastWinNode))
  newContainer.addChild lastWinNode
  oldParent.addChild newContainer
  newContainer


proc adjustForMissingWindows(state: var State) =
  ## As this is Windows, sooner or later, a window will be closed, and we wont
  ## know that happened. So we'll just check whether all windows that are
  ## supposed to exist still exist, and if they dont, adjust the tree.
  ## handles can be recycled, so it might happen that a new window has the old
  ## HWND, but as we check this quite frequently, I think the risk is minimal
  var deadNodes = collect(newSeq):
    for hwnd, node in state.managedWindows:
      if IsWindow(hwnd) == 0:
        node

  for node in deadNodes:
    let root = node.getRoot
    node.removeFromTree
    state.managedWindows.del(node.win)

    # remove the node from the last used windows, if it is in there
    for id in GroupId.low .. GroupId.high:
      if state.lastUsedWindow[id] == some(node.win):
        state.lastUsedWindow[id] = none(HWND)

  let activeTree = state.getActiveTree()
  if deadNodes.anyIt(it.getRoot() == activeTree):
    let absTree = activeTree.getAbsVersion(state.getCurrentMonitorRect())
    absTree.positionWindows()


proc makeGrabWindow(): EventFunc =
  # While it looks completely unnecessary to return an anoymous proc here, it
  # is necessary, because this can be .closure. and either all or no
  # eventFunctions must have closures. And since the others have ...
  result = proc(s: var State): Option[HWND] =
    let curWin = GetForegroundWindow()
    if curWin in s.managedWindows:
      return

    let curContainer =
      # if the user pressed one of the orentation keys, wrap the last window in a
      # container
      if s.containerOrientationFlag.id == s.currentCommandId - 1 and
          s.getLastUsedWindowForActiveGroup.isSome and
          s.getLastUsedWindowForActiveGroup.get in s.managedWindows:
        wrapLastWinInNewContainer s
      else:
        let last = s.getLastUsedWindowForActiveGroup()
        if last.isSome and last.get in s.managedWindows:
          s.managedWindows[last.unsafeGet].parent.get()
        else:
          s.getActiveTree

    let newLeaf = newLeafNode(curWin)
    curContainer.addNode newLeaf
    s.managedWindows[curWin] = newLeaf
    s.positionWindowsInActiveTree()
    return some(curWin)


proc makeDropWindow(): EventFunc =
  result = proc(s: var State): Option[HWND] =
    let 
      curWin = s.getForegroundWindowOrReturn(mustBeManaged=true)
      node = s.managedWindows[curWin]
      root = node.getRoot()
    node.removeFromTree()
    s.managedWindows.del(curWin)
    if s.getActiveTree() == root:
      s.positionWindowsInActiveTree()
    return none(HWND)


proc makeChangeOrientation(): EventFunc =
  result = proc(s: var State): Option[HWND] =
    let 
      curWin = s.getForegroundWindowOrReturn(mustBeManaged=true)
      parent = s.managedWindows[curWin].parent.get()
      pRect = parent.rect
      newOrientation = parent.orientation.next
      nChildren = parent.children.len.float

    parent.orientation = newOrientation
    let (w, h, xIncrement, yIncrement) = case newOrientation:
      of oDeep:
        (pRect.w, pRect.h, 0.0, 0.0)
      of oVertical:
        let winHeight = pRect.h / nChildren
        (pRect.w, winHeight, 0.0, winHeight)
      of oHorizontal:
        let winWidth = pRect.w / nChildren
        (winWidth, pRect.h, winWidth, 0.0)

    var (x, y) = (pRect.x, pRect.y)
    for c in parent.children:
      c.rect = initRect(x, y, w, h)
      x += xIncrement
      y += yIncrement
    s.positionWindowsInActiveTree()


proc makeOrientationFlagSetter(orient: Orientation): EventFunc =
  result = proc (s: var State): Option[HWND] =
    s.containerOrientationFlag = (id: s.currentCommandId, orient: orient)
    let win = s.getForegroundWindowOrReturn(mustBeManaged=true)
    return some(win)


proc selectWin2D(s: var State, dir: Direction, targetOri: Orientation,
                 child: DisplayTreeNode): Option[HWND] =
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
    return some(newWin.win)
  return none(HWND)


proc selectWinDeep(s: var State, dir: Direction, child: DisplayTreeNode):
    Option[HWND] =
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
    return some(currentNode.win)
  return none(HWND)


proc selectWindowByDirection(s: var State, dir: Direction): Option[HWND] =
  let 
    curWin = s.getForegroundWindowOrReturn(mustBeManaged=true)
    targetOri = dir.toOri
    child = s.managedWindows[curWin]

  if targetOri == oDeep:
    return selectWinDeep(s, dir, child)
  else:
    return selectWin2D(s, dir, targetOri, child)


proc makeSelectFunction(d: Direction): EventFunc =
  (s: var State) => selectWindowByDirection(s, d)


proc makeSelectGroup(i: GroupId): EventFunc =
  result = proc (s: var State): Option[HWND] =
    s.activeGroup = i
    let last = s.getLastUsedWindowForActiveGroup()
    s.positionWindowsInActiveTree()

    if last.isSome:
      SetForegroundWindow last.unsafeGet
    return last


proc makeChangeMonitor(dir: MonitorSelection): EventFunc =
  result = proc (s: var State): Option[HWND] =
    # there might be a new display by now, or one might have been disconnected
    s.monitorRects = getMonitorRects()
    let 
      curMon = s.monitorMap[s.activeGroup]
      newMon = if curMon in s.monitorRects:
        let 
          keys = toSeq s.monitorRects.keys
          ind = keys.find curMon
          newInd = case dir:
            of mPrev:
                if ind == keys.low: keys.high
                else: ind - 1
            of mNext:
              if ind == keys.high: keys.low
              else: ind + 1
        keys[newInd]
      else:
        toSeq(s.monitorRects.keys)[0]
    s.monitorMap[s.activeGroup] = newMon
    # if this is done only once, the sizes are messed up due to scaling, 
    # doing it a second time, will correct the sizes.
    s.positionWindowsInActiveTree()
    s.getLastUsedWindowForActiveGroup()


proc dispatch(ev: Event): EventFunc =
  case ev:
    of eGrabWindow: makeGrabWindow()
    of eDropWindow: makeDropWindow()
    of eChangeOrientation: makeChangeOrientation()
    of eAddSubGroupD: makeOrientationFlagSetter(oDeep)
    of eAddSubGroupH: makeOrientationFlagSetter(oHorizontal)
    of eAddSubGroupV: makeOrientationFlagSetter(oVertical)
    of eSelectWinU: makeSelectFunction(dirUp)
    of eSelectWinD: makeSelectFunction(dirDown)
    of eSelectWinL: makeSelectFunction(dirLeft)
    of eSelectWinR: makeSelectFunction(dirRight)
    of eSelectWinF: makeSelectFunction(dirFront)
    of eSelectWinB: makeSelectFunction(dirBack)
    of eSelectGroup1: makeSelectGroup(1)
    of eSelectGroup2: makeSelectGroup(2)
    of eSelectGroup3: makeSelectGroup(3)
    of eSelectGroup4: makeSelectGroup(4)
    of eSelectGroup5: makeSelectGroup(5)
    of eSelectGroup6: makeSelectGroup(6)
    of eSelectGroup7: makeSelectGroup(7)
    of eSelectGroup8: makeSelectGroup(8)
    of eSelectGroup9: makeSelectGroup(9)
    of eSelectGroup10: makeSelectGroup(10)
    of eNextMonitor: makeChangeMonitor(mNext)
    of ePrevMonitor: makeChangeMonitor(mPrev)
    else:
      echo "Not Implemented"
      (s: var State) => s.getLastUsedWindowForActiveGroup()


proc main()=
  echo "Started"
  let 
    hotkeys = getHotkeys()
    config = initConfig()
  for event, hk in hotkeys:
    if not hk.register(event):
      error "Couldn't register hotkey: ", hk

  var
    state = initState()
    run = true
    msg: MSG

  while run:
    #GetMessage(msg, 0, 0, 0) 
    if PeekMessage(msg, 0, 0, 0, PM_REMOVE) != 0:
      if msg.message == WM_HOTKEY:
        let 
          handler = dispatch Event(msg.wparam)
          curWin = handler(state)
        state.currentCommandId.inc
        if curWin.isSome:
          # kurz nachdem ich ein managed window geschlossen hatte, hat diese
          # assertion getriggert, allerdings erst nach erfolgreichem resizing
          # der anderen member
          # Allerdings vermutlich erst nachdem ich ein paar mal auf gruppe 1
          # gedrückt hatte, und das geschlossene Fenster war in Gruppe 2
          assert curWin.unsafeGet in state.managedWindows
        state.lastUsedWindow[state.activeGroup] = curWin
        state.getActiveTree.printTree()

    let now = getMonoTime()
    if (now - state.lastWindowCheck) >= config.windowCheckInterval:
      state.adjustForMissingWindows()
      state.lastWindowCheck = now
    sleep 5


when isMainModule:
  main()
