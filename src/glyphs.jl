# Glyph outline extraction from FreeType fonts
#
# Instead of the fragile FT_Outline_Decompose callback approach (which requires
# @cfunction + careful Ref/GC management), we directly read the FT_Outline
# struct arrays (points, tags, contours) and interpret them ourselves.
# This is fully portable (works on Apple Silicon, x86, …) and avoids segfaults
# from premature GC of Ref objects or stale @cfunction pointers.

struct GlyphOutline
    exterior::Vector{Point2f}
    interiors::Vector{Vector{Point2f}}
end

const GLYPH_CACHE = Dict{Tuple{String, Char}, GlyphOutline}()

# --- Bezier curve approximation ---

function subdivide_conic!(result::Vector{Point2f}, p0::Point2f, p1::Point2f, p2::Point2f; n::Int=10)
    for i in 1:n
        t = Float32(i / n)
        s = 1.0f0 - t
        push!(result, Point2f(
            s*s*p0[1] + 2*s*t*p1[1] + t*t*p2[1],
            s*s*p0[2] + 2*s*t*p1[2] + t*t*p2[2],
        ))
    end
end

function subdivide_cubic!(result::Vector{Point2f}, p0::Point2f, p1::Point2f, p2::Point2f, p3::Point2f; n::Int=12)
    for i in 1:n
        t = Float32(i / n)
        s = 1.0f0 - t
        push!(result, Point2f(
            s^3*p0[1] + 3*s^2*t*p1[1] + 3*s*t^2*p2[1] + t^3*p3[1],
            s^3*p0[2] + 3*s^2*t*p1[2] + 3*s*t^2*p2[2] + t^3*p3[2],
        ))
    end
end

# --- Signed area for winding direction ---

function signed_area(contour::Vector{Point2f})
    n = length(contour)
    n < 3 && return 0.0f0
    area = 0.0f0
    for i in 1:n
        j = mod1(i + 1, n)
        area += contour[i][1] * contour[j][2] - contour[j][1] * contour[i][2]
    end
    return area / 2.0f0
end

# --- Direct outline reading (no FT_Outline_Decompose / no callbacks) ---
#
# We read the raw FT_Outline arrays (points, tags, contours) and interpret
# them according to FreeType conventions:
#   • FT_CURVE_TAG_ON    (0x01) — on-curve point
#   • FT_CURVE_TAG_CONIC (0x00) — conic (quadratic) Bézier control point
#   • FT_CURVE_TAG_CUBIC (0x02) — cubic Bézier control point
# Two consecutive conic off-curve points have an implicit on-curve midpoint.

const _TAG_ON    = UInt8(0x01)
const _TAG_CONIC = UInt8(0x00)
const _TAG_CUBIC = UInt8(0x02)

"""
    _load_outline_data(face, char) -> (points, tags, contour_ends)

Load a glyph and copy its outline data out of FreeType while the face lock
is held.  Returns Julia-owned arrays so no dangling pointers remain.
"""
function _load_outline_data(face::FreeTypeAbstraction.FTFont, char::Char)
    gi = FreeTypeAbstraction.glyph_index(face, char)

    @lock getfield(face, :lock) begin
        err = FT_Load_Glyph(face, UInt32(gi), FT_LOAD_NO_SCALE | FT_LOAD_NO_BITMAP)
        err != 0 && error("Could not load glyph for '$char': FreeType error $err")

        facerec  = unsafe_load(getfield(face, :ft_ptr))
        glyphrec = unsafe_load(facerec.glyph)
        outline  = glyphrec.outline

        nc = Int(outline.n_contours)
        np = Int(outline.n_points)

        if nc == 0 || np == 0
            return Point2f[], UInt8[], Int[]
        end

        # Copy everything into Julia arrays before releasing the lock
        raw_pts  = [unsafe_load(outline.points, i) for i in 1:np]
        raw_tags = [unsafe_load(Ptr{UInt8}(outline.tags), i) for i in 1:np]
        raw_ends = [Int(unsafe_load(outline.contours, i)) for i in 1:nc]

        points = [Point2f(Float32(v.x), Float32(v.y)) for v in raw_pts]
        tags   = [t & 0x03 for t in raw_tags]   # keep only curve-tag bits

        return points, tags, raw_ends            # raw_ends are 0-indexed
    end
end

"""
    _interpret_contour(pts, tags) -> Vector{Point2f}

Walk one closed contour and convert it to a dense polyline, approximating
any quadratic / cubic Bézier arcs with short line segments.
"""
function _interpret_contour(pts::AbstractVector{Point2f}, tags::AbstractVector{UInt8})
    n = length(pts)
    n < 2 && return Point2f[]

    result = Point2f[]
    # Circular index helper (1-based)
    ci(i) = mod1(i, n)

    # --- find a starting on-curve point ---
    first_on = findfirst(==(UInt8(_TAG_ON)), tags)

    if first_on !== nothing
        push!(result, pts[first_on])
    else
        # Entire contour is conic off-curve ⇒ start at implicit midpoint
        push!(result, (pts[n] + pts[1]) / 2)
        first_on = 1                       # start processing from index 1
    end

    # --- walk around the contour ---
    i = first_on + 1
    steps = 0                              # safety guard (≤ 2n is generous)
    while steps < 2n
        idx = ci(i)
        # If we've come back to the start, we're done
        if idx == first_on && steps > 0
            break
        end

        t = tags[idx]

        if t == _TAG_ON
            push!(result, pts[idx])
            i += 1

        elseif t == _TAG_CONIC
            ctrl = pts[idx]
            next_idx = ci(i + 1)
            next_tag = tags[next_idx]

            if next_tag == _TAG_ON
                # conic arc with explicit endpoint
                subdivide_conic!(result, result[end], ctrl, pts[next_idx])
                i += 2
            else
                # two consecutive conics → implicit on-curve at midpoint
                implicit = (ctrl + pts[next_idx]) / 2
                subdivide_conic!(result, result[end], ctrl, implicit)
                i += 1                     # next conic will be handled next iteration
            end

        elseif t == _TAG_CUBIC
            c1 = pts[idx]
            c2 = pts[ci(i + 1)]
            ep = pts[ci(i + 2)]
            subdivide_cubic!(result, result[end], c1, c2, ep)
            i += 3

        else
            i += 1                         # skip unknown tags
        end

        steps += 1
    end

    # Close: if last segment was a conic whose target is the start point,
    # it's already included; but if the contour ends with off-curve points
    # that wrap around, connect back to the start.
    if !isempty(result) && result[end] != result[1]
        last_tag = tags[ci(first_on - 1)]  # tag of last point before start
        if last_tag == _TAG_CONIC
            ctrl = pts[ci(first_on - 1)]
            subdivide_conic!(result, result[end], ctrl, result[1])
        end
    end

    return result
end

# --- Build contour list from outline data ---

function extract_contours(face::FreeTypeAbstraction.FTFont, char::Char)
    points, tags, contour_ends = _load_outline_data(face, char)
    isempty(points) && return Vector{Vector{Point2f}}()

    contours = Vector{Vector{Point2f}}()
    start = 1                               # 1-indexed start of current contour
    for ce in contour_ends
        last = ce + 1                       # convert 0-indexed end → 1-indexed
        n = last - start + 1
        if n >= 2
            poly = _interpret_contour(
                @view(points[start:last]),
                @view(tags[start:last]),
            )
            !isempty(poly) && push!(contours, poly)
        end
        start = last + 1
    end
    return contours
end

# --- Build a normalized GlyphOutline from a font face and character ---

function build_glyph(face::FreeTypeAbstraction.FTFont, char::Char)
    contours = extract_contours(face, char)
    isempty(contours) && error("No contours found for character '$char'")

    # Global bounding box across all contours
    all_pts = reduce(vcat, contours)
    xs = [p[1] for p in all_pts]
    ys = [p[2] for p in all_pts]
    xmin, xmax = extrema(xs)
    ymin, ymax = extrema(ys)
    w = xmax - xmin; w == 0 && (w = 1.0f0)
    h = ymax - ymin; h == 0 && (h = 1.0f0)

    # Normalize every contour to [0,1] x [0,1]
    for c in contours, i in eachindex(c)
        c[i] = Point2f((c[i][1] - xmin) / w, (c[i][2] - ymin) / h)
    end

    # Classify: positive signed area → exterior (CCW), negative → hole (CW)
    exteriors = Vector{Point2f}[]
    holes     = Vector{Point2f}[]
    for c in contours
        if signed_area(c) > 0
            push!(exteriors, c)
        else
            push!(holes, c)
        end
    end

    if isempty(exteriors) && !isempty(holes)
        # All contours have the same winding — pick largest as exterior, reverse it
        areas = [abs(signed_area(c)) for c in contours]
        idx = argmax(areas)
        exterior = reverse(contours[idx])
        interior = [contours[i] for i in eachindex(contours) if i != idx]
        return GlyphOutline(exterior, interior)
    elseif length(exteriors) == 1
        return GlyphOutline(exteriors[1], holes)
    else
        # Multiple exteriors: use largest, treat remaining as additional shapes
        areas = [abs(signed_area(e)) for e in exteriors]
        idx = argmax(areas)
        return GlyphOutline(exteriors[idx], holes)
    end
end

# --- Public API ---

function get_glyph(char::Char; font_name::String="dejavu sans bold")
    key = (font_name, char)
    return get!(GLYPH_CACHE, key) do
        face = FreeTypeAbstraction.findfont(font_name)
        face === nothing && error("Font '$font_name' not found")
        build_glyph(face, char)
    end
end

clear_glyph_cache!() = empty!(GLYPH_CACHE)

function glyph_to_polygon(glyph::GlyphOutline, x::Real, y::Real, width::Real, height::Real)
    xf, yf, wf, hf = Float32(x), Float32(y), Float32(width), Float32(height)
    ext = [Point2f(xf + p[1]*wf, yf + p[2]*hf) for p in glyph.exterior]
    if isempty(glyph.interiors)
        return Polygon(ext)
    else
        ints = [[Point2f(xf + p[1]*wf, yf + p[2]*hf) for p in hole] for hole in glyph.interiors]
        return Polygon(ext, ints)
    end
end
