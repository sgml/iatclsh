#
# app_if.tcl
#

proc clear {} {
    return "\x11"    
}
     
namespace eval iatclsh {
    variable cmd
    variable ret
    variable err
    while {1} {
        set cmd [gets stdin]
        if {[eof stdin]} {
            exit 0
        }
        if {$cmd == "\x03"} {
            puts "\x03"; flush stdout
        } else {
            if {[catch {set ret [namespace eval :: $::iatclsh::cmd]} err]} {
                puts $err; flush stdout
            } elseif {$ret != ""} {    
                puts $ret; flush stdout
            }
        }
    }
}

