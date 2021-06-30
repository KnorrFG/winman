For this to work, the program must be DPI aware (per Monitor v2). This is
configured in the manifest file, which MUST be linked, otherwise the window
placement will be pretty off, because some functions will work with actual
sizes, and some will work with scaled sizes. 

The b task in the nimble file, handles this. It call windres, which is a tool
that comes bundled with the default mingw distribution for nim. However, nimble
does not add the mingw folder to the path automatically, so for this to work,
you must make sure, windres is in the path

Todo next:
Select window on depth isnt implemented yet.
Also, when using v, h, and d prefixes, it will only work, if the currently
selected window is managed. but its very intuitive to press that directly
before grabbing a new window, when the new window is already active. And this
2nd scenario should work too.
