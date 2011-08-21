/*
 * linux_kill.c
 *
 * Provides kill command for running under Linux
 */
#include <tcl.h>
#include <signal.h>
#include <sys/wait.h>

static int kill_cmd(ClientData clientData, Tcl_Interp *interp, int objc, 
        Tcl_Obj *CONST objv[]) {
    int pid, rc;
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "pid");
        return TCL_ERROR;
    }
    rc = Tcl_GetIntFromObj(interp, objv[1], &pid);
    if (rc != TCL_OK)
        return rc;
    rc = kill(pid, SIGTERM);
    if (rc == 0) {
        waitpid(pid, NULL, 0);
        Tcl_SetObjResult(interp, Tcl_NewBooleanObj(1));
    }
    else
        Tcl_SetObjResult(interp, Tcl_NewBooleanObj(0));
    return TCL_OK;
}

int Kill_Init(Tcl_Interp *interp) {
    Tcl_InitStubs(interp, "8.4", 0);
    Tcl_CreateObjCommand(interp, "iatclsh::kill", kill_cmd, NULL, NULL);
    return TCL_OK;
}

