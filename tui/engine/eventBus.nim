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
 

# TODO: demo for this module, without involving other modules
