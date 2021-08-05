For this to work, the program must be DPI aware (per Monitor v2). This is
configured in the manifest file, which MUST be linked, otherwise the window
placement will be pretty off, because some functions will work with actual
sizes, and some will work with scaled sizes. 

The b task in the nimble file, handles this. It call windres, which is a tool
that comes bundled with the default mingw distribution for nim. However, nimble
does not add the mingw folder to the path automatically, so for this to work,
you must make sure, windres is in the path

## Roadmap:

### First usable Version

- [x] depth selection
- [x] fix orientation input
- [x] deal with disapearing windows
- hk to remove window
- Touch and TouchParent
- groups

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
