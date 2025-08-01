
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
#
# Strict distinction between draw/write and render:
#   Anything with "draw/write" in its name is related to writing content to a buffer
#   Anything with "render" in its name is related to display a buffer on the screen
#------------------------------------------------------------------------------


import terminal
import tables
import strformat
import unicode

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
  BoxBuffers* = Table[BoxRegions, Buffer]

  # WARNING: BorderDrawingSymbols cantains only borders regions, accessing brCanvas will cause KeyError
  BorderDrawingSymbols* = Table[BoxRegions, Symbol]

  # Must use workaround to tell the compiler a proc is of type BorderRenderer:
  # 
  #   proc render(buffer: Buffer) = discard
  #   let br: BorderRenderer = render
  #   ...
  #   let renderers = {brBorderTop: br, ...}.toTable
  #   drawBorders(rect, renderers)
  # 
  # This workaround should be wrapped in a template/macro 
  BorderDrawer* = proc(buffer: Buffer)
  BorderDrawers* = Table[BoxRegions, BorderDrawer]


  # Maybe put errors somewhere else?
  SizeError* = object of ValueError
  ConstructTimeSizeError* = object of SizeError
  DrawTimeSizeError* = object of SizeError
  ContentExceedingBufferHeightDrawError* = object of DrawTimeSizeError
  ContentExceedingBufferWidthDrawError* = object of DrawTimeSizeError


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


proc toBoxRects*(rect: Rect): BoxRects {.raises: {ConstructTimeSizeError}.} = 
  if rect.width < 3 or rect.height < 3:
    raise newException(ConstructTimeSizeError, "To draw a box in a rect, it must be at least 3x3")
    
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


proc toBoxBuffers*(rects: BoxRects): BoxBuffers = 
  for region in BoxRegions:
    result[region] = newBuffer(rects[region])


proc drawBorders*(boxBuffers: BoxBuffers, symbols: BorderDrawingSymbols = roundedBorderSymbols, styles: SpanStyles = defaultSpanStyles) = 
  for region in BoxRegions:
    case region:
    of brBorderTop, brBorderBottom:
      boxBuffers[region].drawLineHorizontal(symbols[region], styles)

    of brBorderLeft, brBorderRight:
      boxBuffers[region].drawLineVertical(symbols[region], styles)

    of brCornerTopLeft,
      brCornerTopRight,
      brCornerBottomLeft,
      brCornerBottomRight:
      boxBuffers[region].writeSymbol(symbols[region], styles)

    of brCanvas:
      discard


proc drawBorders*(boxBuffers: BoxBuffers, drawers: BorderDrawers) = 
  for region in BoxRegions:
    if region == brCanvas: continue

    drawers[region](boxBuffers[region])


proc drawContentBorderHorizontal*(buffer: Buffer,
   text: string,
   symbol: Symbol,
   styles: SpanStyles = defaultSpanStyles,
   textPosOffset: Natural = 2) {.raises: {ContentExceedingBufferWidthDrawError}.} =

  let textWidth = displayWidth(text)
  if textWidth + textPosOffset > buffer.width:
    raise newException(ContentExceedingBufferWidthDrawError, fmt"Text display width: {textWidth}; Buffer width: {buffer.width}")

  var content = repeat(symbol, textPosOffset)
  content &= text
  content &= repeat(symbol, buffer.width - displayWidth(content))

  buffer.writeHorizontal(content, styles)


proc drawContentBorderVertical*(buffer: Buffer,
   text: string,
   symbol: Symbol,
   styles: SpanStyles = defaultSpanStyles,
   textPosOffset: Natural = 2) {.raises: {ContentExceedingBufferHeightDrawError}.} = 

  let textRuneLen = text.runeLen
  if textRuneLen + textPosOffset > buffer.height:
    raise newException(ContentExceedingBufferHeightDrawError, fmt"Text length: {textRuneLen}; Buffer height: {buffer.height}")

  var content = repeat(symbol, textPosOffset)
  content &= text
  content &= repeat(symbol, buffer.height - content.runeLen)

  buffer.writeVertical(content, styles)


proc drawContentBorderHorizontal*(buffer: Buffer,
   text: string,
   symbol: Symbol,
   textStyles: SpanStyles = defaultSpanStyles,
   symbolStyles: SpanStyles = defaultSpanStyles,
   textPosOffset: Natural = 2) {.raises: {ContentExceedingBufferWidthDrawError}.} =

  doAssert buffer.height == 1, "Error: Horizontal border can only be draw to buffers of height 1"

  let textWidth = displayWidth(text)
  if textWidth + textPosOffset > buffer.width:
    raise newException(ContentExceedingBufferWidthDrawError, fmt"Text display width: {textWidth}; Buffer width: {buffer.width}")


  let
    remainLen = buffer.width - textWidth - textPosOffset

    rect = buffer.lines[0]
    sections = layout(ldHorizontal, rect, @[
      fixedLength(textPosOffset),
      fixedLength(textWidth),
      fixedLength(remainLen),
    ])

    spans = @[
      toSpan(sections[0], repeat(symbol, textPosOffset), symbolStyles),
      toSpan(sections[1], text, textStyles),
      toSpan(sections[2], repeat(symbol, remainLen), symbolStyles),
    ]

  buffer.setLineContent(0, spans)


proc drawContentBorderVertical*(buffer: Buffer,
   text: string,
   symbol: Symbol,
   textStyles: SpanStyles = defaultSpanStyles,
   symbolStyles: SpanStyles = defaultSpanStyles,
   textPosOffset: Natural = 2) {.raises: {ContentExceedingBufferHeightDrawError}.} = 

  doAssert buffer.width == 1, "Error: Vertical border can only be draw to buffers of width 1"

  let textRuneLen = text.runeLen
  if textRuneLen + textPosOffset > buffer.height:
    raise newException(ContentExceedingBufferHeightDrawError, fmt"Text length: {textRuneLen}; Buffer height: {buffer.height}")


  var content = repeat(symbol, textPosOffset)
  content &= text
  content &= repeat(symbol, buffer.height - content.runeLen)

  for lineNumber, rune in content.toRunes:
    var currentStyles: SpanStyles
    if lineNumber < textPosOffset or lineNumber >= textPosOffset + textRuneLen:
      currentStyles = symbolStyles
    else:
      currentStyles = textStyles

    buffer.writeToLine(lineNumber, $rune, currentStyles)
 

when isMainModule:
  let
    gTitleStyle = initSpanStyles(fgYellow, bgDefault)
    gStyleOK = initSpanStyles(fgCyan, bgDefault)
    gStyleReachMinSize = initSpanStyles(fgRed, bgDefault)

  var
    (gMaxWidth, gMaxHeight) = terminalSize()
    gIsRunning = true
    gRect = initRect(0, 0, gMaxWidth, gMaxHeight)
    gBoxRects = toBoxRects(gRect)
    gBoxBuffers = toBoxBuffers(gBoxRects)
    gStyles = gStyleOK


  let
    gBorderBottomDrawer: BorderDrawer = proc(buffer: Buffer) = drawLineHorizontal(buffer, "=".toSymbol, gStyles)

    gBorderVerticalDrawer: BorderDrawer = proc(buffer: Buffer) = drawLineVertical(buffer, "#".toSymbol, gStyles)

    gTitleBorderLeftDrawer: BorderDrawer = proc(buffer: Buffer) = drawContentBorderVertical(buffer, "Layzer", "|".toSymbol, gTitleStyle, gStyles)

    gBorderCornerDrawer: BorderDrawer = proc(buffer: Buffer) = writeSymbol(buffer, "+".toSymbol, gStyles)

  var gDrawers = {
    brBorderBottom: gBorderBottomDrawer,
    brBorderLeft: gTitleBorderLeftDrawer,
    brBorderRight: gBorderVerticalDrawer,
    brCornerTopLeft: gBorderCornerDrawer,
    brCornerTopRight: gBorderCornerDrawer,
    brCornerBottomLeft: gBorderCornerDrawer,
    brCornerBottomRight: gBorderCornerDrawer,
  }.toTable


  proc drawApp() =
    let title = fmt"Size: {gRect.width} x {gRect.height}"
    let titleBorderTopDrawer: BorderDrawer = proc(buffer: Buffer) = drawContentBorderHorizontal(buffer, title, "-".toSymbol, gTitleStyle, gStyles)

    gDrawers[brBorderTop] = titleBorderTopDrawer

    drawBorders(gBoxBuffers, gDrawers)


  proc renderApp() =
    eraseScreen()
    for _, buffer in gBoxBuffers:
      buffer.render()


  proc resizeApp(newWidth, newHeight: Natural) = 

    let
      rectBackup = gRect
      newRect = initRect(gRect.x, gRect.y, newWidth, newHeight)

    gRect = newRect

    try:
      gBoxRects = toBoxRects(gRect)
      gBoxBuffers = toBoxBuffers(gBoxRects)
      drawApp()
      renderApp()
    except SizeError: 
      gStyles = gStyleReachMinSize
      # This creates new buffers with the old rect and renders,
      # it's a little wasteful but good enough for MVP
      # Maybe move to a transactional design when needed? If draw with the new rect/buffer is successful, commit the new rect and buffer; otherwise, do nothing
      resizeApp(rectBackup.width, rectBackup.height)


  proc onKeyPress(ctx: EventContext) =
    if not (ctx of KeyContext):
      return

    gStyles = gStyleOK

    let c = KeyContext(ctx)
    let key = c.key
    
    case key:
    of Key.Q, Key.CtrlC:
      println("Exiting...")
      gIsRunning = false

      eraseScreen()
      setCursorPos(0, 0)
      showCursor()

    of Key.H:
      let newWidth = min(gRect.width - 1, gMaxWidth)
      resizeApp(newWidth, gRect.height)

    of Key.L:
      let newWidth = min(gRect.width + 1, gMaxWidth)
      resizeApp(newWidth, gRect.height)

    of Key.K:
      let newHeight = min(gRect.height + 1, gMaxHeight)
      resizeApp(gRect.width, newHeight)
      
    of Key.J:
      let newHeight = min(gRect.height - 1, gMaxHeight)
      resizeApp(gRect.width, newHeight)

    else:
      discard


  proc onResize(ctx: EventContext) =
    if not (ctx of ResizeContext):
      return

    gStyles = gStyleOK
    let c = ResizeContext(ctx)
    (gMaxWidth, gMaxHeight) = (c.width, c.height)
    resizeApp(gMaxWidth, gMaxHeight)


  println("Press H J K L to change box size; resize terminal to redraw fullscreen box.")
  println("Press Q or Ctrl-C to quit. Press anything to start the demo.")
  discard getch()

  hideCursor()

  drawApp()
  renderApp()

  let tuiConfig = initTuiConfig()
  runTuiApp(tuiConfig, gIsRunning, onResize, onKeyPress):
    discard

