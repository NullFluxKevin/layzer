
#------------------------------------------------------------------------------
# Widget Design Notes
#
# - Stateless widgets are just procs that take a `Buffer` and write to it.
#   They contain no internal state and exist purely to render a given visual.
#
# - Stateful widgets are objects that own a `Buffer` and maintain internal
#   state that affects rendering or behavior.
#
# When to make a widget stateful:
# - If it stores internal data.
# - If that data is updated via internal logic (e.g., a counter, toggle, etc.).
#
# When NOT to make a widget stateful:
# - If updates are just setting external values (no internal logic).
#   In that case, just pass data directly into a stateless proc.
#
# Example — NOT stateful:
#   proc update(label: Label, content: string) =
#     label.content = content
#     label.buffer.writeToLine(0, content)
#
#   This should be a stateless proc that draws to a buffer, since it simply
#   reflects external state.
#
# Example — Stateful:
#   proc inc(counter: var Counter) =
#     inc counter.count
#     counter.buffer.writeToLine(0, fmt"Count: {counter.count}")
#
#   This widget stores internal state (`count`) and encapsulates logic for
#   how that state is updated and displayed.
#------------------------------------------------------------------------------


import terminal
import strformat
import unicode

import tui/render/doubleBuffer
import layoutEngine
import tui/core


type
  Symbol = Rune

  BoxRegions = object
    borderTop, borderBottom, borderLeft, borderRight: Rect
    cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: Rect
    canvas: Rect
    
  Borders = object
    top, bottom, left, right: Buffer
    cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: Buffer

  Counter = object
    buffer: Buffer
    count: Natural


proc initCounter(rect: Rect): Counter =
  doAssert rect.height == 1

  result.buffer = newBuffer(rect)
  result.count = 0

  result.buffer.writeToLine(0, "Count: 0")


# render should do nothing but rendering the buffer.
# It should not flush states to the buffer.
proc render(counter: Counter) =
  counter.buffer.render()


# procs that updates states must write changes to the buffer
proc inc(counter: var Counter) =
  inc counter.count
  counter.buffer.writeToLine(0, fmt"Count: {counter.count}")
  
# resized creates and returns a new widget which has new dimentions and the old widget's states
proc resized(counter: Counter, rect: Rect): Counter = 
  result = initCounter(rect)
  result.count = counter.count
  # Very important:
  # Don't forget to actually write the copied state to the new buffer.
  result.buffer.writeToLine(0, fmt"Count: {result.count}")


proc toSymbol(s: string): Symbol = 
  doAssert s.runeLen == 1, "Error: Symbol must be a single character"
  s.runeAt(0)
  

proc drawLineH(buffer: Buffer, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}) =
  doAssert buffer.height == 1
  buffer.writeToLine(0, repeat(symbol, buffer.width), colors, styles)

proc drawLineV(buffer: Buffer, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}) =
  doAssert buffer.width == 1
  for i in 0 ..< buffer.height:
    buffer.writeToLine(i, $symbol, colors, styles)

proc drawSymbol(buffer: Buffer, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}) =
  doAssert buffer.width == 1 and buffer.height == 1
  buffer.writeToLine(0, $symbol, colors, styles)


proc toBoxRegions(rect: Rect): BoxRegions = 
  doAssert rect.width >= 3 and rect.height >= 3, "Error: Rect used to build the box must at least be 3x3"
  let
    verticalConstraints = @[
      Constraint(kind: ckLength, length: 1),
      Constraint(kind: ckLength, length: rect.height - 2),
      Constraint(kind: ckLength, length: 1),
    ]
    horizontalConstraints = @[
      Constraint(kind: ckLength, length: 1),
      Constraint(kind: ckLength, length: rect.width - 2),
      Constraint(kind: ckLength, length: 1),
    ]
    rows = layout(ldVertical, rect, verticalConstraints)
    (topRow, midRow, bottomRow) = (rows[0], rows[1], rows[2])

    topRowCols = layout(ldHorizontal, topRow, horizontalConstraints)
    midRowCols = layout(ldHorizontal, midRow, horizontalConstraints)
    bottomRowCols = layout(ldHorizontal, bottomRow, horizontalConstraints)

  (result.cornerTopLeft, result.borderTop, result.cornerTopRight) = (topRowCols[0], topRowCols[1], topRowCols[2])
  (result.borderLeft, result.canvas, result.borderRight) = (midRowCols[0], midRowCols[1], midRowCols[2])
  (result.cornerBottomLeft, result.borderBottom, result.cornerBottomRight) = (bottomRowCols[0], bottomRowCols[1], bottomRowCols[2])


proc initBorders(regions: BoxRegions): Borders =
  result.top = newBuffer(regions.borderTop)
  result.bottom = newBuffer(regions.borderBottom)
  result.left = newBuffer(regions.borderLeft)
  result.right = newBuffer(regions.borderRight)

  result.cornerTopLeft = newBuffer(regions.cornerTopLeft)
  result.cornerTopRight = newBuffer(regions.cornerTopRight)
  result.cornerBottomLeft = newBuffer(regions.cornerBottomLeft)
  result.cornerBottomRight = newBuffer(regions.cornerBottomRight)


proc drawTitleBorder(buffer: Buffer, content: string) =
  let
    rect = buffer.lines[0]
    sections = layout(ldHorizontal, rect,
      @[
        fixedLength(2),
        fixedLength(displayWidth(content)),
        minLength(0)
      ]
    )

  buffer.setLineContent(0,
    toSpan(sections[0], "──"),
    toSpan(sections[1], content),
    toSpan(sections[2], repeat("─".toSymbol, sections[2].width))
  )


proc render(borders: Borders) =
  borders.top.render()
  borders.bottom.render()
  borders.left.render()
  borders.right.render()

  borders.cornerTopLeft.render()
  borders.cornerTopRight.render()
  borders.cornerBottomLeft.render()
  borders.cornerBottomRight.render()
  

when isMainModule:
  

  let
    (maxWidth, maxHeight) = terminalSize()
    minHeight = 3

  var
    isRunning = true
    (width, height) = (maxWidth, maxHeight)
    minWidth = 3

    rect = initRect(0, 0, width, height)
    regions = toBoxRegions(rect)

    counterRect = layout(ldVertical, regions.canvas, @[fixedLength(1), minLength(0)])[0]

    resizeCounter = initCounter(counterRect)

  proc drawBox() = 
    regions = toBoxRegions(rect)
    var borders = initBorders(regions)

    let title = fmt"Size: {width} x {height}"
    minWidth = displayWidth(title) + 4 # why 4: left corner, two "─", right corner

    # borders.top.drawLineH("─".toSymbol)
    borders.top.drawTitleBorder(title)
    borders.bottom.drawLineH("─".toSymbol)
    borders.left.drawLineV("│".toSymbol)
    borders.right.drawLineV("│".toSymbol)

    borders.cornerTopLeft.drawSymbol("╭".toSymbol)
    borders.cornerTopRight.drawSymbol("╮".toSymbol)
    borders.cornerBottomLeft.drawSymbol("╰".toSymbol)
    borders.cornerBottomRight.drawSymbol("╯".toSymbol)

    borders.render()


  proc renderApp() =
    eraseScreen()
    drawBox()
    resizeCounter.render()

  proc resizeApp(width, height: int) = 
    rect = initRect(rect.x, rect.y, width, height)
    counterRect = layout(ldVertical, regions.canvas, @[fixedLength(1), minLength(0)])[0]
    resizeCounter = resizeCounter.resized(counterRect)
    inc resizeCounter


  proc onKeyPress(ctx: EventContext) =
    if not (ctx of KeyContext):
      return

    let c = KeyContext(ctx)
    let key = c.key
    
    if key == Key.Q or key == Key.CtrlC:
      println("Exiting...")
      isRunning = false

      eraseScreen()
      setCursorPos(0, 0)
      showCursor()

    elif key == Key.K:
      width = clamp(width + 1, minWidth, maxWidth)
      height = clamp(height + 1, minHeight, maxHeight)
      resizeApp(width, height)
      renderApp()
      
    elif key == Key.J:
      width = clamp(width - 1, minWidth, maxWidth)
      height = clamp(height - 1, minHeight, maxHeight)
      resizeApp(width, height)
      renderApp()


  proc onResize(ctx: EventContext) =
    if not (ctx of ResizeContext):
      return

    let c = ResizeContext(ctx)
    (width, height) = (c.width, c.height)
    resizeApp(width, height)
    renderApp()


  println("Press J and K to change box size; resize terminal to redraw fullscreen box.")
  println("Press Q or Ctrl-C to quit. Press anything to start the demo.")
  discard getch()

  hideCursor()

  renderApp()

  let tuiConfig = initTuiConfig()
  runTuiApp(tuiConfig, isRunning, onResize, onKeyPress):
    discard

