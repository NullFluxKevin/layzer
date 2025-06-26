import strutils
import terminal

import layoutEngine

type
  Box = object
    topLeft, top, topRight: Rect
    midLeft, canvas, midRight: Rect
    bottomLeft, bottom, bottomRight: Rect

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

  (result.topLeft, result.top, result.topRight) = (topRowCols[0], topRowCols[1], topRowCols[2])
  (result.midLeft, result.canvas, result.midRight) = (midRowCols[0], midRowCols[1], midRowCols[2])
  (result.bottomLeft, result.bottom, result.bottomRight) = (bottomRowCols[0], bottomRowCols[1], bottomRowCols[2])


proc drawBox(box: Box) = 
  let
    corner = "+"
    horizontal = "-"
    vertical = "|"

  setCursorPos(box.topLeft.x, box.topLeft.y)
  stdout.styledWrite(fgGreen, corner)
  setCursorPos(box.topRight.x, box.topRight.y)
  stdout.styledWrite(fgGreen, corner)
  setCursorPos(box.bottomLeft.x, box.bottomLeft.y)
  stdout.styledWrite(fgGreen, corner)
  setCursorPos(box.bottomRight.x, box.bottomRight.y)
  stdout.styledWrite(fgGreen, corner)


  let horizontalBorder = horizontal.repeat(box.top.width).join

  setCursorPos(box.top.x, box.top.y)
  stdout.styledWrite(fgWhite, horizontalBorder)
  
  setCursorPos(box.bottom.x, box.bottom.y)
  stdout.styledWrite(fgWhite, horizontalBorder)

  for i in 0 ..< box.midLeft.height:
    setCursorPos(box.midLeft.x, box.midLeft.y + i)
    stdout.styledWrite(fgWhite, vertical)
    setCursorPos(box.midRight.x, box.midRight.y + i)
    stdout.styledWrite(fgWhite, vertical)
    
    
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

