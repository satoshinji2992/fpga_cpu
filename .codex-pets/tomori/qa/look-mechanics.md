# Tomori look mechanics

Tomori keeps both feet and her lower torso anchored while her eyes lead each gaze. Her eyelids and brows reshape subtly, followed by a restrained head-and-neck turn and a very small upper-body follow-through. Her long hair stays attached and trails the head turn smoothly; the centered ribbon and uniform remain stable.

Motion budget: every 22.5-degree step changes eye position, eyelids, head turn, and hair overlap by a similar small amount. Preserve facial proportions, head size, body scale, and baseline. Do not rotate or warp the whole sprite.

- 000 up: pupils and face lift; chin rises slightly; more lower face is visible; hair remains balanced.
- 090 screen-right: pupils and nose point to the image's right; the face turns right, revealing more of the left cheek while right-side hair overlaps slightly.
- 180 down: pupils and face lower; chin tucks; upper eyelids lower slightly; bangs cover a little more forehead.
- 270 screen-left: pupils and nose point to the image's left; the face turns left, revealing more of the right cheek while left-side hair overlaps slightly.

Diagonals interpolate those pose families continuously. Hair follows with subtle lag, never flips sides or detaches. No props or effects are introduced.
