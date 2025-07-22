import os
import heapqueue
import times
import tables
import sets


type
  TimerID = Natural

  Timer = ref object
    id: TimerID
    isOneShot: bool
    interval: Duration
    due: Time


  TimerRegistry = Table[TimerID, proc()]
  TimerEventQueue = Channel[TimerID]
  TimerHandler = proc()

  TimerLoopCommandKind = enum
    tlckCancel

  TimerLoopCommand = object
    case kind: TimerLoopCommandKind
    of tlckCancel:
      id: TimerID

  CommandChannel = Channel[TimerLoopCommand]


var
  timerEventQueue = TimerEventQueue()
  idCounter = 0
  cmdCh = CommandChannel()

timerEventQueue.open
cmdCh.open

const
  minIntervalAllowed = initDuration(milliseconds=1)


proc `<`(a, b: Timer): bool = a.due < b.due


iterator pollTimerID(): TimerID = 
  while true:
    let recv = timerEventQueue.tryRecv()
    if not recv.dataAvailable:
      break

    yield recv.msg


proc initTimer(interval: Duration, isOneShot: bool): Timer =
  let timerID = idCounter
  idCounter += 1
  Timer(id: timerID, isOneShot: isOneShot, interval: interval)


proc registerTimer(registry: var TimerRegistry, timerID: TimerID, handler: TimerHandler) =
  registry[timerID] = handler
  
proc cancelTimer(id: TimerID) = 
  cmdCh.send(TimerLoopCommand(kind: tlckCancel, id: id))


proc startTimers(timers: seq[Timer]) {.thread.} = 

  var
    timerQueue = initHeapQueue[Timer]()
    pendingCancellations = HashSet[TimerID]()

  for timer in timers:
    doAssert minIntervalAllowed <= timer.interval, "Fatal: Intervals smaller than 1ms are not allowed."
    timer.due = getTime() + timer.interval
    timerQueue.push(timer)


  while true:
    let nextTimer = timerQueue.pop()

    if pendingCancellations.contains(nextTimer.id):
      pendingCancellations.excl(nextTimer.id)
      continue

    let timeTilActivation = nextTimer.due - getTime()
  
    doAssert DurationZero < timeTilActivation, "Fatal: Timer due time is in the past. This may indicate host time drift or a bug in timer setup." &
    "\nTimer ID: " & $nextTimer.id & 
    "\nDue: " & $nextTimer.due & 
    "\nNow: " & $getTime() & 
    "\nInterval: " & $nextTimer.interval

      
    let milsecs = timeTilActivation.inMilliseconds
    sleep(milsecs)

    # Has to be checked AFTER the thread wakes up to prevent from sending to closed channel by race condition
    let isTimerEventQueueClosed = timerEventQueue.peek == -1
    if isTimerEventQueueClosed:
      return

    while true:
      let recv = cmdCh.tryRecv
      if not recv.dataAvailable:
        break

      let cmd = recv.msg
      case cmd.kind:
      of tlckCancel:
        pendingCancellations.incl(cmd.id)

    timerEventQueue.send(nextTimer.id)

    if not nextTimer.isOneShot:
      nextTimer.due = getTime() + nextTimer.interval
      timerQueue.push(nextTimer)

   

when isMainModule:

  proc tick1SecHandler() =
    echo "tick every 1 sec"

  proc tick2SecsHandler() =
    echo "tick every 2 secs"

  proc toBeCancelledTimerHandler() =
    doAssert false, "Fatal: The timer is supposed to be cancelled and never be triggered"
  
  var timerRegistry = TimerRegistry()

  let tick1sec = initTimer(initDuration(seconds=1), false)
  let tick2secs = initTimer(initDuration(seconds=2), false)
  let toBeCancelledTimer = initTimer(initDuration(seconds=1, milliseconds=500), false)

  timerRegistry.registerTimer(tick1sec.id, tick1SecHandler)
  timerRegistry.registerTimer(tick2secs.id, tick2SecsHandler)
  timerRegistry.registerTimer(toBeCancelledTimer.id, toBeCancelledTimerHandler)
  var timers: seq[Timer] = @[tick1sec, tick2Secs, toBeCancelledTimer]

  var timerThread: Thread[seq[Timer]]
  createThread(timerThread, startTimers, timers)

  # The timer thread must be started before sending control commands.
  # Commands (like cancellation) are only processed once the timer loop is running.
  # 
  # IMPORTANT:
  # The effect of sending a cancellation command before the loop starts is *not* guaranteed, unless the target timer's due time is far enough in the future to allow the cancellation to be processed *before* the timer is activated.
  # 
  # This behavior is by design: control commands are part of the running timer system, and cannot take effect before it begins.
  cancelTimer(toBeCancelledTimer.id)

  var timerCounter = 0
  while true:
    for timerID in pollTimerID():
      timerRegistry[timerID]()
      inc timerCounter

    # pretend to do useful work
    sleep(500)

    if timerCounter > 10:
      break

  # This is how we signal the timer thread to stop the loop
  timerEventQueue.close

  cmdCh.close

  joinThread(timerThread)

