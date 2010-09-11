
proc initialise {} {
    addAction "Start" start
    addAction "Stop" stop
    stop
}

proc run {} {
    setStatusRight [getBusyString]
    return 100
}

