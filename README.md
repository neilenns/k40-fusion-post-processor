# K40 Whisperer Fusion 360 Post Processor

## What is this?

This is a Post (https://cam.autodesk.com/hsmposts) for Fusion 360 and Autodesk HSM that produces SVG files from CAM operations that can be loaded into the K40 Whisperer
app without any further modifications.

This work is based on the [glowforge-colorific-fusion360-post](https://github.com/garethky/glowforge-colorific-fusion360-post) project.

## Goal

Update the GlowForge post so the auto-generated colours work properly for K40 Whisperer. Instead of cycling through a list of colours this post
uses red (#FF0000) for all cut operations and black (#000000) for all engrave operations. Other than that it is identical to the
Glowforge colorific post processor.

# License

Copyright (C) 2018 by Autodesk, Inc.
All rights reserved.

This work is based on an original work by Autodesk, Inc. Ths work is provided *Gratis* but *not Libre*, see: https://en.wikipedia.org/wiki/Gratis_versus_libre
This was developed for my own personal use and posted so that others (including Autodesk, Inc.) might benefit from this effort.
