# Look row 10 padded final QA

- selected_source: `generated/look-row-10-left-padded-final.png`
- result: accepted for deterministic slicing
- layout: exactly 8 isolated full-body poses, each visually centered in its equal cell
- scale: all poses reduced approximately 12% from the prior semantic-pass source
- padding: generous uniform yellow clearance around hair, clip, hands, sleeves, legs, and slippers; no visible pose approaches the outer canvas or internal cell boundaries
- slot 1 / 180: down-front pose is centered with clear left and right margins; no accessory or body part near either cell edge
- orientation: slot 1 down-front; slots 2-8 retain the correct physical-left-facing progression
- pose progression: down-front, slight down-left, down-left, strong down-left, pure left, left-up, stronger left-up, near-up while still left-facing
- character invariants: exposed short lavender-gray bob, single penguin hair clip, pale blue pajama outfit, penguin slippers, no hat, no sleeping cap, no head covering
