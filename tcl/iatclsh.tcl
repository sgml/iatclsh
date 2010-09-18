#!/usr/bin/tclsh8.5

#
# iatclsh.tcl
#
package require Tk

namespace eval iatclsh {    
    variable exports [list \
            slaveInterpVarChange \
            pending post cmd getLine getAll stop start \
            isStatusBarHidden showStatusBar hideStatusBar \
            setStatusLeft setStatusRight getBusyString \
            addAction addCBAction addRBAction addSeparator] 
            
    # bgScript and userScript are for holding the background and user script
    # filenames
    variable bgScript ""
    variable userScript ""

    # for user script: fd is the file descriptor for the pipe to the tclsh 
    # running the user script; appIf is the path to the app_if.tcl script
    variable fd ""
    variable appIf [file dirname [info script]]/app_if.tcl

    # for log and command history: LOG_MAX_LINES is the maximum number lines to
    # store in the log window;  HISTORY_MAX_COMMANDS is the maximum number of
    # interactive commands to store; cmdHistory is a list where the interactive
    # commands are stored; historyIndex is an index into cmdHistory; 
    # currentEditCmd is a store for an interactive command currently being
    # typed
    variable LOG_MAX_LINES 10000
    variable HISTORY_MAX_CMDS 100
    variable cmdHistory [list]
    variable historyIndex 0
    variable currentEditCmd ""

    # for running interactive/background commands: cmdLine is the variable 
    # associated with the command line entry widget; interactiveCmd is a buffer
    # for storing an interactive command entered in gui; bgCmd is a buffer for
    # storing a background command run from a background script; bgRxBuf is a 
    # buffer for holding the result of running a background command; lastCmdBg
    # indicates that the last command to run was a background command;
    # bgCmdComplete indicates that a background command has run and completed;
    # busy indicates that a command is running, either interactive or 
    # background
    variable cmdLine ""
    variable interactiveCmd ""
    variable bgCmd ""
    variable bgRxBuf ""    
    variable lastCmdBg 0
    variable bgCmdComplete 0
    variable busy 0

    # for backgound script: reloadUserScriptScheduled indicates that the user
    # script is scheduled for reload; reloadBgScriptScheduled indicates that
    # the background script has been scheduled for reload; bgScriptOk indicates 
    # that a background script has been loaded ok; bgInterp is the interpreter 
    # used for running background scripts
    variable reloadUserScriptScheduled 0 
    variable reloadBgScriptScheduled 0
    variable bgScriptOk 1 
    variable bgInterp ""
    
    # for run command: running indicates that the run command is running or 
    # scheduled to run; inRunCycle indicates that the run command is part way
    # through executing; stopRun indicates that the run procedure should stop
    variable running 0
    variable inRunCycle 0
    variable stopRun 0

    # for user interface relating to background script: subMenuCount holds 
    # count of menus added to Actions menu; traces maps Action menu variables
    # to procedures to run when they change; statusHidden controls whether 
    # the status bar is hidden
    variable subMenuCount 0
    variable traces [dict create]
    variable statusHidden 1
    
    # for busy string: busyCount keeps track of the current position in the
    # busy string sequence; busyTime records the time of the last sequence 
    # update
    variable busyCount 0
    variable busyTime [clock milliseconds]
    
    # controls whether scrollbar is visable
    variable showScrollBar 0

    # parse command line arguments. Returns 1 if command line parsed 
    # successfully, otherwise 0
    proc parseCmdLineArgs {} {
        global argc argv 
        variable bgScript
        variable userScript  
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
                if {$userScript == ""} {
                    set userScript $t
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
        variable userScript
        variable appIf
        set exe [info nameofexecutable]
        set fd [open "|$exe $appIf" r+]
        chan configure $fd -blocking 0
        if {$userScript != ""} {
            .cmdEntry configure -state disabled
            sourceUserFile
            .cmdEntry configure -state normal
        }
        chan event $fd readable ::iatclsh::readPipe
    }

    # source user file. Writes to log any resulting messages
    proc sourceUserFile {} {
        variable userScript
        variable fd 
        puts $fd "cd [file dirname $userScript]"
        puts $fd "source [file tail $userScript]"
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
        variable lastCmdBg
        variable bgRxBuf
        if {!$lastCmdBg} {
            if {$s == "\x11\n"} {
                clearLog
            } else {
                appendLog "$s" response
            }
            update idletasks
        } else {
            set bgRxBuf $bgRxBuf$s
        }
    }
    
    # command completed
    proc completedCmd {} {
        variable cmdLine 
        variable interactiveCmd
        variable bgCmd
        variable lastCmdBg
        variable busy
        variable bgCmdComplete
        set busy 0
        if {$lastCmdBg} {
            set bgCmd ""
            set bgCmdComplete 1
            if {$interactiveCmd != ""} {
                sendACmd   
            }
        } else {
            set cmdLine ""
            set interactiveCmd ""
            .cmdEntry config -state normal
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
            .cmdEntry config -state disabled
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
    
    # send a command, based on what commands are pending, interactive or 
    # background, and what type of command was sent previously
    proc sendACmd {} {
        variable interactiveCmd
        variable bgCmd
        variable lastCmdBg
        variable busy
        if {$busy} {
            return
        }
        if {$interactiveCmd != "" && $bgCmd == ""} {
            set lastCmdBg 0
            sendCmd $interactiveCmd
        } elseif {$interactiveCmd == "" && $bgCmd != ""} {
            set lastCmdBg 1
            sendCmd $bgCmd
        } else {
            if {$lastCmdBg} {
                set lastCmdBg 0  
                sendCmd $interactiveCmd
            } else {
                set lastCmdBg 1
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
        variable lastCmdBg 
        variable busy
        set busy 1
        if {!$lastCmdBg} {
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
                .cmdEntry icursor end
            }
        } elseif {$historyIndex < [llength $cmdHistory]} {
            incr historyIndex
            if {$historyIndex == [llength $cmdHistory]} {
                set cmdLine $currentEditCmd
            } else {
                set cmdLine [lindex $cmdHistory $historyIndex]
            }
            .cmdEntry icursor end                             
        }
    }
    
    # called when app is closing, either due to exit command or window close
    # button pressed
    proc closeApp {} {
        variable fd
        close $fd
        saveHistory
        executeClosing 
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
        variable bgRxBuf 
        if {![pending]} {
            post {*}$args
            set bgRxBuf ""
            return [getAll]
        }
        return ""
    }
    
    # get a line of response from background command
    proc getLine {} {
        variable bgRxBuf
        while {1} {
            if {[regexp {^(.*?)\n(.*)$} $bgRxBuf match before after]} {
                set bgRxBuf $after
                return $before
            }
            vwait ::iatclsh::bgRxBuf
        }
    }

    # get complete response from background command
    proc getAll {} {
        variable bgRxBuf
        variable bgCmdComplete
        while {1} {
            vwait ::iatclsh::bgCmdComplete
            if {$bgCmdComplete} {
                regexp {(.*)\n$} $bgRxBuf match line
                set bgRxBuf ""
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
        variable stopRun
        set stopRun 1
    }
    
    # start executing run procedure 
    proc start {} {
        variable stopRun
        variable running
        if {!$running} {
            set stopRun 0
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
        text .log -background black -yscrollcommand ".sb set"
        scrollbar .sb -command ".log yview"
        entry .cmdEntry -highlightthickness 0 -textvariable iatclsh::cmdLine
        frame .status
        label .status.left -justify left -textvariable iatclsh::statusLeft
        label .status.right -justify right \
                -textvariable iatclsh::statusRight
        option add *Menu.tearOff 0
        menu .mbar
        menu .mbar.actions
        menu .puMenu

        # pop up menu
        .puMenu add command -label "Load User Script" \
                -command iatclsh::loadUserScriptUIEvent
        .puMenu add command -label "Load Background Script" \
                -command iatclsh::loadBgScriptUIEvent
        .puMenu add separator
        .puMenu add command -label "Reload User Script" \
                -command iatclsh::reloadUserScriptUIEvent
        .puMenu add command -label "Reload Background Script" \
                -command iatclsh::reloadBgScriptUIEvent
        .puMenu add separator
        .puMenu add command -label "Reset tclsh" \
                -command iatclsh::resetTclshUIEvent
        .puMenu add command -label "Unload Background Script" \
                -command iatclsh::unloadBgScriptUIEvent
        .puMenu add separator
        .puMenu add command -label "Clear" -command ::iatclsh::clearLog

        # configure log
        .log configure -state disabled 
        .log tag configure command -foreground green
        .log tag configure response -foreground lightgrey
        .log tag configure error -foreground red

        # bindings
        bind .cmdEntry <Return> {::iatclsh::postIaCmd $iatclsh::cmdLine}
        bind .cmdEntry <Up> {::iatclsh::setCmdLine up}
        bind .cmdEntry <Down> {::iatclsh::setCmdLine dn}
        bind .cmdEntry <braceleft> {event generate .cmdEntry <braceright>; \
                event generate .cmdEntry <Left>}
        bind .cmdEntry <bracketleft> {event generate .cmdEntry <bracketright>; \
                event generate .cmdEntry <Left>}
        bind .log <ButtonPress-3> {tk_popup .puMenu %X %Y}

        # layout 
        grid .log -row 0 -column 0 -sticky nsew
        grid .sb -row 0 -column 1 -sticky ns
        grid .cmdEntry -row 1 -column 0 -columnspan 2 -sticky ew 
        grid .status -row 2 -column 0 -columnspan 2 -pady {5 0} -sticky ew
        grid columnconfigure . 0 -weight 1
        grid rowconfigure . 0 -weight 1
        grid .status.left -row 0 -column 0 -sticky nw  
        grid .status.right -row 0 -column 1 -sticky ne
        grid columnconfigure .status 0 -weight 1                       
        grid remove .status
        grid remove .sb
        wm protocol . WM_DELETE_WINDOW ::iatclsh::closeApp 
        wm title . "iatclsh"
        focus .cmdEntry
    }
 
    # update gui state based on state of program
    proc updateGuiState {} {
        variable userScript
        variable bgScript
        variable reloadUserScriptScheduled 
        variable reloadBgScriptScheduled 

        # reload user script popup menu state
        if {$userScript == "" || $reloadUserScriptScheduled} {
            .puMenu entryconfigure "Reload User Script" -state disabled
        } else {
            .puMenu entryconfigure "Reload User Script" -state normal
        }

        # reload/unload background script popup menu state
        if {$bgScript == "" || $reloadBgScriptScheduled} {
            .puMenu entryconfigure "Reload Background Script" -state disabled
            .puMenu entryconfigure "Unload Background Script" -state disabled
        } else {
            .puMenu entryconfigure "Reload Background Script" -state normal
            .puMenu entryconfigure "Unload Background Script" -state normal
        }

        # menu bar state
        if {$reloadBgScriptScheduled} {
            if {[. cget -menu] == ".mbar"} {
                .mbar entryconfigure "Actions" -state disabled
            }
        } else {
            if {[. cget -menu] == ".mbar"} {
                .mbar entryconfigure "Actions" -state normal
            }
        }

        # set main window title bar 
        if {$userScript == ""} {
            wm title . "iatclsh"
        } else {
            wm title . "iatclsh - [file tail $userScript]"    
        }
    }

    # present a file open dialog and load user script if one is chosen
    proc loadUserScriptUIEvent {} {
        variable userScript  
        variable reloadUserScriptScheduled 
        variable inRunCycle
        set f [tk_getOpenFile -filetypes {{Tcl .tcl} {All *}}]
        if {$f == ""} {
            return
        }
        set userScript $f
        reloadUserScriptUIEvent
    }

    # present a file open dialog and load background script if one is chosen
    proc loadBgScriptUIEvent {} {
        variable bgScript
        set f [tk_getOpenFile -filetypes {{Tcl .tcl} {All *}}]
        if {$f == ""} {
            return
        }
        set bgScript $f
        reloadBgScriptUIEvent
    }

    # reload user script, either immediately if a background command isn't
    # running, otherwise schedule reload for when background command completes
    proc reloadUserScriptUIEvent {} {
        variable reloadUserScriptScheduled 
        variable inRunCycle
        if {$inRunCycle == 0} {
            reloadUserScript
        } else {
            set reloadUserScriptScheduled 1
            updateGuiState
        }
    }

    # reload background script, either immediately if a background command
    # isn't running, otherwise schedule reload for when background command 
    # completes
    proc reloadBgScriptUIEvent {} {
        variable reloadBgScriptScheduled 1
        variable inRunCycle
        if {$inRunCycle == 0} {
            reloadBgScript
        } else {
            set reloadBgScriptScheduled 1
            updateGuiState
        }
    }

    # reset tclsh
    proc resetTclshUIEvent {} {
        variable userScript
        variable bgRxBuf
        variable bgCmdComplete
        set userScript ""
        set bgRxBuf "\n"
        set bgCmdComplete 1
        reloadUserScript
    }

    # unload background script 
    proc unloadBgScriptUIEvent {} {
        variable bgScript 
        variable bgCmd
        variable reloadBgScriptScheduled 
        variable running
        variable inRunCycle
        variable stopRun
        shutdownBgScriptState
        set bgScript ""
        set bgCmd ""
        set reloadBgScriptScheduled 0
        set running 0
        set inRunCycle 0
        set stopRun 1
        updateGuiState 
    }

    # reload user script
    proc reloadUserScript {} {
        variable reloadUserScriptScheduled 
        set reloadUserScriptScheduled 0
        shutdownIaScriptState 
        startUp 
        updateGuiState
    }
   
    # clear any pending interactive and user command, ready for loading of 
    # user script
    proc shutdownIaScriptState {} {
        variable fd
        variable bgCmd
        variable interactiveCmd
        variable cmdLine
        variable busy
        variable bgRxBuf 
        variable bgCmdComplete
        close $fd
        # set bgCmd ""
        set interactiveCmd ""
        set cmdLine ""
        set busy 0
        # set bgRxBuf "\n"
        .cmdEntry config -state normal
        # set bgCmdComplete 1
    }
 
    # reload background script
    proc reloadBgScript {} {
        variable reloadBgScriptScheduled 
        variable bgScriptOk
        variable running
        set reloadBgScriptScheduled 0
        shutdownBgScriptState
        set bgScriptOk [loadBgScript]
        if {$bgScriptOk} {
            executeInitialise
            updateGuiState
            if {$running == 0} {
                executeRun
            } 
        } else {
            set running 0
        }
    }

    # shutdown background script user interface, i.e. menubar and statusbar
    proc shutdownBgScriptState {} {
        variable traces
        variable bgInterp
        if {$bgInterp == ""} {
            return
        }
        executeClosing
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
        set bgInterp ""
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
        set script [format {
                cd [file dirname %s] 
                source [file tail %s]
                } $iatclsh::bgScript $iatclsh::bgScript]
        if {[catch {$bgInterp eval $script}]} {
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

    # execute closing command provided by background script. Returns 1 if 
    # closing isn't provided, or if closing is provided and successfully 
    # executes. Otherwise returns 0
    proc executeClosing {} {
        variable bgInterp
        if {$bgInterp != "" && [$bgInterp eval {llength \
                    [info procs ::closing]}] == 1} {
            if {[catch {$bgInterp eval ::closing}]} {
                appendLog $::errorInfo response
                return 0
            } 
        }
        return 1
    }

    # repeatedly execute run command provided by background script
    proc executeRun {} {
        variable stopRun 
        variable inRunCycle
        variable running
        variable reloadUserScriptScheduled
        variable reloadBgScriptScheduled
        variable bgInterp
        set running 1
        set inRunCycle 1
        if {$stopRun == 0 && \
                    [$bgInterp eval {llength [info procs ::run]}] == 1} {
            if {[catch {set rv [$bgInterp eval run]}]} {
                appendLog $::errorInfo response
                set running 0
            } elseif {[string is integer -strict $rv]} {
                after $rv iatclsh::executeRun
            } else {
                set running 0
            }
        } else {
            set running 0
        }
        set inRunCycle 0
        if {$reloadUserScriptScheduled} {
            reloadUserScript
        }   
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

