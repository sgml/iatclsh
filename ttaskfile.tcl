#
# ttaskfile for iatclsh 
#

task build {
    tarArchive build 
    zipArchive build -exe wrap
}
task clean {rmdir build}

# tar archive 
project add tarArchive -type tar
tarArchive src -srcDir tcl -add *.tcl
tarArchive build -buildDir build -name iatclsh.tar.gz

# zip archive 
project add zipArchive -type zip
zipArchive build -buildDir build -name iatclsh.zip

