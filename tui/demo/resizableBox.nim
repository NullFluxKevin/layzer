import terminal

import tui/core
import tui/box


when isMainModule:

  let
    (maxWidth, maxHeight) = terminalSize()
    minWidth = 3
    minHeight = 3


  var
    isRunning = true
    (width, height) = (maxWidth, maxHeight)


  proc drawBox() =
    eraseScreen()
    setCursorPos(0, 0)
    let 
      rect = initRect(0, 0, width, height)
      box = initBox(rect)
      title = "Size: " & $width & " x " & $height

    box.drawTopTitleBox(title, taCenter)
    # flush or the last thing you write will be in buffer and not displayed
    stdout.flushFile()
    

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
      drawBox()
      
    elif key == Key.J:
      width = clamp(width - 1, minWidth, maxWidth)
      height = clamp(height - 1, minHeight, maxHeight)
      drawBox()


  proc onResize(ctx: EventContext) =
    if not (ctx of ResizeContext):
      return

    let c = ResizeContext(ctx)
    (width, height) = (c.width, c.height)
    drawBox()


  println("Press J and K to change box size; resize terminal to redraw fullscreen box.")
  println("Press Q or Ctrl-C to quit. Press anything to start the demo.")
  discard getch()

  hideCursor()
  drawBox()

  let tuiConfig = initTuiConfig()
  runTuiApp(tuiConfig, isRunning, onResize, onKeyPress):
    discard
    
