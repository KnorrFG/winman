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
    oldParent = lastWinNode.parent

  oldParent.children.delete(oldParent.children.find(lastWinNode))
  newContainer.addChild lastWinNode
  oldParent.addChild newContainer
  newContainer


proc grabWindow(s: var State) =
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
        s.managedWindows[s.lastUsedWindow.unsafeGet].parent
      else:
        s.getActiveTree

  let newLeaf = curContainer.addNewWindow curWin
  s.managedWindows[curWin] = newLeaf
  curContainer.getAbsVersion(getMonitorRect()).positionWindows


proc makeOrientationFlagSetter(orient: Orientation): EventFunc =
  result = proc (s: var State) =
    s.containerOrientationFlag = (id: s.currentCommandId, orient: orient)

proc selectWindowByDirection(s: var State, dir: Direction) =
  discard

proc makeSelectFunction(d: Direction): EventFunc =
  (s: var State) => selectWindowByDirection(s, d)

proc errorProc(s: var State) = error "Not Implemented"

proc dispatch(ev: Event): EventFunc =
  case ev:
    of eGrabWindow: grabWindow
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
      state.lastUsedWindow = if curWin != 0: some(curWin) else: none(HWND)


when isMainModule:
  main()
