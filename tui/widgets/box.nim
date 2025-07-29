import os

import tui/render/doubleBuffer
import layoutEngine
import unicode


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
    colors: SpanColors
    styles: set[Style]
  

proc toSymbol(s: string): Symbol = 
  doAssert s.runeLen == 1, "Error: Symbol must be a single character"
  s.runeAt(0)
  

proc initLineHorizontal(rect: Rect, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): LineHorizontal =
  doAssert rect.height == 1, "Error: Horizontal line must have height of 1"
  let buffer = newBuffer(rect)
  LineHorizontal(buffer: buffer, symbol: symbol, colors: colors, styles: styles)


proc buildFrame(line: LineHorizontal): Frame = 
  line.buffer.writeToLine(0, repeat(line.symbol, line.buffer.width), line.colors, line.styles)
  line.buffer.buildFrame()


proc render(line: LineHorizontal) =
  drawFrame(line.buildFrame())


proc initCell(rect: Rect, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): Cell = 
  doAssert rect.width == 1 and rect.height == 1, "Error: Cell must be a 1x1 rect"
  let buffer = newBuffer(rect)
  Cell(buffer: buffer, symbol: symbol, colors: colors, styles: styles)


proc buildFrame(cell: Cell): Frame =
  cell.buffer.writeToLine(0, $cell.symbol)
  cell.buffer.buildFrame()


proc render(cell: Cell) = 
  drawFrame(cell.buildFrame())


proc initLineVertical(rect: Rect, symbol: Symbol, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): LineVertical =
  doAssert rect.width == 1, "Error: Vertical line must have width of 1"
  let buffer = newBuffer(rect)
  LineVertical(buffer: buffer, symbol: symbol, colors: colors, styles: styles)


proc buildFrame(line: LineVertical): Frame = 
  for i in 0 ..< line.buffer.height:
    line.buffer.writeToLine(i, $line.symbol, line.colors, line.styles)

  line.buffer.buildFrame()


proc render(line: LineVertical) =
  drawFrame(line.buildFrame())


proc newBuffer(rect: Rect, symbols: BoxDrawingSymbols, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}): Box = 
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

    (cornerTopLeft, borderTop, cornerTopRight) = (topRowCols[0], topRowCols[1], topRowCols[2])
    (borderLeft, canvas, borderRight) = (midRowCols[0], midRowCols[1], midRowCols[2])
    (cornerBottomLeft, borderBottom, cornerBottomRight) = (bottomRowCols[0], bottomRowCols[1], bottomRowCols[2])


  result.borderTop = initLineHorizontal(borderTop, symbols[bdskHorizontal], colors, styles)
  result.borderBottom = initLineHorizontal(borderBottom, symbols[bdskHorizontal], colors, styles)
  result.borderLeft = initLineVertical(borderLeft, symbols[bdskVertical], colors, styles)
  result.borderRight = initLineVertical(borderRight, symbols[bdskVertical], colors, styles)

  result.cornerTopLeft = initCell(cornerTopLeft, symbols[bdskTopLeft], colors, styles)
  result.cornerTopRight = initCell(cornerTopRight, symbols[bdskTopRight], colors, styles)
  result.cornerBottomLeft = initCell(cornerBottomLeft, symbols[bdskBottomLeft], colors, styles)
  result.cornerBottomRight = initCell(cornerBottomRight, symbols[bdskBottomRight], colors, styles)

  result.canvas = canvas


proc setSymbols(box: var Box, symbols: BoxDrawingSymbols) =
  box.borderTop.symbol = symbols[bdskHorizontal]
  box.borderBottom.symbol = symbols[bdskHorizontal]
  box.borderLeft.symbol = symbols[bdskVertical]
  box.borderRight.symbol = symbols[bdskVertical]

  box.cornerTopLeft.symbol = symbols[bdskTopLeft]
  box.cornerTopRight.symbol = symbols[bdskTopRight]
  box.cornerBottomLeft.symbol = symbols[bdskBottomLeft]
  box.cornerBottomRight.symbol = symbols[bdskBottomRight]


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
    rect = initRect(10, 10, 10, 10)

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


  var box = newBuffer(rect, singleBorderSymbols)


  for i in 0 ..< 100:

    if i mod 2 == 0:
      box.setSymbols(singleBorderSymbols)
    else:
      box.setSymbols(doubleBorderSymbols)

    box.render()
    sleep(10)

