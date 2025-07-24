from posix import signal
import terminal
import options

import tui/term/rawTerm
import tui/term/keyInput
import tui/engine/eventBus
import tui/engine/timer

export rawTerm, keyInput, eventBus, timer


const
  resizeEvent* = "resizeEvent"
  keyEvent* = "keyEvent"
  SIGWINCH = 28


type
  ResizeContext* = ref object of EventContext
    width*, height*: int

  KeyContext* = ref object of EventContext
    key*: Key

  TuiConfig* = object
    timeout*: Milliseconds
    escSeqTimeout*: Milliseconds
    keyEscSeqTable*: KeyEscapeSequenceTable
    unknownKeyCodeHandler*: UnknownKeyCodeHandler
    unknownEscSeqHandler*: UnknownEscSeqHandler
    

proc initTuiConfig*(
  timeout: Milliseconds = 100,
  escSeqTimeout: Milliseconds = 10,
  keyEscSeqTable: KeyEscapeSequenceTable = defaultKeyEscSeqTable,
  unknownKeyCodeHandler: UnknownKeyCodeHandler = nil,
  unknownEscSeqHandler: UnknownEscSeqHandler = nil
): TuiConfig =

  TuiConfig(
    timeout: timeout,
    escSeqTimeout: escSeqTimeout,
    keyEscSeqTable: keyEscSeqTable,
    unknownKeyCodeHandler: unknownKeyCodeHandler,
    unknownEscSeqHandler: unknownEscSeqHandler
  )


proc handleEvents*() = 
  for eventInfo in pollEvents():
    let (e, ctx) = (eventInfo.e, eventInfo.ctx)
    e.invoke(ctx)


template println*(content: varargs[untyped, `$`]) =
  stdout.write(content, "\r\n")


template println*() =
  stdout.write("\r\n")


template runTuiApp*(tuiConfig: TuiConfig, isRunning: var bool, onResize: EventHandler, onKeyPress: EventHandler, body: untyped) = 

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

    while isRunning:
      block emitResizeEvent:
        if hasResized:
          var
            width = terminalWidth()
            height = terminalHeight()

          emitEvent(resizeEvent, ResizeContext(width: width, height: height))
          hasResized = false

      block emitKeyEvent:
        let ret = tryGetKey(
          tuiConfig.timeout,        
          tuiConfig.escSeqTimeout,        
          tuiConfig.keyEscSeqTable,        
          tuiConfig.unknownKeyCodeHandler,        
          tuiConfig.unknownEscSeqHandler,        
        )

        if ret.isSome:
          let key = ret.get
          emitEvent(keyEvent, KeyContext(key: key))
          

      handleEvents()

      body


when isMainModule:

  var
    isRunning = true
    keyPressCount = 0

  proc onKeyPress(ctx: EventContext) =
    if not (ctx of KeyContext):
      return

    let c = KeyContext(ctx)
    let key = c.key
    println("Key: ", key)
    
    inc keyPressCount

    if key == Key.Q or key == Key.CtrlC:
      println("Exiting...")
      isRunning = false


  proc onResize(ctx: EventContext) =
    if not (ctx of ResizeContext):
      return

    let c = ResizeContext(ctx)
    println("width: ", c.width, "; height: ", c.height)


  proc reportKeyPerSec() = 
    println("Key pressed in the last second: ", keyPressCount)
    keyPressCount = 0

    
  println("Press keys and resize terminal to test related events.")
  println("Press Q or Ctrl-C to quit.")

  let timers = @[
    every(1000, reportKeyPerSec)
  ]

  let tuiConfig = initTuiConfig()
  withTimers(timers):
    runTuiApp(tuiConfig, isRunning, onResize, onKeyPress):
      discard processActivatedTimers()
      # do other work
  
