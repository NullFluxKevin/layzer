import unicode

import tui/core
import tui/render/doubleBuffer
import layoutEngine


# Naming convention: the thing + its direction/Position e.g. BorderHorizontal, CornerLeftTop
 
type
  Symbol = Rune

  LineHorizontal = object
    symbol: Symbol
    # these three seem to repeat in widgets, might be grouped into another object for reuse
    buffer: Buffer
    colors: SpanColors
    styles: set[Style]

  LineVertical = object
    symbol: Symbol
    buffer: Buffer
    colors: SpanColors
    styles: set[Style]

  Cell = object
    symbol: Symbol
    buffer: Buffer
    colors: SpanColors
    styles: set[Style]

  BoxDrawingSymbolKind = enum
    bdskHorizontal,
    bdskVertical,
    bdskTopLeft,
    bdskTopRight,
    bdskBottomLeft,
    bdskBottomRight
  
  BoxDrawingSymbols = array[BoxDrawingSymbolKind, Symbol]

  Box = object
    borderTop, borderBottom: LineHorizontal
    borderLeft, borderRight: LineVertical
    cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: Cell
    canvas: Rect
    symbols: BoxDrawingSymbols
    colors: SpanColors
    styles: set[Style]

  BoxRegions = object
    borderTop, borderBottom, borderLeft, borderRight: Rect
    cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: Rect
    canvas: Rect
    

proc toSymbol(s: string): Symbol = 
  doAssert s.runeLen == 1, "Error: Symbol must be a single character"
  s.runeAt(0)
  

proc initLineHorizontal(rect: Rect, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): LineHorizontal =
  doAssert rect.height == 1, "Error: Horizontal line must have height of 1"
  let buffer = newBuffer(rect)
  LineHorizontal(buffer: buffer, symbol: symbol, colors: colors, styles: styles)


proc resized(line: LineHorizontal, rect: Rect): LineHorizontal =
  initLineHorizontal(rect, line.symbol, line.colors, line.styles)


proc updateContent(line: LineHorizontal) = 
  line.buffer.writeToLine(0, repeat(line.symbol, line.buffer.width), line.colors, line.styles)


proc buildFrame(line: LineHorizontal): Frame = 
  line.buffer.buildFrame()


proc render(line: LineHorizontal) =
  drawFrame(line.buildFrame())


proc initCell(rect: Rect, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): Cell = 
  doAssert rect.width == 1 and rect.height == 1, "Error: Cell must be a 1x1 rect"
  let buffer = newBuffer(rect)
  Cell(buffer: buffer, symbol: symbol, colors: colors, styles: styles)


proc updateContent(cell: Cell) = 
  cell.buffer.writeToLine(0, $cell.symbol)


proc resized(cell: Cell, rect: Rect): Cell =
  initCell(rect, cell.symbol, cell.colors, cell.styles)


proc buildFrame(cell: Cell): Frame =
  cell.buffer.buildFrame()


proc render(cell: Cell) = 
  drawFrame(cell.buildFrame())


proc initLineVertical(rect: Rect, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): LineVertical =
  doAssert rect.width == 1, "Error: Vertical line must have width of 1"
  let buffer = newBuffer(rect)
  LineVertical(buffer: buffer, symbol: symbol, colors: colors, styles: styles)


proc updateContent(line: LineVertical) = 
  for i in 0 ..< line.buffer.height:
    line.buffer.writeToLine(i, $line.symbol, line.colors, line.styles)


proc resized(line: LineVertical, rect: Rect): LineVertical =
  initLineVertical(rect, line.symbol, line.colors, line.styles)


proc buildFrame(line: LineVertical): Frame = 
  line.buffer.buildFrame()


proc render(line: LineVertical) =
  drawFrame(line.buildFrame())


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


proc initBox(rect: Rect, symbols: BoxDrawingSymbols, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): Box = 

  result.symbols = symbols
  result.colors = colors
  result.styles = styles

  let regions = rect.toBoxRegions

  result.borderTop = initLineHorizontal(regions.borderTop, symbols[bdskHorizontal], colors, styles)
  result.borderBottom = initLineHorizontal(regions.borderBottom, symbols[bdskHorizontal], colors, styles)
  result.borderLeft = initLineVertical(regions.borderLeft, symbols[bdskVertical], colors, styles)
  result.borderRight = initLineVertical(regions.borderRight, symbols[bdskVertical], colors, styles)

  result.cornerTopLeft = initCell(regions.cornerTopLeft, symbols[bdskTopLeft], colors, styles)
  result.cornerTopRight = initCell(regions.cornerTopRight, symbols[bdskTopRight], colors, styles)
  result.cornerBottomLeft = initCell(regions.cornerBottomLeft, symbols[bdskBottomLeft], colors, styles)
  result.cornerBottomRight = initCell(regions.cornerBottomRight, symbols[bdskBottomRight], colors, styles)

  result.canvas = regions.canvas


proc setSymbols(box: var Box, symbols: BoxDrawingSymbols) =
  box.borderTop.symbol = symbols[bdskHorizontal]
  box.borderBottom.symbol = symbols[bdskHorizontal]
  box.borderLeft.symbol = symbols[bdskVertical]
  box.borderRight.symbol = symbols[bdskVertical]

  box.cornerTopLeft.symbol = symbols[bdskTopLeft]
  box.cornerTopRight.symbol = symbols[bdskTopRight]
  box.cornerBottomLeft.symbol = symbols[bdskBottomLeft]
  box.cornerBottomRight.symbol = symbols[bdskBottomRight]


proc updateContent(box: Box) = 
  box.borderTop.updateContent()
  box.borderBottom.updateContent()
  box.borderLeft.updateContent()
  box.borderRight.updateContent()

  box.cornerTopLeft.updateContent()
  box.cornerTopRight.updateContent()
  box.cornerBottomLeft.updateContent()
  box.cornerBottomRight.updateContent()


proc resized(box: Box, rect: Rect): Box = 
  initBox(rect, box.symbols, box.colors, box.styles)


proc buildFrame(box: Box): Frame = 
  result &= box.borderTop.buildFrame()
  result &= box.borderBottom.buildFrame()
  result &= box.borderLeft.buildFrame()
  result &= box.borderRight.buildFrame()

  result &= box.cornerTopLeft.buildFrame()
  result &= box.cornerTopRight.buildFrame()
  result &= box.cornerBottomLeft.buildFrame()
  result &= box.cornerBottomRight.buildFrame()


proc render(box: Box) =
  drawFrame(box.buildFrame())


when isMainModule:
  let
    singleBorderSymbols = [
      "─".toSymbol,
      "│".toSymbol,
      "┌".toSymbol,
      "┐".toSymbol,
      "└".toSymbol,
      "┘".toSymbol
    ]

    doubleBorderSymbols = [
      "═".toSymbol,
      "║".toSymbol,
      "╔".toSymbol,
      "╗".toSymbol,
      "╚".toSymbol,
      "╝".toSymbol
    ]

    roundedBorderSymbols = [
      "─".toSymbol,
      "│".toSymbol,
      "╭".toSymbol,
      "╮".toSymbol,
      "╰".toSymbol,
      "╯".toSymbol
    ]

 
  let
    (maxWidth, maxHeight) = terminalSize()
    minWidth = 3
    minHeight = 3


  var
    isRunning = true
    (width, height) = (maxWidth, maxHeight)

    rect = initRect(0, 0, width, height)
    box = initBox(rect,roundedBorderSymbols)

  proc resizeRedraw(rect: Rect) =
    erasescreen()
    box = box.resized(rect)
    box.updateContent()
    box.render()
    

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
      rect = initRect(rect.x, rect.y, width, height)
      resizeRedraw(rect)
      
    elif key == Key.J:
      width = clamp(width - 1, minWidth, maxWidth)
      height = clamp(height - 1, minHeight, maxHeight)
      rect = initRect(rect.x, rect.y, width, height)
      resizeRedraw(rect)


  proc onResize(ctx: EventContext) =
    if not (ctx of ResizeContext):
      return

    let c = ResizeContext(ctx)
    (width, height) = (c.width, c.height)
    rect = initRect(rect.x, rect.y, width, height)
    resizeRedraw(rect)


  println("Press J and K to change box size; resize terminal to redraw fullscreen box.")
  println("Press Q or Ctrl-C to quit. Press anything to start the demo.")
  discard getch()

  eraseScreen()
  hideCursor()
  box.updateContent()
  box.render()

  let tuiConfig = initTuiConfig()
  runTuiApp(tuiConfig, isRunning, onResize, onKeyPress):
    discard
 
