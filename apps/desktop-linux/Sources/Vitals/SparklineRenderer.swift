import CCairo
import Foundation

/// Renders compact line/area charts to PNG bytes with Cairo.
///
/// Adwaita's `Picture` shows raster data only — it decodes through
/// `gdk_texture_new_from_bytes`, which rejects SVG — so the dashboard's
/// sparklines and history charts are drawn here and handed over as PNG `Data`.
/// Cairo is already pulled in by GTK, so this adds no runtime weight.
///
/// Honest by construction: fewer than two points yields empty `Data`, and the
/// view then shows nothing rather than a fabricated flat line.
enum SparklineRenderer {

    struct Color {
        let r, g, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    }

    /// Collects the PNG stream cairo emits. A reference box so the
    /// `@convention(c)` write callback can reach it through a raw pointer.
    private final class ByteSink { var data = Data() }

    static func render(
        values: [Double],
        width: Int,
        height: Int,
        line: Color,
        fill: Bool = true
    ) -> Data {
        guard values.count > 1, width > 0, height > 0 else { return Data() }

        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height))
        defer { cairo_surface_destroy(surface) }
        guard cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else { return Data() }
        let cr = cairo_create(surface)
        defer { cairo_destroy(cr) }

        let w = Double(width)
        let h = Double(height)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = hi - lo
        let inset = h * 0.12

        func px(_ i: Int) -> Double { w * Double(i) / Double(values.count - 1) }
        func py(_ v: Double) -> Double {
            let t = span > 0 ? (v - lo) / span : 0.5
            return h - inset - t * (h - inset * 2)
        }
        func trace() {
            cairo_move_to(cr, px(0), py(values[0]))
            for i in 1..<values.count { cairo_line_to(cr, px(i), py(values[i])) }
        }

        if fill {
            trace()
            cairo_line_to(cr, w, h)
            cairo_line_to(cr, 0, h)
            cairo_close_path(cr)
            cairo_set_source_rgba(cr, line.r, line.g, line.b, 0.18)
            cairo_fill(cr)
        }

        trace()
        cairo_set_line_width(cr, 2)
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
        cairo_set_source_rgba(cr, line.r, line.g, line.b, 1)
        cairo_stroke(cr)

        let sink = ByteSink()
        let status = cairo_surface_write_to_png_stream(
            surface,
            { closure, bytes, length in
                guard let closure, let bytes else { return CAIRO_STATUS_SUCCESS }
                let sink = Unmanaged<ByteSink>.fromOpaque(closure).takeUnretainedValue()
                sink.data.append(bytes, count: Int(length))
                return CAIRO_STATUS_SUCCESS
            },
            Unmanaged.passUnretained(sink).toOpaque()
        )
        return status == CAIRO_STATUS_SUCCESS ? sink.data : Data()
    }
}
