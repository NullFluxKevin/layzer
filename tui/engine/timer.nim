#[
# 
# Timer Module — Usage Guide and Design Notes

## ❯ Usage

- **All timer creation must happen on the _main thread_**, including runtime-created timers.
- **All timer control procs** — `cancelTimer`, `addTimer`, and `shutdown` — must also be called from the _main thread_.
- **Timer callbacks are executed in the main thread**, so they can safely access main-thread data.

- You may define timers up front or dynamically add them during runtime.

- `driftTolerance` defines how much trigger drift (due to race conditions or OS scheduling delays) is acceptable.  
  You may adjust this if your timers frequently fire off-time.

- `idlePollInterval` controls how long the background thread sleeps when **no timers** are pending.  
  Adjust this to tune responsiveness vs. CPU usage.

---

## ❯ Limitations & Assumptions

- This timer system is designed to be driven by a **single-threaded main loop**.  
  **No multithreaded access is supported.**

- Timer IDs are generated via a module-global counter (`idCounter`) with no thread-safety guarantees.  
  This is safe because **all timer creation must happen on the main thread**.

- The **minimum allowed timer interval** is **1 millisecond**.  
  Intervals below that will cause a runtime `doAssert` failure.

- If you are starting and stopping the timer thread manually, the system must be **explicitly shut down** by calling `shutdown()` once you're done:
  - This ensures the background thread exits cleanly.
  - All pending control commands (`add`, `cancel`, etc.) are processed before shutdown completes.
  - After shutdown, **no new timers will be scheduled**.
  - You must `joinThread` after shutdown to ensure full cleanup.

---

## ❯ Control Command Timing Rules

- The **timer loop must be running before you send any control commands**.
- Commands sent *before* the loop starts are **not guaranteed to work**:
  - Especially cancellation — if the timer fires before the cancel command is processed, it will still trigger.
  - If you need guaranteed cancellation, ensure the timer’s `due` time is far enough in the future.

- This behavior is **intentional**:  
  control commands are part of the live timer system, and are not processed before it begins.

]#


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
  idlePollInterval*: Millisecond = 50

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

  
proc newTimer*(interval: Duration, isOneShot: bool): Timer =
  doAssert idCounter <= high(TimerID), "Fatal: Timer ID exhausted. The system is not designed to be long-running to handle this many timers: " & $idCounter
  let timerID = idCounter
  idCounter += 1
  Timer(id: timerID, isOneShot: isOneShot, interval: interval)


proc newTimer*(interval: Millisecond, isOneShot: bool): Timer =
  newTimer(initDuration(milliseconds= interval), isOneShot)
  

proc every*(interval: Duration, handler: TimerHandler): Timer = 
  result = newTimer(interval, false)
  timerRegistry[result.id] = handler


proc every*(interval: Millisecond, handler: TimerHandler): Timer = 
  every(initDuration(milliseconds=interval), handler)


proc once*(countdown: Duration, handler: TimerHandler): Timer = 
  result = newTimer(countdown, true)
  timerRegistry[result.id] = handler


proc once*(countdown: Millisecond, handler: TimerHandler): Timer = 
  once(initDuration(milliseconds=countdown), handler)


proc cancelTimer*(timer: Timer) = 
  cmdCh.send(TimerLoopCommand(kind: tlckCancel, id: timer.id))


proc addTimer*(timer: Timer) = 
  cmdCh.send(TimerLoopCommand(kind: tlckAddTimer, timer: timer))


proc shutdown*() = 
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
    var nextTimer: Timer = nil
    if timerQueue.len == 0:
      doAssert idlePollInterval >= 1, "Error: Poll interval must be at least 1ms"
      sleep(idlePollInterval)
    else:

      nextTimer = timerQueue.pop()

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
       

    if not nextTimer.isNil:
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

