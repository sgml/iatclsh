namespace import iatclsh::*

proc run {} {
    global count
    set ta [cmd temp a]
    set tb [cmd temp b]
    set v [cmd supv]
    set i [cmd supi]
    set p [format "%.1f" [expr {$v * $i}]]
    setStatusRight "Temps A/B: $ta, $tb"
    setStatusLeft "V: $v, mA: $i\nmW: $p"
    return 1000
}

