#
# app_if.tcl
#

proc clear {} {
    puts -nonewline "\x11"
}

namespace eval iatclsh {
    proc readStdin {} {
        set cmd [gets stdin]
        if {[eof stdin]} {
            exit 0
        }
        if {[fblocked stdin]} {
            return
        }
        set bgCmd 0
        if {[string first "\x02" $cmd] == 0} {
            set cmd [string range $cmd 1 end]
            puts -nonewline "\x02"
            set bgCmd 1
        }
        if {[catch {set ret [namespace eval :: $cmd]} err]} {
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

    fconfigure stdin -blocking 0
    fileevent stdin readable ::iatclsh::readStdin
    vwait forever
}

