set testVar 1

proc initialise {} {
    addAction "Set" {setLevel 1}
    addAction "Clear" {setLevel 0}
    addCBAction "Toggle" testVar 
}

proc setLevel {level} {
    global testVar
    set testVar $level
}

proc run {} {
    global testVar
    setStatusRight "$testVar [getBusyString]"
    return 100
}

