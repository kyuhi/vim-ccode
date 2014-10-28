local function removed_macro( header_text )
    header_text = header_text:gsub( "/%*.-%*/", "" )
    header_text = header_text:gsub( "#%s*define.-[^\\]\n", "" )
    header_text = header_text:gsub( "#include.-\n", "" )
    header_text = header_text:gsub( "#%s*ifdef%s+__cplusplus.-#%s*endif", "" )
    header_text = header_text:gsub( "#%s*ifndef%s+__has_feature.-#%s*endif", "" )
    header_text = header_text:gsub( "#%s*ifdef%s+__has_feature.-#%s*endif", "" )
    header_text = header_text:gsub( "#.-\n", "" )
    header_text = header_text:gsub( "CINDEX_LINKAGE", "" )
    header_text = header_text:gsub( "CINDEX_DEPRECATED", "" )
    return header_text
end

local function map_reduce_headers( headers )
    local reduced = ''
    for i, header in ipairs( headers ) do
        local file = assert(io.open( header ))
        local text = file:read('*a')
        file:close()
        reduced = reduced .. removed_macro( text )
    end
    return reduced
end

local function load_clang_ffi( clang_directory )
    local ffi = require('ffi')
    local index_h = clang_directory .. "/include/clang-c/Index.h"
    local cx_string_h = clang_directory .. "/include/clang-c/CXString.h"
    local include_files = { cx_string_h, index_h }

    local decltext = [[
        typedef uint64_t time_t;
    ]]
    decltext = decltext .. map_reduce_headers( include_files )
    ffi.cdef( decltext )
    return ffi
end

return {
    load_clang_ffi = load_clang_ffi
}
