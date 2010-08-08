#
# iatclsh.tcl
#

namespace eval iatclsh {    
    namespace export \
            pending post cmd getLine getAll stop resume \
            isStatusBarHidden showStatusBar hideStatusBar \
            setStatusLeft setStatusRight \
            addAction addCBAction addRBAction addSeparator 
       
    variable configFile ""
    variable sourceFiles [list]
    variable showScrollBar 0
    variable HISTORY_MAX_CMDS 100
    variable LOG_MAX_LINES 10000
    variable cmdHistory [list]                       
    variable historyIndex 0
    variable currentEditCmd ""
    variable bgndRxBuf ""    
    variable cmdLine ""
    variable lastCmdAuto 0
    variable interactiveCmd ""
    variable autoCmd ""
    variable autoCmdComplete 0
    variable busy 0
    variable statusHidden 1
    variable runStopped 0
    variable pause
    variable fd
    
    # parse command line arguments. Returns 1 if command line parsed 
    # successfully, otherwise 0
    proc parseCmdLineArgs {} {
        global argc argv 
        variable configFile
        variable sourceFiles
        variable showScrollBar
        set i 0
        while {$i < $argc} {
            set t [lindex $argv $i]
            if {[regexp {^-} $t]} {
                if {$t == "-sc"} {
                    set showScrollBar 1
                    incr i
                } elseif {$t == "-config"} {
                    incr i
                    if {$i >= $argc} {
                        return 0
                    }
                    set configFile [lindex $argv $i]
                    incr i
                } else {
                    return 0
                }
            } else {
                lappend sourceFiles $t
                incr i
            }
        }
        return 1
    }
    
    # open pipe to app interface and source any supplied files. Returns a 
    # string message in m, and 1 for success, 0 for fail
    proc startUp {m} {
        variable sourceFiles
        variable fd 
        global tcl_platform
        upvar $m msg
        switch $tcl_platform(platform) {
            "unix" {set prog "app_if.sh"}
            "windows" {set prog "app_if.bat"}
            "default" {set msg "platform?"; return 0}
        }
        if {[catch {set fd [open "|$prog" r+]} err]} {
            set msg $err; 
            return 0
        }
        set msg ""
        foreach f $sourceFiles {
            puts $fd "source $f"
            puts $fd "\x03"; flush $fd
            while {1} {
                set l [gets $fd]
                if {$l == "\x03"} {
                    break
                }
                set msg "$msg$l\n"
            }
        }
        chan event $fd readable ::iatclsh::readPipe
        chan configure $fd -blocking 0
        return 1
    }
    
    # event handler for reading pipe
    proc readPipe {} {
        variable fd
        set r [read $fd]
        if {[eof $fd]} {
            closeApp
        }
        if {[regexp {^(.*)\x03\n$} $r match response]} {
            if {$response != ""} {
                processRxMsg $response
            }
            completedCmd
        } else {
            if {$r != ""} {
                processRxMsg $r
            }
        }
    }
    
    # process received messages
    proc processRxMsg {s} {
        variable lastCmdAuto 
        variable bgndRxBuf
        if {!$lastCmdAuto} {
            if {$s == "\x11\n"} {
                clearLog
            } else {
                appendLog "$s" response
            }
            update idletasks
        } else {
            set bgndRxBuf $bgndRxBuf$s
        }
    }
    
    # command completed
    proc completedCmd {} {
        variable cmdLine 
        variable interactiveCmd
        variable autoCmd
        variable lastCmdAuto
        variable busy
        variable autoCmdComplete
        set busy 0
        if {$lastCmdAuto} {
            set autoCmd ""
            set autoCmdComplete 1
            if {$interactiveCmd != ""} {
                sendACmd   
            }
        } else {
            set cmdLine ""
            set interactiveCmd ""
            .cmd config -state normal
            if {$autoCmd != ""} {
                sendACmd   
            }
        }
    }
    
    # append string str to text widget log, with supplied tag 
    proc appendLog {str tag} {
        .log configure -state normal
        .log insert end $str $tag
        trimLog
        .log configure -state disabled
        .log see end
    }
    
    # trim log to a maximum of LOG_MAX_LINES
    proc trimLog {} {
        variable LOG_MAX_LINES
        set lines [.log count -lines 0.0 end]
        set deleteTo [expr {$lines - $LOG_MAX_LINES + 1}]
        if {$deleteTo > 0} {
            .log delete 1.0 $deleteTo.0    
        }
    }
    
    # remove all lines from log
    proc clearLog {} {
        .log configure -state normal
        .log delete 1.0 end
        .log configure -state disabled
    }
    
    # post interactive command for sending
    proc postIaCmd {cmd} {
        variable interactiveCmd
        set cmd [string trim $cmd]
        if {$cmd == ""} {
            appendLog "\n" command
        } else {
            .cmd config -state disabled
            set interactiveCmd $cmd
            sendACmd 
        }
    }
    
    # post background command
    proc post {args} {
        variable autoCmd
        variable autoCmdComplete
        set autoCmdComplete 0
        set autoCmd $args
        sendACmd   
    }
    
    # send a command, based on what commands are pending, interactive or auto,
    # and what type of command was sent previously
    proc sendACmd {} {
        variable interactiveCmd
        variable autoCmd
        variable lastCmdAuto
        variable busy
        if {$busy} {
            return
        }
        if {$interactiveCmd != "" && $autoCmd == ""} {
            set lastCmdAuto 0
            sendCmd $interactiveCmd
        } elseif {$interactiveCmd == "" && $autoCmd != ""} {
            set lastCmdAuto 1
            sendCmd $autoCmd
        } else {
            if {$lastCmdAuto} {
                set lastCmdAuto 0  
                sendCmd $interactiveCmd
            } else {
                set lastCmdAuto 1
                sendCmd $autoCmd    
            }
        }
    }
    
    # send supplied command
    proc sendCmd {cmdLine} {
        variable cmdHistory 
        variable historyIndex 
        variable HISTORY_MAX_CMDS          
        variable fd 
        variable lastCmdAuto 
        variable busy
        set busy 1
        if {!$lastCmdAuto} {
            appendLog "$cmdLine\n" command 
            if {$cmdLine != [lindex $cmdHistory end]} {
                lappend cmdHistory $cmdLine
            }
            if {[llength $cmdHistory] > $HISTORY_MAX_CMDS} {
                set cmdHistory [lreplace $cmdHistory 0 0]
            }
            set historyIndex [llength $cmdHistory]
        }
        puts $fd "$cmdLine"
        puts $fd "\x03"; flush $fd
    }
    
    # sets command line entry widget, based on current historyIndex and dir.
    # dir may be up or down.
    proc setCmdLine {dir} {
        variable cmdHistory
        variable historyIndex
        variable cmdLine
        variable currentEditCmd
        if {$dir == "up"} {
            if {$historyIndex > 0} {
                if {$historyIndex == [llength $cmdHistory]} {
                    set currentEditCmd $cmdLine   
                }
                incr historyIndex -1
                set cmdLine [lindex $cmdHistory $historyIndex]
                .cmd icursor end
            }
        } elseif {$historyIndex < [llength $cmdHistory]} {
            incr historyIndex
            if {$historyIndex == [llength $cmdHistory]} {
                set cmdLine $currentEditCmd
            } else {
                set cmdLine [lindex $cmdHistory $historyIndex]
            }
            .cmd icursor end                             
        }
    }
    
    # called when app is closing, either due to exit command or window close
    # button pressed
    proc closeApp {} {
        variable fd
        close $fd
        saveHistory
        if {[llength [info procs ::closing]] == 1} {
            closing
        }
        exit 0
    }
    
    # load command history from ~./iatclsh file
    proc loadHistory {} {
        variable cmdHistory
        variable historyIndex
        set f [open "~/.iatclsh" r]
        while {1} {
            gets $f cmd
            if {[eof $f]} {
                break
            }
            lappend cmdHistory $cmd
        }
        set historyIndex [llength $cmdHistory]
        close $f
    }

    # save command history to ~./iatclsh file
    proc saveHistory {} {
        variable cmdHistory
        if {[lindex $cmdHistory end] == "exit"} {
            set cmdHistory [lreplace $cmdHistory end end]   
        }
        set f [open "~/.iatclsh" w]
        foreach cmd $cmdHistory {
            puts $f $cmd   
        }
        close $f
    }

    # returns 1 if background command pending, otherwise 0
    proc pending {} {
        variable autoCmd
        if {$autoCmd == ""} {
            return 0
        }
        return 1
    }
    
    # sends command and returns all response from background command
    proc cmd {args} {
        variable bgndRxBuf 
        if {![pending]} {
            post {*}$args
            set bgndRxBuf ""
            return [getAll]
        }
        return ""
    }
    
    # get a line of response from background command
    proc getLine {} {
        variable bgndRxBuf
        while {1} {
            if {[regexp {^(.*?)\n(.*)$} $bgndRxBuf match before after]} {
                set bgndRxBuf $after
                return $before
            }
            vwait ::iatclsh::bgndRxBuf
        }
    }

    # get complete response from background command
    proc getAll {} {
        variable bgndRxBuf
        variable autoCmdComplete
        while {1} {
            vwait ::iatclsh::autoCmdComplete
            if {$autoCmdComplete} {
                regexp {(.*)\n$} $bgndRxBuf match line
                set bgndRxBuf ""
                return $line
            }
        }
    }

    proc isStatusBarHidden {} {
        variable statusHidden
        return $statusHidden
    }

    proc showStatusBar {} {
        variable statusHidden
        if {$statusHidden} {
            set statusHidden 0
            grid .status
        }
    }
    
    proc hideStatusBar {} {
        variable statusHidden
        if {!$statusHidden} {
            set statusHidden 1
            grid remove .status
        }
    }

    # set status bar left label
    proc setStatusLeft {str} {
        variable statusLeft
        if {[isStatusBarHidden]} {
            showStatusBar 
        }
        set statusLeft $str    
    }
    
    # set status bar right label
    proc setStatusRight {str} {
        variable statusRight
        if {[isStatusBarHidden]} {
            showStatusBar 
        }
        set statusRight $str
    }

    # diaplay menu bar for actions menu
    proc displayMenuBar {} {
        .mbar add cascade -label Actions -menu .mbar.actions -underline 0
        . configure -menu .mbar
    }

    # add command to action menu
    proc addAction {label args} {
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        foreach param {-command -submenu} {
            set c [getActionParam $param {*}$args]
            if {$c != ""} {
                .mbar.actions add command -label $label -command $c
            } 
        }
    }
    
    # add check box actions to action menu
    proc addCBAction {label var args} {
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        .mbar.actions add checkbutton -label $label -variable $var
        if {$args != ""} {
            puts "args: $args"
        }
        if {[getActionParam "-command"] != ""} {
            set command [getActionParam "-command" $args]
            puts "-command: $command"
        }
        if {[getActionParam "-submenu"] != ""} {
            set submenu [getActionParam "-submenu" $args]
            puts "-submenu: $submenu"
        }
    }

    # add radio button actions to action menu
    proc addRBAction {labels var args} {
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        foreach label $labels {
            .mbar.actions add radiobutton -label $label -variable $var
        }
        if {[getActionParam "-command"] != ""} {
            set command [getActionParam "-command" $args]
            puts "-command: $command"
        }
        if {[getActionParam "-submenu"] != ""} {
            set submenu [getActionParam "-submenu" $args]
            puts "-submenu: $submenu"
        }
    }

    # parse variable args supplied to action commands for a specific parameter
    proc getActionParam {param args} {
        for {set i 0} {$i < [llength $args]} {incr i} {
            if {[lindex $args $i] == $param} {
                incr i
                return [lindex $args $i]
            }
        }
        return "" 
    }

    # add separator to actions menu
    proc addSeparator {} {
        .mbar.actions add separator
    }

    # stop executing run procedure
    proc stop {} {
        variable runStopped
        set runStopped 1
    }
    
    # resume executing run procedure 
    proc resume {} {
        variable runStopped
        variable pause 
        if {$runStopped} {
            set runStopped 0
            after 0 {set pause 0}
        }
    }

    # gui
    proc buildGui {} {
        tk::text .log -background black -yscrollcommand ".sb set"
        ttk::scrollbar .sb -command ".log yview"
        ttk::entry .cmd -textvariable iatclsh::cmdLine
        ttk::frame .status
        ttk::label .status.left -textvariable iatclsh::statusLeft
        ttk::label .status.right -textvariable iatclsh::statusRight
        option add *Menu.tearOff 0
        menu .mbar
        menu .mbar.actions
        .log configure -state disabled 
        .log tag configure command -foreground green
        .log tag configure response -foreground lightgrey
        .log tag configure error -foreground red
        bind .cmd <Return> [namespace code {postIaCmd $cmdLine}]
        bind .cmd <Up> [namespace code {setCmdLine up}]
        bind .cmd <Down> [namespace code {setCmdLine dn}]
        bind .cmd <braceleft> {event generate .cmd <braceright>; \
                event generate .cmd <Left>}
        bind .cmd <bracketleft> {event generate .cmd <bracketright>; \
                event generate .cmd <Left>}
        grid .log -row 0 -column 0 -sticky nsew
        grid .sb -row 0 -column 1 -sticky ns
        grid .cmd -row 1 -column 0 -columnspan 2 -sticky ew 
        grid .status -row 2 -column 0 -columnspan 2 -pady {5 0} -sticky ew
        grid columnconfigure . 0 -weight 1
        grid rowconfigure . 0 -weight 1
        grid .status.left -row 0 -column 0 -sticky nw  
        grid .status.right -row 0 -column 1 -sticky ne
        grid columnconfigure .status 0 -weight 1                       
        grid remove .status
        grid remove .sb
        wm protocol . WM_DELETE_WINDOW [namespace code closeApp] 
        wm title . "iatclsh"
        focus .cmd
    }
    
    proc main {} {
        variable showScrollBar
        variable sourceFiles
        variable runStopped
        variable pause
        
        buildGui
            
        if {[parseCmdLineArgs] == 0} {
            tk_messageBox -type ok -icon error -title "Error" \
                    -message "Error parsing command line parameters"
            exit 1
        }
        
        if {$showScrollBar} {
            grid .sb
        }
        
        # set main window title bar 
        if {[llength sourceFiles] != 0} {
            set t ""
            foreach f $sourceFiles {
                set t "$t [file tail $f]"
            }
            wm title . "[wm title .] -$t"    
        }
        
        # load history from previously saved file
        catch iatclsh::loadHistory
        
        # initilise and log any messages from sourced files
        set msg ""
        if {![startUp msg]} {
            tk_messageBox -type ok -icon error -title "Error" -message $msg
            exit 1
        }
        appendLog $msg response
        
        # load and run config file
        if {$iatclsh::configFile != ""} {
            if {[catch {namespace eval :: {source $iatclsh::configFile}}]} {
                appendLog $::errorInfo response
            } else {
                if {[llength [info procs ::initialise]] == 1} {
                    if {[catch initialise]} {
                        appendLog $::errorInfo response
                        return
                    } 
                }
                while {1} {
                    if {$runStopped == 0 && [llength [info procs ::run]] == 1} {
                        if {[catch {set rv [run]}]} {
                            appendLog $::errorInfo response
                            break
                        }
                        if {[string is integer -strict $rv]} {
                            set runStopped 0
                            after $rv {set pause 0}
                        } else {
                            set runStopped 1
                        }
                    } 
                    vwait pause
                }
            }
        }
    }
    
    main
}

