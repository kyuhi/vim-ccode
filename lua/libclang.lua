#!/usr/bin/env luajit
local clang_root = os.getenv( 'VIM_CCODE_CLANG_ROOT_DIRECTORY_FOR_LUAJIT' )
if clang_root:sub( -1 ) == '/' then
    clang_root = clang_root:sub(1, -2)
end
local clang_ffi_loader = require( 'clang_ffi_load' )
local ffi = clang_ffi_loader.load_clang_ffi( clang_root )
local clang_library_path = ''
if jit.os == 'OSX' then
    clang_library_path = clang_root .. '/lib/libclang.dylib'
else
    clang_library_path = clang_root .. '/lib/libclang.so'
end
local C = ffi.load( clang_library_path )
local bit = require( "bit" )

-- helper functions for clang -------------------------------------------------


local function isCxCursorInValid( cx_cursor )
    -- compare int to lua number
    if not ( C.clang_Cursor_isNull( cx_cursor ) == 0 ) then
        return true
    elseif not( C.clang_isInvalid( C.clang_getCursorKind( cx_cursor ) ) == 0 ) then
        return true
    end
    return false
end

local CompletionDataKindsChars = {
    -- c
    [ tonumber( C.CXCursor_StructDecl ) ] = 's',
    [ tonumber( C.CXCursor_EnumDecl ) ] = 'e',
    [ tonumber( C.CXCursor_EnumConstantDecl ) ] = 'e',
    [ tonumber( C.CXCursor_UnexposedDecl ) ] = 't',
    [ tonumber( C.CXCursor_UnionDecl ) ] = 't',
    [ tonumber( C.CXCursor_TypedefDecl ) ] = 't',
    [ tonumber( C.CXCursor_FieldDecl ) ] = 'm',
    [ tonumber( C.CXCursor_FunctionDecl ) ] = 'f',
    [ tonumber( C.CXCursor_VarDecl ) ] = 'v',
    [ tonumber( C.CXCursor_MacroDefinition ) ] = 'p',
    [ tonumber( C.CXCursor_ParmDecl ) ] = 'p',
    -- c++
    [ tonumber( C.CXCursor_Namespace ) ] = 'n',
    [ tonumber( C.CXCursor_NamespaceAlias ) ] = 'n',
    [ tonumber( C.CXCursor_ClassDecl ) ] = 'c',
    [ tonumber( C.CXCursor_ClassTemplate ) ] = 'c',
    [ tonumber( C.CXCursor_CXXMethod ) ] = 'f',
    [ tonumber( C.CXCursor_FunctionTemplate ) ] = 'f',
    [ tonumber( C.CXCursor_ConversionFunction ) ] = 'f',
    [ tonumber( C.CXCursor_Constructor ) ] = 'f',
    [ tonumber( C.CXCursor_Destructor ) ] = 'f',
    -- objective-c
    [ tonumber( C.CXCursor_ObjCInterfaceDecl ) ] = 'c',
    [ tonumber( C.CXCursor_ObjCProtocolDecl ) ] = 'c',
    [ tonumber( C.CXCursor_ObjCClassMethodDecl ) ] = 'f',
    [ tonumber( C.CXCursor_ObjCInstanceMethodDecl ) ] = 'f',
    [ tonumber( C.CXCursor_ObjCIvarDecl ) ] = 'm',
    [ tonumber( C.CXCursor_ObjCPropertyDecl ) ] = 'f',
}

local function cursorKindToCharacter( kind )
    local k = CompletionDataKindsChars[ tonumber( kind ) ]
    if k then
        return k
    else
        return tostring( kind ) -- Unknown kind
    end
end

local DiagnoticsKindsChars = {
    [ tonumber( C.CXDiagnostic_Ignored ) ] = 'I',
    [ tonumber( C.CXDiagnostic_Note ) ] = 'I',
    [ tonumber( C.CXDiagnostic_Warning ) ] = 'W',
    [ tonumber( C.CXDiagnostic_Error ) ] = 'E',
    [ tonumber( C.CXDiagnostic_Fatal ) ] = 'E',
}

local function cxDiagnosticServerityToChar( kind )
    local k = DiagnoticsKindsChars[ tonumber( kind ) ]
    if k then
        return k
    else
        return 'E'
    end
end


-- clang to lua --------------------------------------------------------------
local function cx2String( cx_string )
    local str = ffi.string( C.clang_getCString( cx_string ) )
    C.clang_disposeString( cx_string )
    return str
end

local function cx2CompletionChunkText( completion_string, i )
    local cxstr = C.clang_getCompletionChunkText( completion_string, i )
    return cx2String( cxstr )
end


-- lua to clang ---------------------------------------------------------------
local function lua2Cstrings( flags )
    local n = #flags
    if n == 0 then
        return nil, 0
    end
    local pp = ffi.new('const char *[?]', n)
    for i, str in ipairs( flags ) do
        pp[ i - 1 ] = str
    end
    return pp, n
end

local function lua2CunsavedFiles( unsaved_files )
    local n = #unsaved_files
    if n == 0 then
        return nil, 0
    end
    local c_unsaved = ffi.new( "struct CXUnsavedFile [?]", n )
    for i, f in ipairs( unsaved_files ) do
        c_unsaved[ i - 1 ].Filename = f.filename
        c_unsaved[ i - 1 ].Contents = f.contents
        c_unsaved[ i - 1 ].Length = #f.contents
    end
    return c_unsaved, n
end


-- CompletionData -------------------------------------------------------------
local CompletionData = {}
local CompletionData_MT = { __index = CompletionData }
function CompletionData:new( cx_completion_result )

    local name, placeholder, returntype = '', '', ''
    local continue = nil

    local cx_completion_string = cx_completion_result.CompletionString
    local num_chunks = C.clang_getNumCompletionChunks( cx_completion_string )

    for i=0, (num_chunks-1) do
        local kind = C.clang_getCompletionChunkKind( cx_completion_string, i )
        local text = cx2CompletionChunkText( cx_completion_string, i )

        if kind == C.CXCompletionChunk_Informative then
            continue = nil
        elseif kind == C.CXCompletionChunk_ResultType then
            returntype = text
        else
            if kind == C.CXCompletionChunk_TypedText then
                name = name .. text
            end
            if kind == C.CXCompletionChunk_Placeholder then
                placeholder = placeholder .. '#{{' .. text .. '}}#'
            else
                placeholder = placeholder .. text
            end
        end 
    end

    return setmetatable( { name=name,
                           placeholder=placeholder,
                           returntype=returntype,
                           kind=tonumber( cx_completion_result.CursorKind ) },
                           CompletionData_MT )
end

function CompletionData:getPlaceholder( rep_start, rep_end )
    return self.placeholder:gsub( '#{{', rep_start ):gsub( '}}#', rep_end )
end

function CompletionData:getUltisnipsPlaceholder()
    local count = 1
    local result = self.placeholder
    local prev = result
    repeat
        prev = result
        local repl = '${' .. tostring( count ) .. ':'
        result = result:gsub( '#{{', repl, 1 )
        count = count + 1
    until result == prev
    return result:gsub( '}}#', '}' )
end

function CompletionData:getName()
    return self.name
end

function CompletionData:getUpperTextForCompare( size )
    local result = ''
    local text = self:getName()
    for w in text:gmatch( "[_%w]" ) do
        result = result .. w
    end
    return result
end

function CompletionData:getKind()
    return cursorKindToCharacter( self.kind )
end

function CompletionData:getReturnType()
    return self.returntype
end

function CompletionData:getSyntax()
    return self:getPlaceholder( '', '' )
end

function CompletionData:getFullSyntax()
    local noreturn = self:getSyntax()
    if #self.returntype == 0 then
        return noreturn
    else
        return self.returntype .. ' ' .. noreturn
    end
end

function CompletionData:startsWithUpper( upper, size )
    return self:getName():sub( 1, size ):upper() == upper
end

-- CodeCompletionResults ------------------------------------------------------
local CodeCompletionResults = {}
local CodeCompletionResults_MT = { __index = CodeCompletionResults }
function CodeCompletionResults:new( cx_code_completion_results )
    C.clang_sortCodeCompletionResults( cx_code_completion_results.Results,
                                       cx_code_completion_results.NumResults )
    return setmetatable( {
            cache = {},
            cx_code_completion_results = ffi.gc(
                                cx_code_completion_results,
                                C.clang_disposeCodeCompleteResults ),
            min_index = 1,
            max_index = cx_code_completion_results.NumResults,
        },
        CodeCompletionResults_MT )
end

function CodeCompletionResults:dataAt( index )
    assert( self.min_index <= index and index <= self.max_index )
    local data = self.cache[ index ]
    if data then return data end
    self.cache[ index ] = CompletionData:new(
            self.cx_code_completion_results.Results[ index - 1 ] )
    return self.cache[ index ]
end

function CodeCompletionResults:numDatas()
    return self.cx_code_completion_results.NumResults
end

function CodeCompletionResults:searchLeftIndex( query )
    local q = query:upper()
    local qlen = #query
    local low, high = self.min_index, self.max_index
    while low < high do
        local mid = math.floor( (low+high)/2 )
        local target = self:dataAt( mid ):getName():sub(1, qlen):upper()
        if target < query then
            low = mid+1
        else
            high = mid
        end
    end
    return low
end

-- Location -------------------------------------------------------------------
local Location = {}
local Location_MT = { __index = Location }
function Location:new( cx_location )
    local cxfile = ffi.new('CXFile[1]')
    local p_line = ffi.new('unsigned int [1]')
    local p_column = ffi.new('unsigned int [1]') 
    local p_unused = ffi.new('unsigned int [1]')
    C.clang_getExpansionLocation( cx_location,
                                  cxfile,
                                  p_line,
                                  p_column,
                                  p_unused )
    local cxfilename = C.clang_getFileName( cxfile[0] )
    return setmetatable( {
           line = tonumber( p_line[0] ),
           column = tonumber( p_column[0] ),
           filename = ffi.string( cx2String( cxfilename ) ),
        },
        Location_MT )
end

function Location:debugString()
    return string.format("Location [%s] %s [%d %d]",
                tostring(self), self.filename, self.line, self.column)
end

-- Diagnostic -----------------------------------------------------------------
local Diagnostic = {}
local Diagnostic_MT = { __index = Diagnostic }
function Diagnostic:new( cx_diagnostic )
    local cx_location = C.clang_getDiagnosticLocation( cx_diagnostic )
    local kind = cxDiagnosticServerityToChar(
                    C.clang_getDiagnosticSeverity( cx_diagnostic ) )
    local text = cx2String( C.clang_getDiagnosticSpelling( cx_diagnostic ) )


    return setmetatable( {
                kind = kind,
                text = text,
                location = Location:new( cx_location ),
            },
            Diagnostic_MT )
end

function Diagnostic:debugString()
    return string.format("Diagnostic [%s] kind:%s text:%s location:%s",
            tostring(self), self.kind, self.text, self.location:debugString() )
end

-- Index ----------------------------------------------------------------------
local Index = {}
local Index_MT = { __index = Index }
function Index:new()
    index = ffi.gc( C.clang_createIndex( 0,0 ), C.clang_disposeIndex )
    C.clang_toggleCrashRecovery( ffi.cast('unsigned', 1) )
    return setmetatable( { index=index }, Index_MT )
end


-- TranslationUnit ------------------------------------------------------------
local TranslationUnit = {}
local TranslationUnit_MT = { __index = TranslationUnit }

function TranslationUnit:new( index, filename, unsaved_files, flags )
    local cflags, nflags = lua2Cstrings( flags )
    local cxunsaved, n_cxunsaved = lua2CunsavedFiles( unsaved_files )
    local options = TranslationUnit.editingOptions()
    local tu = C.clang_parseTranslationUnit( index,
                                             filename,
                                             cflags,
                                             nflags,
                                             cxunsaved,
                                             n_cxunsaved,
                                             options )
    if not tu then return nil end
    local bad = C.clang_reparseTranslationUnit( tu,
                                                n_cxunsaved,
                                                cxunsaved,
                                                options )
    if bad == 1 then
        C.clang_disposeTranslationUnit( tu )
        return nil
    end
    return setmetatable( { tu=tu, filename=filename }, TranslationUnit_MT )
end

function TranslationUnit:codeCompletionAt( filename, line, column, unsaved_files )
    local ufiles, nu = lua2CunsavedFiles( unsaved_files )
    local cx_completions = C.clang_codeCompleteAt(
                                        self.tu,
                                        filename,
                                        line,
                                        column,
                                        ufiles,
                                        nu,
                                        TranslationUnit.codeCompleteOptions() )
    return CodeCompletionResults:new( cx_completions )
end

function TranslationUnit:update( unsaved_files )
    self:updateWithOptions( unsaved_files, TranslationUnit.editingOptions() )
end

function TranslationUnit:updateWithOptions( unsaved_files, options )
    local ufiles, nu = lua2CunsavedFiles( unsaved_files )
    local bad = C.clang_reparseTranslationUnit(
                                        self.tu,
                                        nu,
                                        ufiles,
                                        options )
    if bad then
        -- TODO: error check
    end
end

function TranslationUnit:locationToDefinition( line, column, unsaved_files )
    self:updateWithOptions( unsaved_files, TranslationUnit.indexingOptions() )
    local cx_cursor = self:getLocationOfCXCursor( line, column )
    if isCxCursorInValid( cx_cursor ) then
        return nil
    end
    local cx_definition_cursor = C.clang_getCursorDefinition( cx_cursor )
    if isCxCursorInValid( cx_definition_cursor ) then
        return nil
    end
    return Location:new( C.clang_getCursorLocation( cx_definition_cursor ) )
end

function TranslationUnit:locationToDeclaration( line, column, unsaved_files )
    self:updateWithOptions( unsaved_files, TranslationUnit.indexingOptions() )
    local cx_cursor = self:getLocationOfCXCursor( line, column )
    if isCxCursorInValid( cx_cursor ) then
        return nil
    end
    local cx_declaration_cursor = C.clang_getCursorReferenced( cx_cursor )
    if isCxCursorInValid( cx_declaration_cursor ) then
        return nil
    end
    return Location:new( C.clang_getCursorLocation( cx_declaration_cursor ) )
end


function TranslationUnit:getLocationOfCXCursor( line, column )
    local cxfile = C.clang_getFile( self.tu, self.filename )
    local cx_location = C.clang_getLocation( self.tu,
                                             cxfile,
                                             line,
                                             column )
    return C.clang_getCursor( self.tu, cx_location )
end


function TranslationUnit:getDiagnostics()
    local num = C.clang_getNumDiagnostics( self.tu )
    local diagnostics = {}
    for i=0, (num-1) do
        local cx_diagnostic = ffi.gc( C.clang_getDiagnostic( self.tu, i ),
                                      C.clang_disposeDiagnostic )
        diagnostics[ i + 1 ] = Diagnostic:new( cx_diagnostic )
    end
    return diagnostics
end

function TranslationUnit:dispose()
    if self.tu then
        C.clang_disposeTranslationUnit( self.tu )
        self.tu = nil
    end
end

function TranslationUnit.codeCompleteOptions()
    return C.clang_defaultCodeCompleteOptions()
end

function TranslationUnit.editingOptions()
    return ffi.cast( 'unsigned',
                     bit.bor( C.CXTranslationUnit_DetailedPreprocessingRecord,
                              C.clang_defaultEditingTranslationUnitOptions() ) )
end

function TranslationUnit.indexingOptions()
    return ffi.cast( 'unsigned',
                     bit.bor( C.CXTranslationUnit_PrecompiledPreamble,
                              C.CXTranslationUnit_SkipFunctionBodies ) )
end

function TranslationUnit:__gc()
    self:dispose()
end

-- Module ---------------------------------------------------------------------
return {
    Index = Index,
    TranslationUnit = TranslationUnit,
    CompletionData = CompletionData,
    CodeCompletionResults = CodeCompletionResults,
}
