# Glyph outline extraction from FreeType fonts

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

# --- FT_Outline_Decompose callback-based extraction ---
# Pattern follows FreeType.jl test: test/runtests.jl:9-52

function extract_raw_paths(face::FreeTypeAbstraction.FTFont, char::Char)
    gi = FreeTypeAbstraction.glyph_index(face, char)

    paths = Any[]

    function _pos(p::Ptr{FreeType.FT_Vector})
        v = unsafe_load(p)
        (Float32(v.x), Float32(v.y))
    end

    move_to(to, user)          = (push!(paths, (:move, _pos(to)));                       Cint(0))
    line_to(to, user)          = (push!(paths, (:line, _pos(to)));                       Cint(0))
    conic_to(ctrl, to, user)   = (push!(paths, (:conic, _pos(ctrl), _pos(to)));          Cint(0))
    cubic_to(c1, c2, to, user) = (push!(paths, (:cubic, _pos(c1), _pos(c2), _pos(to))); Cint(0))

    move_f  = @cfunction($move_to,  Cint, (Ptr{FreeType.FT_Vector}, Ptr{Cvoid}))
    line_f  = @cfunction($line_to,  Cint, (Ptr{FreeType.FT_Vector}, Ptr{Cvoid}))
    conic_f = @cfunction($conic_to, Cint, (Ptr{FreeType.FT_Vector}, Ptr{FreeType.FT_Vector}, Ptr{Cvoid}))
    cubic_f = @cfunction($cubic_to, Cint, (Ptr{FreeType.FT_Vector}, Ptr{FreeType.FT_Vector}, Ptr{FreeType.FT_Vector}, Ptr{Cvoid}))

    @lock getfield(face, :lock) begin
        err = FreeType.FT_Load_Glyph(face, UInt32(gi), FreeType.FT_LOAD_NO_SCALE | FreeType.FT_LOAD_NO_BITMAP)
        err != 0 && error("Could not load glyph for '$char': FreeType error $err")

        GC.@preserve move_f line_f conic_f cubic_f begin
            facerec  = unsafe_load(getfield(face, :ft_ptr))
            glyphrec = unsafe_load(facerec.glyph)
            outline  = glyphrec.outline

            outline_funcs = FreeType.FT_Outline_Funcs(
                Base.unsafe_convert.(Ptr{Cvoid}, (move_f, line_f, conic_f, cubic_f))...,
                Cint(0), FT_Pos(0),
            )

            FreeType.FT_Outline_Decompose(
                pointer_from_objref.((Ref(outline), Ref(outline_funcs)))...,
                C_NULL,
            )
        end
    end

    return paths
end

# --- Convert raw path commands to polygon contours ---

function paths_to_contours(paths::Vector)
    contours = Vector{Vector{GeometryBasics.Point2f}}()
    current = GeometryBasics.Point2f[]

    for cmd in paths
        tag = cmd[1]
        if tag === :move
            !isempty(current) && push!(contours, current)
            current = [GeometryBasics.Point2f(cmd[2]...)]
        elseif tag === :line
            push!(current, GeometryBasics.Point2f(cmd[2]...))
        elseif tag === :conic
            p0 = current[end]
            subdivide_conic!(current, p0, GeometryBasics.Point2f(cmd[2]...), GeometryBasics.Point2f(cmd[3]...))
        elseif tag === :cubic
            p0 = current[end]
            subdivide_cubic!(current, p0, GeometryBasics.Point2f(cmd[2]...), GeometryBasics.Point2f(cmd[3]...), GeometryBasics.Point2f(cmd[4]...))
        end
    end
    !isempty(current) && push!(contours, current)

    return contours
end

# --- Build a normalized GlyphOutline from a font face and character ---

function build_glyph(face::FreeTypeAbstraction.FTFont, char::Char)
    paths = extract_raw_paths(face, char)
    contours = paths_to_contours(paths)
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
        c[i] = GeometryBasics.Point2f((c[i][1] - xmin) / w, (c[i][2] - ymin) / h)
    end

    # Classify: positive signed area → exterior (CCW), negative → hole (CW)
    exteriors = Vector{GeometryBasics.Point2f}[]
    holes     = Vector{GeometryBasics.Point2f}[]
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
    ext = [GeometryBasics.Point2f(xf + p[1]*wf, yf + p[2]*hf) for p = glyph.exterior]
    if isempty(glyph.interiors)
        return GeometryBasics.Polygon(ext)
    else
        ints = [[GeometryBasics.Point2f(xf + p[1]*wf, yf + p[2]*hf) for p = hole] for hole = glyph.interiors]
        return GeometryBasics.Polygon(ext, ints)
    end
end
