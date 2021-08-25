For this to work, the program must be DPI aware (per Monitor v2). This is
configured in the manifest file, which MUST be linked, otherwise the window
placement will be pretty off, because some functions will work with actual
sizes, and some will work with scaled sizes. 

The b task in the nimble file, handles this. It call windres, which is a tool
that comes bundled with the default mingw distribution for nim. However, nimble
does not add the mingw folder to the path automatically, so for this to work,
you must make sure, windres is in the path

mouse focus does not switch reliably. This seems to be in context of maximizing
the window while it is under control of the wm. But also without a good excuse

The monitor rect is wrong, if display scaling is used


## Todo:

For the multimonitor and virtual desktop stuff: since there will be one tree
per GroupId AND virtual Desktop, I think this is the time to change this to
lazy tree creation. 

Also, when checking whether a window was closed, I should also check whether it
was moved to a different virtual desktop.

Also, per Tree, I'll need the Info which desktop its on, as well as the
ability, to move it to another desktop. Id provide just next and prev for
desktops. I hope the enumerateDesktops function will keep the order, when a new
one appears.

Also I need one active tree per virtual desktop.

## Known Problems

1. There will be a 2 pixel gap between Windows, that you cannot get rid off.
	 This is because the explorer window (and possibly others) will leak into
	 neighbouring displays without those gaps. Cant prevent that.
2. You might see windows move first, and resize afterwards. This isn't Ideal,
	 but if I do both on the same time, the window sizes will be messed up, when
	 moving the windows between displays with different scaling.

## Roadmap:

### First usable Version

- [x] depth selection
- [x] fix orientation input
- [x] deal with disapearing windows
- [x] hk to remove window
- Touch and TouchParent
- [x] groups
- [x] change orientation
- config
- fix the deep display bug (does it even exist?)
- also, before public release, logging might be a nice idea

### Horizon:

- config script
- multi monitor support 
	- there is an easy version of this, which just respekts other monitors on the
			current virtual desktop, and one hard version, which incorporates windows
			virtual desktops
	- There are also two versions of virtual desktop support: actually use
			windows virtual desktops as Groups, which will be very hard, and the
			second version is to have a set of groups per virtual desktop. Which is
			way easier, because it doesnt relly on unofficial and undocumented
			windows apis
- moving windows with a gui
- virtual desktop support
