Create one horizontal animation strip for Codex pet `tomori`, state `review`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 6 full-body frames in one left-to-right row on flat pure yellow #FFFF00. Treat the row as 6 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: 忠实再现高松灯：紫灰色齐耳短发、厚重不规则刘海、粉棕眼、安静略不安神情。官方 PAJAMA PARTY 服装：浅蓝露肩荷叶边上衣、白色双层荷叶边短裤、蓝白袜圈、小鸟拖鞋。头部只有夹在头发左上方的小型蓝色企鹅与蝴蝶结发卡；绝对没有睡帽、头巾、兜帽、帽子或覆盖头发的布料。完整露出头顶、短发后脑和短发轮廓。左右拖动最终共用同一套右拖悬空动画。. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `sticker`: Polished sticker mascot with bold clean shapes, crisp outline, flat colors, and minimal highlight detail. User style notes: 精致日系动画Q版贴纸精灵，忠实官方短发与企鹅发卡，清晰平涂赛璐璐阴影。.
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Ready-review loop: focused inspection of completed output with lean, blink, narrowed eyes, head tilt, or paw pose.

State requirements:
- Show review through lean, blink, narrowed eyes, head tilt, or paw/hand position.
- Do not add magnifying glasses, papers, code, UI, punctuation, symbols, or other new props unless they already exist in the base pet identity.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
