# v16 fixes

- Editor selection handles: resize/rotation handles now win hit-testing over the inline NSTextView, are fully drawn inside element bounds, and have larger hit targets.
- Watermark: live preview is now directly draggable/resizable on the PDF page. Position is stored as normalized page coordinates and the same position/size is used for final processing. The old fixed-position picker was removed.
- Watermark text clipping: annotation bounds are calculated from real font metrics instead of character-count estimates, avoiding clipped final uppercase glyphs.
- Compression: creates optimized/lossy candidates and keeps the smallest valid result, using the original PDF as fallback. Compression therefore never intentionally returns a larger file than the source.
