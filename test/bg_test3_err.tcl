
proc initialise {} {
    addAction "Start" start
    addAction "Stop" stop
    puts "An" "Error"
}

proc run {} {
    setStatusRight [getBusyString]
    return 100
}

