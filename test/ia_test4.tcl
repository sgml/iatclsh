# use with ia_test1.tcl as a user script

proc run {} {
    set i [cmd getAString]
    set j [cmd getBString]
    setStatusLeft $i
    setStatusRight $j
    return 
}

