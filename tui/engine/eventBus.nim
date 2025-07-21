import tables
import options


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

eventQueue.open
# not closed ever, let OS clean up after the process exits
  

proc closeEventQueue*() = 
  # May not be necessary, but you can do it before quitting the app
  eventQueue.close


proc tryGetEvent*(): Option[EventInfo] =
  let recv = eventQueue.tryRecv()
  if recv.dataAvailable:
    result = some((recv.msg.e, recv.msg.ctx))
  else:
    result = none(EventInfo)
    

iterator pollEvents*(): EventInfo = 
  while true:
    let eventInfo = tryGetEvent()
    if eventInfo.isNone:
      break

    yield eventInfo.get
      

proc invoke*(e: Event, ctx: EventContext) =
  for handler in e.handlers:
    handler(ctx)


proc invoke*(eventInfo: EventInfo) =
  let
    event = eventInfo.e
    context = eventInfo.ctx

  for handler in event.handlers:
    handler(context)


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

  # To define and register a custom event, you will need:
  # 1. A unique event name
  # 2. A custom event context sub-type for passing values to event handler(s)
  # 3. To define event handler(s) for the event
  # 4. To register the event on the event bus with onEvent()
   
  const customEvent = "customEvent"

  type CustomEventContext = ref object of EventContext
    msg: string

  proc customHandler(ctx: EventContext) =
    # Every handler must test and down cast ctx to the correct context type
    if not (ctx of CustomEventContext):
      return
    let customCtx = CustomEventContext(ctx)


    echo("Custom event message: ", customCtx.msg)


  # Every event MUST be registered before it could be used
  onEvent(customEvent, customHandler)


  # To emit an event, simply call emitEvent().
  # Events to be emitted MUST already be registered to the event bus.
  for i in 1..10:
    emitEvent(customEvent, CustomEventContext(msg: "Hello " & $i))


  # To handle events, you need to get them out from the event queue first.
  for eventInfo in pollEvents():
    let
      event = eventInfo.e
      context = eventInfo.ctx

    event.invoke(context)
