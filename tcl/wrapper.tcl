#
# wrapper.tcl
#
# Used to wrap scripts so that they are compatible for use with tclkit 
#
if {$argv == "-app_if"} {
    source [file dirname [info script]]/app_if.tcl
} else {
    set runningWithTclkit 1
    source [file dirname [info script]]/iatclsh.tcl
}

