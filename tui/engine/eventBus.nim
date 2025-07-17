import terminal
import posix
import tables
import options

import tui/term/keyInput
import tui/term/rawTerm


type
  EventContext* = ref object of RootObj

  EventHandler* = proc(ctx: EventContext)
  Event* = ref object
    name*: string
    handlers*: seq[EventHandler]
 
  EventBus = Table[string, Event]
  EventInfo* = tuple[e: Event, ctx: EventContext]
  EventQueue = Channel[EventInfo]
 

var
  eventBus = EventBus()
  eventQueue = EventQueue()


template withEventQueue*(body: untyped) = 
  try:
    eventQueue.open
    body
  finally:
    eventQueue.close

proc tryGetEvent*(): Option[EventInfo] =
  let recv = eventQueue.tryRecv()
  if recv.dataAvailable:
    result = some((recv.msg.e, recv.msg.ctx))
  else:
    result = none(EventInfo)
    

proc invoke*(e: Event, ctx: EventContext) =
  for handler in e.handlers:
    handler(ctx)


proc onEvent*(event: string, handler: EventHandler) = 
  # Table value gotcha:
  # if your value is of value type, then modification after assignment such as
  # ```nim
  # eventBus[event] = e
  # e.handlers.add(handler)  # handler not registered to eventBus[event]!
  # ```
  # will not affect it. Even mgetOrPut wouldn't work.
  # So Event has to be ref object
  var e = eventBus.mgetOrPut(event, Event(name: event))
  e.handlers.add(handler)


proc emitEvent*(event: string, ctx: EventContext) = 
  doAssert event in eventBus, "No such event registered: " & event

  let toBeEmitted = eventBus[event]
  eventQueue.send((toBeEmitted, ctx))
  

when isMainModule:
  # works fine. commented out for testing resizeEvent for now
  # 
  # block test_keyEvent:
  #   type KeyContext = ref object of EventContext
  #     key: Key

  #   const keyEvent = "keyEvent"

  #   proc run(intervalMS: Positive = 100) =
  #     while true:
  #       let recv = eventQueue.tryRecv()
  #       if recv.dataAvailable:
  #         let (e, ctx) = (recv.msg.e, recv.msg.ctx)
  #         e.invoke(ctx)

  #         let keyCtx = KeyContext(ctx)
  #         if keyCtx.key == Key.Q or keyCtx.key == Key.CtrlC:
  #           stdout.write("Exiting...", "\r\n")
  #           break

  #       let keys = getPressedKeys()
  #       if keys.len > 0:
  #         for key in keys:
  #           emitEvent(keyEvent, KeyContext(key: key))



  #   onEvent(keyEvent, proc(ctx: EventContext) =
  #     let c = KeyContext(ctx)
  #     stdout.write("Key pressed: ", c.key, "\r\n")
  #   )

  #   onEvent(keyEvent, proc(ctx: EventContext) =
  #     let c = KeyContext(ctx)
  #     stdout.write("Key code: ", ord(c.key), "\r\n")
  #   )

  #   echo "Key press event Demo. Press q or ctrl-c to quit"
  #   withEventQueue:
  #     withRawMode:
  #       run()


  
  # TODO: resize event should be core api
  # TODO: move event polling logic from userland to framework
  block test_resizeEvent:

    const
      SIGWINCH = 28
      resizeEvent = "resizeEvent"

    type
      ResizeContext = ref object of EventContext
        width, height: int

    proc onResize(ctx: EventContext) = 
      let c = ResizeContext(ctx)
      echo "New terminal window size: ", c.width, ", ", c.height


    onEvent(resizeEvent, onResize)

    echo "You have to change the size of the ternimal for testing"
    echo "Stop manually with ctrl-c when you are done testing"

    var hasResized = false
    signal(SIGWINCH, proc(sigwinch: cint) {.noconv.} = hasResized = true)

    withEventQueue:
      while true:
        if hasResized:
          var
            width = terminalWidth()
            height = terminalHeight()

          emitEvent(resizeEvent, ResizeContext(width: width, height: height))
          hasResized = false

        let recv = eventQueue.tryRecv()
        if recv.dataAvailable:
          let
            event = recv.msg.e
            ctx = recv.msg.ctx

          event.invoke(ctx)
