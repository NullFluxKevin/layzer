import os
import heapqueue
import times
import tables
import sets


type
  TimerID* = Natural

  Timer* = ref object
    id: TimerID
    isOneShot: bool
    interval: Duration
    due: Time

  TimerHandler* = proc()
  TimerRegistry = Table[TimerID, TimerHandler]

  TimerEventQueue = Channel[TimerID]
  TimerQueue = HeapQueue[Timer]

  TimerLoopCommandKind = enum
    tlckCancel, tlckAddTimer, tlckShutdown

  TimerLoopCommand = object
    case kind: TimerLoopCommandKind
    of tlckCancel:
      id: TimerID
    of tlckAddTimer:
      timer: Timer
    of tlckShutdown:
      discard

  CommandChannel = Channel[TimerLoopCommand]
  Millisecond* = Natural


const
  minIntervalAllowed = initDuration(milliseconds=1)


var
  # Acceptable timer trigger drift due to race conditions or OS scheduling delays.
  # Matching minIntervalAllowed ensures we don't allow more than the shortest valid interval.
  driftTolerance* = initDuration(milliseconds=1)

  timerEventQueue = TimerEventQueue()
  idCounter: Natural = 0
  cmdCh = CommandChannel()
  timerRegistry = TimerRegistry()


proc initModule() = 
  # DO NOT CLOSE THE CHANNELS.
  # RACE CONDITION WILL MOST LIKELY TO CAUSE SENDING TO CLOSED TIMER CHANNEL EVEN WITH FLUSING CHANNELS BEFORE CLOSING AND CHECKING IF THE CHANNEL IS CLOSED AND CHECKING THE SHUTDOWN FLAG BEFORE SENDING.
  timerEventQueue.open
  cmdCh.open

initModule()


# For heapqueue to compare timers
proc `<`(a, b: Timer): bool = a.due < b.due


iterator pollTimerIDs*(): TimerID = 
  while true:
    let recv = timerEventQueue.tryRecv()
    if not recv.dataAvailable:
      break

    yield recv.msg


proc activate*(timerID: TimerID) = 
  doAssert timerID in timerRegistry, "Error: Timer is not registered. Timer ID: " & $timerID
  timerRegistry[timerID]()


proc processActivatedTimers*(): Natural =
  for timerID in pollTimerIDs():
    activate(timerID)
    inc result

  
proc initTimer*(interval: Duration, isOneShot: bool): Timer =
  doAssert idCounter <= high(TimerID), "Fatal: Timer ID exhausted. The system is not designed to be long-running to handle this many timers: " & $idCounter
  let timerID = idCounter
  idCounter += 1
  Timer(id: timerID, isOneShot: isOneShot, interval: interval)


proc initTimer*(interval: Millisecond, isOneShot: bool): Timer =
  initTimer(initDuration(milliseconds= interval), isOneShot)
  

proc every*(interval: Duration, handler: TimerHandler): Timer = 
  result = initTimer(interval, false)
  timerRegistry[result.id] = handler


proc every*(interval: Millisecond, handler: TimerHandler): Timer = 
  every(initDuration(milliseconds=interval), handler)


proc once*(countdown: Duration, handler: TimerHandler): Timer = 
  result = initTimer(countdown, true)
  timerRegistry[result.id] = handler


proc once*(countdown: Millisecond, handler: TimerHandler): Timer = 
  once(initDuration(milliseconds=countdown), handler)


proc cancelTimer*(timer: Timer) = 
  cmdCh.send(TimerLoopCommand(kind: tlckCancel, id: timer.id))


proc addTimer*(timer: Timer) = 
  cmdCh.send(TimerLoopCommand(kind: tlckAddTimer, timer: timer))


proc shutdown*() = 
  #[
    shutdown() gracefully terminates the timer system after the next due timer fires.
    Any commands in the queue (e.g. cancel, add) are still processed.
    No further timer events are scheduled.
    Thread joins are expected to happen after shutdown to ensure full cleanup.
  ]#
  cmdCh.send(TimerLoopCommand(kind: tlckShutdown))


template withTimers*(timers: seq[Timer], body: untyped) =
  var timerThread: Thread[seq[Timer]]
  createThread(timerThread, startTimers, timers)

  body

  shutdown()
  joinThread(timerThread)
  

proc scheduleInternal(timerQueue: var TimerQueue, newTimer: Timer) =
  var timer = newTimer
  doAssert minIntervalAllowed <= timer.interval, "Fatal: Intervals smaller than 1ms are not allowed."
  timer.due = getTime() + timer.interval
  timerQueue.push(timer)


proc startTimers*(timers: seq[Timer]) {.thread.} = 

  var
    timerQueue = initHeapQueue[Timer]()
    pendingCancellations = HashSet[TimerID]()

  for timer in timers:
    timerQueue.scheduleInternal(timer)


  while true:
    let nextTimer = timerQueue.pop()

    if pendingCancellations.contains(nextTimer.id):
      pendingCancellations.excl(nextTimer.id)
      continue

    let timeTilActivation = nextTimer.due - getTime()

    let isDueInThePast = timeTilActivation < DurationZero

    if isDueInThePast:

      doAssert abs(timeTilActivation) <= driftTolerance, "Fatal: Timer due time is in the past. This may indicate host time drift or a bug in timer setup." &
      "\nTimer ID: " & $nextTimer.id & 
      "\nDue: " & $nextTimer.due & 
      "\nNow: " & $getTime() & 
      "\ntimeTilActivation: " & $timeTilActivation & 
      "\nInterval: " & $nextTimer.interval

    else:
      sleep(timeTilActivation.inMilliseconds)

    var shutdown = false
    while true:
      let recv = cmdCh.tryRecv
      if not recv.dataAvailable:
        break

      let cmd = recv.msg
      case cmd.kind:
      of tlckCancel:
        pendingCancellations.incl(cmd.id)
      of tlckAddTimer:
        let newTimer = cmd.timer
        timerQueue.scheduleInternal(newTimer)
      of tlckShutdown:
        shutdown = true
       

    timerEventQueue.send(nextTimer.id)

    if not nextTimer.isOneShot:
      nextTimer.due = getTime() + nextTimer.interval
      timerQueue.push(nextTimer)

    if shutdown:
      break
   

when isMainModule:

  proc tick1Handler() =
    echo "tick 1"

  proc tick2Handler() =
    echo "tick 2"

  proc toBeCancelledTimerHandler() =
    doAssert false, "Fatal: The timer is supposed to be cancelled and never be triggered"

  proc runtimeOneShotHandler() =
    echo "One-shot timer added at runtime triggered"

  proc runtimeHandler() = 
    echo "Recurring timer added at runtime triggered"
  

  var timers = @[
    every(10, tick1Handler),
    every(20, tick2Handler),
  ]

  let toBeCancelledTimer = every(15, toBeCancelledTimerHandler)
  timers.add(toBeCancelledTimer)

  withTimers(timers):

    # The timer thread must be started before sending control commands.
    # Commands (like cancellation) are only processed once the timer loop is running.
    # 
    # IMPORTANT:
    # The effect of sending a cancellation command before the loop starts is *not* guaranteed, unless the target timer's due time is far enough in the future to allow the cancellation to be processed *before* the timer is activated.
    # 
    # This behavior is by design: control commands are part of the running timer system, and cannot take effect before it begins.
    cancelTimer(toBeCancelledTimer)

    let
      runtimeOneShotTimer = once(50, runtimeOneShotHandler)
      runtimeTimer = every(30, runtimeHandler)

    addTimer(runtimeOneShotTimer)
    addTimer(runtimeTimer)


    var timerCounter = 0
    while true:
      let timersProcessed = processActivatedTimers()
      timerCounter += timersProcessed

      # pretend to do useful work
      sleep(5)

      if timerCounter > 20:
        break

