from posix import signal
import terminal
import options

import tui/term/rawTerm
import tui/term/keyInput
import tui/engine/eventBus

export rawTerm, keyInput, eventBus


const
  resizeEvent* = "resizeEvent"
  keyEvent* = "keyEvent"
  SIGWINCH = 28


type
  ResizeContext* = ref object of EventContext
    width*, height*: int

  KeyContext* = ref object of EventContext
    key*: Key


proc handleEvents*() = 
  let eventInfo = tryGetEvent()
  if eventInfo.isSome:
    let ei = eventInfo.get
    let (e, ctx) = (ei.e, ei.ctx)
    e.invoke(ctx)


template println*(content: varargs[untyped, `$`]) =
  stdout.write(content, "\r\n")


template runTuiApp*(isRunning: var bool, onResize: EventHandler, onKeyPress: EventHandler, body: untyped) = 

  onEvent(keyEvent, onKeyPress)

  #[
    "In Nim, the {.volatile.} pragma is used to declare a variable as volatile.
    This means the compiler should not make any assumptions about the value of the variable and should always read its current value from memory, rather than relying on cached or optimized values.
    This is important when dealing with variables that can be modified by external factors, such as hardware or other threads, where the compiler's optimizations might lead to unexpected behavior." -- Internet
  ]#
  var hasResized {.volatile.} = false

  signal(SIGWINCH, proc(sigwinch: cint) {.noconv.} = hasResized = true)
  onEvent(resizeEvent, onResize)

  withRawMode:
    withEventQueue:

      while isRunning:
        block emitResizeEvent:
          if hasResized:
            var
              width = terminalWidth()
              height = terminalHeight()

            emitEvent(resizeEvent, ResizeContext(width: width, height: height))
            hasResized = false

        block emitKeyEvents:
          let keys = getPressedKeys()
          if keys.len > 0:
            for key in keys:
              emitEvent(keyEvent, KeyContext(key: key))

          

        handleEvents()

        body


when isMainModule:

  var isRunning = true

  proc onKeyPress(ctx: EventContext) =
    if not (ctx of KeyContext):
      return

    let c = KeyContext(ctx)
    let key = c.key
    println("Key: ", key)
    
    if key == Key.Q or key == Key.CtrlC:
      println("Exiting...")
      isRunning = false


  proc onResize(ctx: EventContext) =
    if not (ctx of ResizeContext):
      return

    let c = ResizeContext(ctx)
    println("width: ", c.width, "; height: ", c.height)

    
  println("Press keys and resize terminal to test related events.")
  println("Press Q or Ctrl-C to quit.")

  proc main() =
    discard

  runTuiApp(isRunning, onResize, onKeyPress):
    main()
  
