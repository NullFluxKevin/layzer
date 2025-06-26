import unicode
import strutils
import terminal

import layoutEngine

type
  Box = object
    cornerTopLeft, borderTop, cornerTopRight: Rect
    borderLeft, canvas, borderRight: Rect
    cornerBottomLeft, borderBottom, cornerBottomRight: Rect

  BoxSymbols = object
    horizontal, vertical, cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: string

proc initBox(rect: Rect): Box = 
  doAssert rect.width >= 3
  doAssert rect.height >= 3
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


proc initBoxSymbols(horizontal, vertical, cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: string): BoxSymbols = 
  doAssert horizontal.runeLen == 1
  doAssert vertical.runeLen == 1
  doAssert cornerTopLeft.runeLen == 1
  doAssert cornerTopRight.runeLen == 1
  doAssert cornerBottomLeft.runeLen == 1
  doAssert cornerBottomRight.runeLen == 1

  BoxSymbols(
    horizontal: horizontal,
    vertical: vertical,
    cornerTopLeft: cornerTopLeft,
    cornerTopRight: cornerTopRight,
    cornerBottomLeft: cornerBottomLeft,
    cornerBottomRight: cornerBottomRight,
  )

const singleBoxSymbols = initBoxSymbols("─", "│", "┌", "┐", "└", "┘")
const doubleBoxSymbols = initBoxSymbols("═", "║", "╔", "╗", "╚", "╝")
const roundedBoxSymbols = initBoxSymbols("─", "│", "╭", "╮", "╰", "╯")
 
proc drawBox(box: Box, symbols: BoxSymbols = roundedBoxSymbols) = 
  setCursorPos(box.cornerTopLeft.x, box.cornerTopLeft.y)
  stdout.write(symbols.cornerTopLeft)
  setCursorPos(box.cornerTopRight.x, box.cornerTopRight.y)
  stdout.write(symbols.cornerTopRight)
  setCursorPos(box.cornerBottomLeft.x, box.cornerBottomLeft.y)
  stdout.write(symbols.cornerBottomLeft)
  setCursorPos(box.cornerBottomRight.x, box.cornerBottomRight.y)
  stdout.write(symbols.cornerBottomRight)


  let horizontalBorder = symbols.horizontal.repeat(box.borderTop.width).join

  setCursorPos(box.borderTop.x, box.borderTop.y)
  stdout.write(horizontalBorder)
  
  setCursorPos(box.borderBottom.x, box.borderBottom.y)
  stdout.write(horizontalBorder)

  for i in 0 ..< box.borderLeft.height:
    setCursorPos(box.borderLeft.x, box.borderLeft.y + i)
    stdout.write(symbols.vertical)
    setCursorPos(box.borderRight.x, box.borderRight.y + i)
    stdout.write(symbols.vertical)
    
    
when isMainModule:
  try:
    hideCursor()
    eraseScreen()
    setCursorPos(0, 0)
    let
      x = 3
      y = 1
      width = terminalWidth() - 2 * x
      height = terminalHeight() - 2 * y
      rect = initRect(x, y, width, height)

      outerBox = initBox(rect)

      colsConstraints = @[
        Constraint(kind: ckPercent, percent: 20),
        Constraint(kind: ckPercent, percent: 80),
      ]

      rowsConstraints = @[
        Constraint(kind: ckMinLength, minLength: 5),
        Constraint(kind: ckLength, length: 5),
        Constraint(kind: ckPercent, percent: 40),
        Constraint(kind: ckPercent, percent: 60),
      ]


      cols = layout(ldHorizontal, outerBox.canvas, colsConstraints)
      sidebar = cols[0]
      main = cols[1]
      # mainBox = initBox(main)
      rows = layout(ldVertical, main, rowsConstraints)

    # echo "Outer Box: ", rect
    drawBox(outerBox)
    for row in rows:
      drawBox(initBox(row))

    drawBox(initBox(sidebar))
 

    discard getch()

    eraseScreen()
    setCursorPos(0, 0)
  finally:
    showCursor()

