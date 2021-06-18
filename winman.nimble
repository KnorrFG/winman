# Package

version       = "0.1.0"
author        = "Felix Knorr"
description   = "A window manager for Windows"
license       = "MIT"
srcDir        = "src"
bin           = @["winman"]


# Dependencies

requires "nim >= 1.4.6", "winim"

task b, "build and run":
  echo "INFO: running custom build task"
  exec "windres -i resources.rc -o resources.o"
  --gc:orc
  --define:noRes
  --passL:resources.o
  setCommand "build", "winman"
