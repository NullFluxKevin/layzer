
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
#
# Stateful Widget Interface:
#   init/new proc creates, assigns values to states and returns the widget.
#   procs with appropirate names that will update the widget's inner states AND WRITES the changes to the buffer.
#   `proc render(w: Widget)` will DO NOTHING BUT rendering the widget's buffer. It SHOULD NOT FLUSH states to the buffer before rendering.
#   `proc resized(w: Widget, newRect: Rect): Widget` creates and returns a new widget with newRect. The states of the old widget are copied to the new widget AND FLUSHED to the new widget's buffer.
#------------------------------------------------------------------------------


import terminal
import tables

import tui/render/doubleBuffer
import tui/render/bufferWriters
import layoutEngine
import tui/core


type
  BoxRegions* = enum
    brBorderTop, brBorderBottom, brBorderLeft, brBorderRight
    brCornerTopLeft, brCornerTopRight, brCornerBottomLeft, brCornerBottomRight
    brCanvas
    
  BoxRects* = Table[BoxRegions, Rect]

  # WARNING: BorderDrawingSymbols cantains only borders regions, accessing brCanvas will cause KeyError
  BorderDrawingSymbols* = Table[BoxRegions, Symbol]


let
    singleBorderSymbols*: BorderDrawingSymbols = {
      brBorderTop: "─".toSymbol,
      brBorderBottom: "─".toSymbol,
      brBorderLeft: "│".toSymbol,
      brBorderRight: "│".toSymbol,
      brCornerTopLeft: "┌".toSymbol,
      brCornerTopRight: "┐".toSymbol,
      brCornerBottomLeft: "└".toSymbol,
      brCornerBottomRight: "┘".toSymbol
    }.toTable

    doubleBorderSymbols*: BorderDrawingSymbols = {
      brBorderTop: "═".toSymbol,
      brBorderBottom: "═".toSymbol,
      brBorderLeft: "║".toSymbol,
      brBorderRight: "║".toSymbol,
      brCornerTopLeft: "╔".toSymbol,
      brCornerTopRight: "╗".toSymbol,
      brCornerBottomLeft:"╚".toSymbol,
      brCornerBottomRight: "╝".toSymbol
    }.toTable

    roundedBorderSymbols*: BorderDrawingSymbols = {
      brBorderTop: "─".toSymbol,
      brBorderBottom: "─".toSymbol,
      brBorderLeft: "│".toSymbol,
      brBorderRight: "│".toSymbol,
      brCornerTopLeft: "╭".toSymbol,
      brCornerTopRight: "╮".toSymbol,
      brCornerBottomLeft: "╰".toSymbol,
      brCornerBottomRight: "╯".toSymbol
    }.toTable    
    


proc drawLineHorizontal*(buffer: Buffer, symbol: Symbol, styles: SpanStyles = defaultSpanStyles) =
  buffer.writeHorizontal(repeat(symbol, buffer.width), styles)


proc drawLineVertical*(buffer: Buffer, symbol: Symbol, styles: SpanStyles = defaultSpanStyles) =
  buffer.writeVertical(repeat(symbol, buffer.height), styles)


proc toBoxRects*(rect: Rect): BoxRects = 
  doAssert rect.width >= 3 and rect.height >= 3, "Error: Rect used to build the box must at least be 3x3"
  let
    verticalConstraints = @[
      fixedLength(1),
      fixedLength(rect.height - 2),
      fixedLength(1),
    ]
    horizontalConstraints = @[
      fixedLength(1),
      fixedLength(rect.width - 2),
      fixedLength(1),
    ]
    rows = layout(ldVertical, rect, verticalConstraints)
    (topRow, midRow, bottomRow) = (rows[0], rows[1], rows[2])

    topRowCols = layout(ldHorizontal, topRow, horizontalConstraints)
    midRowCols = layout(ldHorizontal, midRow, horizontalConstraints)
    bottomRowCols = layout(ldHorizontal, bottomRow, horizontalConstraints)

  result[brCornerTopLeft] = topRowCols[0]
  result[brBorderTop] = topRowCols[1]
  result[brCornerTopRight] = topRowCols[2]

  result[brBorderLeft] = midRowCols[0]
  result[brCanvas] = midRowCols[1]
  result[brBorderRight] = midRowCols[2]

  result[brCornerBottomLeft] = bottomRowCols[0]
  result[brBorderBottom] = bottomRowCols[1]
  result[brCornerBottomRight] = bottomRowCols[2]


proc drawBorders*(boxRects: BoxRects, symbols: BorderDrawingSymbols = roundedBorderSymbols) = 
  for region in low(BoxRegions) .. high(BoxRegions):
    case region:
    of brBorderTop, brBorderBottom:
      let buffer = newBuffer(boxRects[region])
      buffer.drawLineHorizontal(symbols[region])
      buffer.render()

    of brBorderLeft, brBorderRight:
      let buffer = newBuffer(boxRects[region])
      buffer.drawLineVertical(symbols[region])
      buffer.render()

    of brCornerTopLeft,
      brCornerTopRight,
      brCornerBottomLeft,
      brCornerBottomRight:
      let buffer = newBuffer(boxRects[region])
      buffer.writeSymbol(symbols[region])
      buffer.render()

    of brCanvas:
      discard

    
proc drawBorders*(rect: Rect, symbols: BorderDrawingSymbols = roundedBorderSymbols) = 
  let boxRects = toBoxRects(rect)
  drawBorders(boxRects, symbols)


when isMainModule:
  
  let
    (maxWidth, maxHeight) = terminalSize()
    minHeight = 3

  var
    isRunning = true
    (width, height) = (maxWidth, maxHeight)
    minWidth = 3

    rect = initRect(0, 0, width, height)


  proc renderApp() =
    eraseScreen()
    drawBorders(rect)


  proc resizeApp(width, height: int) = 
    rect = initRect(rect.x, rect.y, width, height)


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

