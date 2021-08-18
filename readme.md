# Winman

This is going to be a pragmatic, i3 inspired window manager for windows 10. 
Its still in development.

## Dev notes

The basic Idea is, that windows are layed out in a tree. A tree has container
and leaf nodes. A leaf node, represents a window. A container holds other nodes
and has an orientation. Horizontal, vertical, and deep. Deep means, its
children are layed out on the z-axis. 

As there is no way in windows to get notified reliably when a new window is
created, you have to "grab" window, to bring it under the window managers
control. Currently that is done by pressing Ctrl + Shift + Alt + G. I'll refer
to the modifier combination as MEH from here on out.
If you press MEH + one of V, H, or D before grabbing a window, the last window
will be wrapped into a new container with the respective orientation, and the
new window will be added to it.

Windows that are managed by winman will be checked twice per secon for whether
they still exist, and if they dont, they are kicked, and everything else is
resized. (This is done in one thread, in a mainloop)

## Plans for the future.

Besides implemententing all the features you'd expect from a sensible window
manager, I'll also add a launcher to it, so that it is possible to
automatically grab the windows, that you start through the launcher.

## Building

This is a windows program, and requires a manifest. The before build part of
the nimble file takes care of it. However, if you, for what ever reason, change
the resources.rc file, it will not automatically be remopiled. Mainly because
the getFileInfo() proc is not available in nimscript, so its not possible to
compare the lastEdited Timestamps.
