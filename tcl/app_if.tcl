#
# app_if.tcl
#

proc clear {} {
    puts -nonewline "\x11"
}

namespace eval iatclsh {
    variable cmd
    variable ret
    variable err
    variable bgCmd
    while {1} {
        set cmd [gets stdin]
        if {[eof stdin]} {
            exit 0
        }
        set bgCmd 0
        if {[string first "\x02" $cmd] == 0} {
            set cmd [string range $cmd 1 end]
            puts -nonewline "\x02"
            set bgCmd 1
        }
        if {[catch {set ret [namespace eval :: $::iatclsh::cmd]} err]} {
            set ret $err
        } 
        if {$bgCmd} {
            puts -nonewline "$ret\x03" 
        } elseif {$ret != ""} {    
            puts -nonewline "$ret\n\x04" 
        } else {
            puts -nonewline "\x04" 
        }
        flush stdout
    }
}

