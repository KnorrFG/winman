# Package

version       = "0.1.0"
author        = "Felix Knorr"
description   = "A window manager for Windows"
license       = "MIT"
srcDir        = "src"
bin           = @["winman"]


# Dependencies

requires "nim >= 1.4.6", "winim"

task buildRes, "compiles the resources.rc":
  echo "Compiling Resource"
  exec "windres -i resources.rc -o resources.o"

before build:
  echo "INFO: running before build macro"
  if not fileExists "resources.o":
    exec "windres -i resources.rc -o resources.o"
