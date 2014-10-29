-- ** vim-helper **
local vimhelper = {}
function vimhelper.bufferData( b )
    if not b or #b == 0 then
        return ''
    end
    local blist = {}
    for i=1, (#b) do
        blist[ i ] = b[i]
    end
    return table.concat( blist, '\n' )
end

function vimhelper.fileType()
    return vim.eval( '&filetype' )
end

function vimhelper.currentDir()
    return vim.eval( 'expand("%:p:h")' )
end

function vimhelper.toLuaList( vim_list )
    local list = {}
    for i=0,(#vim_list-1) do
        list[ i+1 ] = vim_list[ i ]
    end
    return list
end

function vimhelper.toVimList( lua_list )
    local list = vim.list()
    for __, item in ipairs( lua_list ) do
        list:add( item )
    end
    return list
end

function vimhelper.eval( vim_string )
    return vim.eval( vim_string )
end

function vimhelper.setDiagnosticToQuickfix( qf, diag )
    local loc = diag.location
    qf.bufnr = vim.eval( string.format('bufnr("%s")', loc.filename) )
    qf.lnum = loc.line
    qf.col = loc.column
    qf.text = diag.text
    qf.type = diag.kind
    qf.valid = 1
    return qf
end

function vimhelper.setCompletionDataToDict( d, data )
    d.abbr = data:getSyntax()
    d.word = data:getName()
    -- d.word = data:getPlaceholder('$\\\\', '\\\\')
    d.menu = data:getReturnType()
    d.kind = data:getKind()
    d.info = data:getFullSyntax()
    d.icase = '1'
    return d
end

function vimhelper.setLocationToDict( d, location )
    if location then
        d.lnum = location.line
        d.col = location.column
        d.filename = location.filename
    end
    return d
end

function vimhelper.prettyString( object )
    local retstring = ''
    if type( object ) == 'table' then
        local items_string = ''
        for key, val in pairs( object ) do
            items_string = string.format(  '%s%s->%s, ',
                                            items_string,
                                            vimhelper.prettyString(key),
                                            vimhelper.prettyString(val) )
        end
        retstring = '{' .. items_string .. '}'
    elseif type( object ) == 'string' then
        retstring = '"' .. object .. '"'
    else
        retstring = tostring( object )
    end
    return retstring
end

-- ** FlagsStore **
FlagsStore = {}
FlagsStore_MT = { __index = FlagsStore }
function FlagsStore:new()
    return setmetatable( { flags_cache={} }, FlagsStore_MT )
end

function FlagsStore:defaultCompilerFlags()
    local current_dir = vimhelper.currentDir()
    local ft = vimhelper.fileType()

    local ft_flags_table = {
        c = {
            '-x', 'c',
            '-I/usr/include', '-I' .. current_dir,
        },
        cpp = {
            '-x', 'c++',
            '-I/usr/include', '-I' .. current_dir,
        },
        objc = {
            '-x', 'objective-c',
            '-I/usr/include', '-I' .. current_dir,
        },
        objcpp = {
            '-x', 'objective-c++',
            '-I/usr/include', '-I' .. current_dir,
        }
    }
    local flags = ft_flags_table[ ft ]
    if flags then
        return flags
    else
        return ft_flags_table[ 'c' ]
    end
end

function FlagsStore:isEqualFlags( a, b )
    if #a ~= #b then return false end
    for i=1,#a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

function FlagsStore:userVimCompletionFuncname()
    return vimhelper.eval( 'g:ccode#completion_flags_function' )
end

function FlagsStore:flags( filename )
    local flags = self.flags_cache[ filename ]
    if flags then
        return flags
    elseif self:userVimCompletionFuncname() == '' then
        -- default compliler flags
        flags = self:defaultCompilerFlags()
        self.flags_cache[ filename ] = flags
        return flags
    else -- user defined flags
        local funcname = self:userVimCompletionFuncname()
        flags = {}
        if funcname ~= '' then
            flags = vimhelper.toLuaList( vimhelper.eval( funcname .. '()' ) )
        end
        self.flags_cache[ filename ] = flags
    end
    return flags
end


-- ** UserDataStore **
local UserDataStore = {}
local UserDataStore_MT = { __index = UserDataStore }
function UserDataStore:new()
    return setmetatable( {
        flags_store = FlagsStore:new()
    }, UserDataStore_MT )
end

function UserDataStore:makeUserData()
    --[[
    user_data {
        ["filename"] => current filename,
        ["line"] => current line,
        ["column"] => current column,
        ["unsaved_files"] => {
                { ["filename"] => filename,  ["contents"] => contents of file },
                ...
        },
        ["flags"] => compiler flags for the file,
    }
    --]]
    local user_data = {}
    user_data.filename = vim.eval( 'expand("%:p")' )
    user_data.line = vim.eval( 'line(".")' )
    user_data.column = vim.eval( 'col(".")' )
    local filecontents = vimhelper.bufferData( vim.buffer() )
    user_data.unsaved_files = { -- TODO: improve
        { filename = user_data.filename, contents=filecontents }
    }
    user_data.flags = self.flags_store:flags( user_data.filename )
    return user_data
end

function UserDataStore:isAvailable( filename )
    local flags = self.flags_store:flags( filename )
    return #flags > 0
end

function UserDataStore:flagsForFile( filename )
    return self.flags_store:flags( filename )
end


local _M = {
    user_data = UserDataStore:new(),
    prettyString = vimhelper.prettyString,
    setDiagnosticToQuickfix = vimhelper.setDiagnosticToQuickfix,
    setCompletionDataToDict = vimhelper.setCompletionDataToDict,
    setLocationToDict = vimhelper.setLocationToDict,
}

return _M
