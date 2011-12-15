#
# ttaskfile for iatclsh 
#

# for linux kill gcc
config incPath /usr/include/tcl8.5
config libPath /usr/lib

# for tclkit 
config runtimeDir ~/tclkit
config linuxRuntime tclkit-8.5.9-linux-ix86
config winRuntime tclkit-8.5.9-win32.upx.exe

config installDir ~/bin

set archiveSrc {iatclsh.tcl app_if.tcl PrefsDlg.tcl}

task build {
    linuxKillLib build
    linuxTclkit build
    winTclkit build
    tarArchive build
    zipArchive build
}
task install {mkdir $installDir; cp build/linux/iatclsh $installDir}
task clean {rmdir build}

# linux kill shared library
project add linuxKillLib -type gcc
linuxKillLib src -add lib/linux_kill.c
linuxKillLib build -buildDir build/libkill \
        -cFlags {-Wall -O2 -DUSE_TCL_STUBS} -incPath $incPath \
        -libPath $libPath -lib tclstub8.5 -name libkill.so 

# linux starpack 
project add linuxTclkit -type tclkit
linuxTclkit src -srcDir tcl -add *.tcl -srcDir build/libkill -add libkill.so
linuxTclkit build -buildDir build/linux -runtime $runtimeDir/$linuxRuntime \
        -prepare wrapper.tcl -name iatclsh

# windows starpack
project add winTclkit -type tclkit
winTclkit src -srcDir tcl -add *.tcl 
winTclkit build -buildDir build/win -runtime $runtimeDir/$winRuntime \
        -prepare wrapper.tcl -name iatclsh

# tar archive 
project add tarArchive -type tar
tarArchive src -srcDir tcl -add $archiveSrc \
        -srcDir build/libkill -add libkill.so
tarArchive build -buildDir build/tar -name iatclsh.tar.gz

# zip archive 
project add zipArchive -type zip
zipArchive src -srcDir tcl -add $archiveSrc 
zipArchive build -buildDir build/zip -name iatclsh.zip

