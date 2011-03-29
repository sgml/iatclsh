#
# simulates simple hardware device, which can be enabled/disabled, and has 
# monitors for voltage, current, and temperature
#

set hwEnable off

proc help {} {
    puts "en        Get/set power enable (\[on/off\])"
    puts "supv      Get supply voltage"
    puts "supi      Get supply current"
    puts "temp      Get temperature from sensor (a/b)"
    puts "test      Test routine"
}

proc test {} {
    puts "Test proc"
    after 20000
    puts "Test done"
}

proc en {{en ""}} {
    global hwEnable
    switch $en {
        "" {puts "enable: $hwEnable"}
        on -
        off {set hwEnable $en; en}
        default {puts "error, enable must be on or off"}
    }
}

proc supv {} {
    puts [format "%.2f" [expr {11.95 + rand() * 0.1}]]    
}

proc supi {} {
    puts [format "%.1f" [expr {53.5 + rand() * 3.0}]]    
}

proc temp {sensor} {
    switch $sensor {
        a {set base 25.5}
        b {set base 32.3}
        default {puts "error, sensor must be a or b"; return}
    }
    puts [format "%.1f" [expr {$base + rand() * 0.1}]]
}

proc getAString {} {
    return "a \nstring"
}

proc getBString {} {
    return "b \nstring\n"
}

help
foreach i {1 2 3 4 5} {
    puts -nonewline "$i "; flush stdout
    after 1000
}

