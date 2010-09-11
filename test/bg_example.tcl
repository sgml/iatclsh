set viewPwr 1
set t 250

proc initialise {} {
    addAction "Stop" stop
    addAction "Start" start
    addSeparator
    addCBAction "View Power" viewPwr 
    addSeparator
    addRBAction {250 500 1000 2500} t -submenu "Update Rate (ms)" 
}

proc run {} {
    global t viewPwr 
    set ta [cmd temp a]
    set tb [cmd temp b]
    set v [cmd supv]
    set i [cmd supi]
    setStatusRight "Temps A/B: $ta, $tb\n[getBusyString 100]"
    if {$viewPwr && $v !="" && $i != ""} {
        set p [format "%.1f" [expr {$v * $i}]]
        setStatusLeft "V: $v, mA: $i\nmW: $p"
    } else {
        setStatusLeft "V: $v, mA: $i"
    }
    return $t
}

