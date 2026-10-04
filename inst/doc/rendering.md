# Rendering

`to_svg(q)` returns one UTF-8 string. `to_png(q)` returns a raw vector containing an RGBA PNG. `to_pixels(q)` returns a `specqr_pixels` list with width, height and row-major interleaved RGBA `$pixels`. `render_rgba(q)` exposes the same bytes as `$data`. Inputs may be a QR result or a square logical matrix; missing values and dimensions greater than177 are rejected.

Colors: hexadecimal RGB/RGBA `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, plus black, white and transparent are available for every output. Simple ASCII CSS names may be used in SVG; unknown raster colors fail instead of silently substituting a color. The R helper `parse_color(color, strict=FALSE)` returns `NULL` for an unrecognized safe CSS name; use `strict=TRUE` to raise a color error. This R default differs from the Julia helper. XML output contains escaped attributes and no arbitrary markup. A four-module quiet zone is the default. Colors, alpha, small margins and low contrast can affect scanning; diagnostic warnings are advisory.

PNG uses a from-scratch PNG writer, stored DEFLATE blocks, unsigned-safe CRC32 and Adler32. It does not call a graphics device, libpng, zlib, an R image package or an external process. Files are deliberately uncompressed and larger than optimized PNG output. The package returns bytes; writing the bytes is an explicit caller operation.

`to_svg_data_url` uses percent-encoded UTF-8. `to_png_data_url` uses base64. `to_data_url(q,format="svg")` and `render` select an output. `render_dimensions(q,dpi=300)` reports finite pixel and print dimensions. DPI must be positive and finite. Overflow/underflow in physical dimensions is rejected.

The raster budget is4,194,304 pixels; SVG and data URL budgets are8,388,608 and33,554,432 characters. Geometry integers are bounded, and budgets are checked before allocating the raster. Typical v40 with default margin4 and scale8 is1480 square, within the limit. Use smaller scale for many large symbols.
