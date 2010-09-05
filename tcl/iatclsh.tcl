#!/usr/bin/tclsh8.5

#
# iatclsh.tcl
#
package require Tk

namespace eval iatclsh {    
    set exports [list \
            slaveInterpVarChange \
            pending post cmd getLine getAll stop start \
            isStatusBarHidden showStatusBar hideStatusBar \
            setStatusLeft setStatusRight getBusyString \
            addAction addCBAction addRBAction addSeparator] 
            
    # for command line 
    variable bgScript ""
    variable userFile 
    variable showScrollBar 0

    # for command history
    variable HISTORY_MAX_CMDS 100
    variable LOG_MAX_LINES 10000
    variable cmdHistory [list]                       
    variable historyIndex 0
    variable currentEditCmd ""

    # for running interactive/background commands
    variable bgndRxBuf ""    
    variable cmdLine ""
    variable lastCmdAuto 0
    variable interactiveCmd ""
    variable bgCmd ""
    variable bgCmdComplete 0
    variable busy 0
    variable runStopped 0
    variable reloadBgScriptScheduled 0
    variable inRunCycle 0
    variable running 0
    variable bgScriptOk 1 
    variable appIf [file dirname [info script]]/app_if.tcl
    variable fd
    variable bgInterp ""
    
    # for actions
    variable subMenuCount 0
    variable traces [dict create]
    variable statusHidden 1
    
    # for busy string
    variable busyCount 0
    variable busyTime [clock milliseconds]
    
    # parse command line arguments. Returns 1 if command line parsed 
    # successfully, otherwise 0
    proc parseCmdLineArgs {} {
        global argc argv 
        variable bgScript
        variable userFile "" 
        variable showScrollBar
        set i 0
        while {$i < $argc} {
            set t [lindex $argv $i]
            if {[regexp {^-} $t]} {
                if {$t == "-sc"} {
                    set showScrollBar 1
                    incr i
                } elseif {$t == "-bg"} {
                    incr i
                    if {$i >= $argc} {
                        return 0
                    }
                    set bgScript [lindex $argv $i]
                    incr i
                } else {
                    return 0
                }
            } else {
                if {$userFile == ""} {
                    set userFile $t
                } else {
                    return 0
                }
                incr i
            }
        }
        return 1
    }
  
    # open pipe to app interface and source any user file 
    proc startUp {} {
        variable fd 
        variable userFile
        variable appIf
        set exe [info nameofexecutable]
        set fd [open "|$exe $appIf" r+]
        chan configure $fd -blocking 0
        if {$userFile != ""} {
            .cmd configure -state disabled
            sourceUserFile
            .cmd configure -state normal
        }
        chan event $fd readable ::iatclsh::readPipe
    }

    # source user file. Writes to log any resulting messages
    proc sourceUserFile {} {
        variable userFile
        variable fd 
        puts $fd "cd [file dirname $userFile]"
        puts $fd "source [file tail $userFile]"
        puts $fd "\x03"; flush $fd
        while {1} {
            set l [read $fd]
            if {$l == ""} {
                after 50
                continue
            } 
            if {[regexp {^(.*)\x03\n$} $l match l]} {
                if {$l != ""} {
                    appendLog "$l" response
                    update idletasks
                }
                break
            } else {
                appendLog "$l" response
                update idletasks
            }
        }
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
        variable bgCmd
        variable lastCmdAuto
        variable busy
        variable bgCmdComplete
        set busy 0
        if {$lastCmdAuto} {
            set bgCmd ""
            set bgCmdComplete 1
            if {$interactiveCmd != ""} {
                sendACmd   
            }
        } else {
            set cmdLine ""
            set interactiveCmd ""
            .cmd config -state normal
            if {$bgCmd != ""} {
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
        variable bgCmd
        variable bgCmdComplete
        set bgCmdComplete 0
        set bgCmd $args
        sendACmd   
    }
    
    # send a command, based on what commands are pending, interactive or auto,
    # and what type of command was sent previously
    proc sendACmd {} {
        variable interactiveCmd
        variable bgCmd
        variable lastCmdAuto
        variable busy
        if {$busy} {
            return
        }
        if {$interactiveCmd != "" && $bgCmd == ""} {
            set lastCmdAuto 0
            sendCmd $interactiveCmd
        } elseif {$interactiveCmd == "" && $bgCmd != ""} {
            set lastCmdAuto 1
            sendCmd $bgCmd
        } else {
            if {$lastCmdAuto} {
                set lastCmdAuto 0  
                sendCmd $interactiveCmd
            } else {
                set lastCmdAuto 1
                sendCmd $bgCmd    
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
        variable bgCmd
        if {$bgCmd == ""} {
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
        variable bgCmdComplete
        while {1} {
            vwait ::iatclsh::bgCmdComplete
            if {$bgCmdComplete} {
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
    proc addAction {label command} {
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        .mbar.actions add command -label $label \
                -command "$::iatclsh::bgInterp eval $command"
    }
    
    # add check box actions to action menu
    proc addCBAction {label var args} {
        variable bgInterp
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        global shadow_$var
        set shadow_$var [$bgInterp eval set ::$var] 
        .mbar.actions add checkbutton -label $label -variable shadow_$var
        set command [getActionParam "-command" {*}$args]
        addVariableTraces $var $command
    }

    # add radio button actions to action menu
    proc addRBAction {labels var args} {
        variable bgInterp
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        set m .mbar.actions
        set subMenuLabel [getActionParam "-submenu" {*}$args]
        if {$subMenuLabel != ""} {
            set tail [getSubMenuTail]
            $m add cascade -label $subMenuLabel -menu $m.$tail
            menu $m.$tail
            set m $m.$tail
        } 
        global shadow_$var
        set shadow_$var [$bgInterp eval set ::$var] 
        foreach label $labels {
            $m add radiobutton -label $label -variable shadow_$var
        }
        set command [getActionParam "-command" {*}$args]
        addVariableTraces $var $command
    }

    # add separator to actions menu
    proc addSeparator {} {
        .mbar.actions add separator
    }

    # get unique tail for submenu
    proc getSubMenuTail {} {
        variable subMenuCount
        incr subMenuCount
        return $subMenuCount
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

    # add traces to an action variable, both slave and shadow
    proc addVariableTraces {var command} {
        global shadow_$var
        variable bgInterp
        variable traces
        dict set traces shadow_$var $command
        trace add variable shadow_$var write iatclsh::variableTrace
        $bgInterp eval trace add variable ::$var write slaveInterpVarChange
    }

    # for managing slave variables and calling check-box and radio-button 
    # action commands
    proc variableTrace {name element op} {
        variable traces
        variable bgInterp
        set command [dict get $traces $name]
        set slaveName [string range $name 7 end]
        set val [eval set ::$name]
        $bgInterp eval set $slaveName $val
        if {$command != ""} {
            $bgInterp eval $command
        }
    }

    # called when a variable is changed in the slave interpreter that is also
    # used in the Actions menu
    proc slaveInterpVarChange {name element op} {
        variable bgInterp
        global shadow_$name
        set shadow_$name [$bgInterp eval set ::$name] 
    }

    # stop executing run procedure
    proc stop {} {
        variable runStopped
        set runStopped 1
    }
    
    # start executing run procedure 
    proc start {} {
        variable runStopped
        if {$runStopped} {
            set runStopped 0
            executeRun
        }
    }

    # returns next phase in a sequence of strings. If period is supplied, next
    # phase is provided only if time difference since last successful call 
    # exceeds period
    proc getBusyString {{period ""}} {
        variable busyCount
        variable busyTime
        if {$period == "" || [clock milliseconds] - $busyTime > $period} {
            incr busyCount
            if {$busyCount == 4} {
                set busyCount 0
            }
            set busyTime [clock milliseconds]
        }
        switch $busyCount {
            0 {return "|"}
            1 {return "/"}
            2 {return "-"}
            3 {return "\\"}
        }
    }

    # gui
    proc buildGui {} {
        # components
        tk::text .log -background black -yscrollcommand ".sb set"
        ttk::scrollbar .sb -command ".log yview"
        ttk::entry .cmd -textvariable iatclsh::cmdLine
        ttk::frame .status
        ttk::label .status.left -textvariable iatclsh::statusLeft
        ttk::label .status.right -textvariable iatclsh::statusRight
        option add *Menu.tearOff 0
        menu .mbar
        menu .mbar.actions
        menu .puMenu

        # pop up menu
        .puMenu add command -label "Load User Script" \
                -command {iatclsh::openUserScript}
        .puMenu add command -label "Load Background Script" \
                -command {iatclsh::openBgScript}
        .puMenu add separator
        .puMenu add command -label "Reload User Script" \
                -command {iatclsh::reloadUserScript}
        .puMenu add command -label "Reload Background Script" \
                -command {iatclsh::reloadBgScript}
        .puMenu add separator
        .puMenu add command -label "Clear" -command {::iatclsh::clearLog}

        # configure log
        .log configure -state disabled 
        .log tag configure command -foreground green
        .log tag configure response -foreground lightgrey
        .log tag configure error -foreground red

        # bindings
        bind .cmd <Return> [namespace code {postIaCmd $cmdLine}]
        bind .cmd <Up> [namespace code {setCmdLine up}]
        bind .cmd <Down> [namespace code {setCmdLine dn}]
        bind .cmd <braceleft> {event generate .cmd <braceright>; \
                event generate .cmd <Left>}
        bind .cmd <bracketleft> {event generate .cmd <bracketright>; \
                event generate .cmd <Left>}
        bind .log <ButtonPress-3> {tk_popup .puMenu %X %Y}

        # layout 
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
 
    # update gui state based on state of program
    proc updateGuiState {} {
        variable userFile
        variable bgScript
        if {[llength $userFile] == 0} {
            .puMenu entryconfigure "Reload User Script" -state disabled
        } else {
            .puMenu entryconfigure "Reload User Script" -state normal
        }
        if {$bgScript == ""} {
            .puMenu entryconfigure "Reload Background Script" -state disabled
        } else {
            .puMenu entryconfigure "Reload Background Script" -state normal
        }
        # set main window title bar 
        if {$userFile == ""} {
            wm title . "iatclsh"
        } else {
            wm title . "iatclsh - [file tail $userFile]"    
        }
    }

    # present a file open dialog and load user script if one is chosen
    proc openUserScript {} {
        variable userFile  
        set f [tk_getOpenFile -filetypes {{Tcl .tcl} {All *}}]
        if {$f == ""} {
            return
        }
        set userFile $f
        updateGuiState
        clearIaCommand
        startUp
    }

    # present a file open dialog and load background script if one is chosen
    proc openBgScript {} {
        variable bgScript
        set f [tk_getOpenFile -filetypes {{Tcl .tcl} {All *}}]
        if {$f == ""} {
            return
        }
        set bgScript $f
        reloadBgScript
    }

    # close current open interface and open a new one
    proc reloadUserScript {} {
        clearIaCommand
        startUp 
    }

    # clear any pending interactive command ready for loading of user script
    proc clearIaCommand {} {
        variable fd
        variable bgCmd
        variable interactiveCmd
        variable cmdLine
        variable busy
        variable bgndRxBuf 
        variable bgCmdComplete
        close $fd
        set bgCmd ""
        set interactiveCmd ""
        set cmdLine ""
        set busy 0
        set bgndRxBuf "\n"
        .cmd config -state normal
        set bgCmdComplete 1
    }
    
    # reload background script, either immediately if a background command
    # isn't running, otherwise schedule reload for when background command 
    # completes
    proc reloadBgScript {} {
        variable inRunCycle
        variable reloadBgScriptScheduled 
        variable bgScriptOk
        variable running
        if {$inRunCycle == 0} {
            set reloadBgScriptScheduled 0
            shutdownBgScriptState
            set bgScriptOk [loadBgScript]
            if {$bgScriptOk} {
                executeInitialise
                if {[. cget -menu] == ".mbar"} {
                    .mbar entryconfigure "Actions" -state normal
                }
                .puMenu entryconfigure "Reload Background Script" \
                        -state normal
                if {$running == 0} {
                    executeRun
                } 
            }
        } else {
            .mbar entryconfigure "Actions" -state disabled
            .puMenu entryconfigure "Reload Background Script" -state disabled
            set reloadBgScriptScheduled 1
        }
    }

    proc shutdownBgScriptState {} {
        variable traces
        variable bgInterp
        if {$bgInterp == ""} {
            return
        }
        if {[llength [info procs ::closing]] == 1} {
            ::closing
        } 
        setStatusRight ""
        setStatusLeft ""
        hideStatusBar
        . configure -menu ""
        destroy .mbar.actions
        destroy .mbar
        menu .mbar
        menu .mbar.actions
        . configure -menu 
        interp delete $bgInterp
        foreach var [dict keys $traces] {
            unset ::$var
        }
        set traces ""
    }

    # load background script. Returns 1 if successful, 0 otherwise.
    proc loadBgScript {} {
        variable exports
        variable bgInterp
        set bgInterp [interp create]
        foreach e $exports {
            $bgInterp alias $e ::iatclsh::$e
        }
        if {[catch {$bgInterp eval " 
                    cd [file dirname $iatclsh::bgScript]
                    source [file tail $iatclsh::bgScript]
                "}]} {
            appendLog $::errorInfo response
            return 0
        }
        return 1 
    }

    # execute initialise command provided by background script. Returns 1 if 
    # initialise isn't provided, or if initialise is provided and successfully 
    # executes. Otherwise returns 0
    proc executeInitialise {} {
        variable bgInterp
        if {[$bgInterp eval {llength [info procs ::initialise]}] == 1} {
            if {[catch {$bgInterp eval ::initialise}]} {
                appendLog $::errorInfo response
                return 0
            } 
        }
        return 1
    }

    # repeatedly execute run command provided by background script
    proc executeRun {} {
        variable runStopped
        variable inRunCycle
        variable running
        variable reloadBgScriptScheduled
        variable bgScriptOk
        variable bgInterp
        set running 1
        set inRunCycle 1
        if {$bgScriptOk == 0} {
            set inRunCycle 0
            set running 0
        }
        if {$runStopped == 0 && \
                    [$bgInterp eval {llength [info procs ::run]}] == 1} {
            if {[catch {set rv [$bgInterp eval run]}]} {
                appendLog $::errorInfo response
                set inRunCycle 0
                set running 0
            }
            if {[string is integer -strict $rv]} {
                set runStopped 0
                after $rv iatclsh::executeRun
            } else {
                set runStopped 1
            }
        } 
        set inRunCycle 0
        if {$reloadBgScriptScheduled} {
            reloadBgScript
        }   
    }

    proc main {} {
        variable showScrollBar
        variable bgScript
        
        buildGui
            
        if {[parseCmdLineArgs] == 0} {
            tk_messageBox -type ok -icon error -title "Error" \
                    -message "Error parsing command line parameters"
            exit 1
        }
        
        if {$showScrollBar} {
            grid .sb
        }
        
        # load history from previously saved file
        catch iatclsh::loadHistory

        # show gui before start up
        update 
        
        updateGuiState
        
        # open app interface and source any user file
        startUp 

        # load and run background script
        if {$bgScript != "" && [loadBgScript]} {
            if {[executeInitialise]} {
                executeRun
            }
        }
    }
    
    main
}

