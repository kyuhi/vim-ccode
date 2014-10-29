local libclang = require "libclang"

-- ** Completer **
--[[
completer's functions take argument is called user_data.
structure of user_data is ...
{
    "filename" (string) : 'current filename`,
    "line" (number) : `current line`,
    "column" (number): `current column`,
    "unsaved_files" (list of dict) : [
            {
              "filename" (string) : `filename`,
              "contents" (string): `contents of the file`,
            },
            ...
    ],
    "flags" (list of string) : `compiler flags for the current file`,
}
--]]
local ClangCompleter = {}
local ClangCompleter_MT = { __index = ClangCompleter }

function ClangCompleter:new()
    return setmetatable( {
            index=libclang.Index:new(),
            tu_filename_table={},  -- stores transtation unit using filename
            completions_cache=nil, -- code_completion_results
            },
            ClangCompleter_MT )
end

function ClangCompleter:codeCompleteAt( user_data )
    if not self.completions_cache then
        -- completions cache is cleared, so create new completions
        local filename = user_data.filename
        local unsaved_files = user_data.unsaved_files
        local line = user_data.line
        local column = user_data.column
        local tu, __ = self:translationUnit( user_data )
        self.completions_cache = tu:codeCompletionAt( filename,
                                                      line,
                                                      column,
                                                      unsaved_files )
    end
    return self.completions_cache
end

function ClangCompleter:update( user_data )
    local tu, created = self:translationUnit( user_data )
    local unsaved_files = user_data.unsaved_files
    if not created then
        tu:update( unsaved_files )
    end
end

function ClangCompleter:locationToDefinition( user_data )
    local tu = self:translationUnit( user_data )
    return tu:locationToDefinition( user_data.line,
                                    user_data.column,
                                    user_data.unsaved_files )
end

function ClangCompleter:locationToDeclaration( user_data )
    local tu = self:translationUnit( user_data )
    return tu:locationToDeclaration( user_data.line,
                                     user_data.column,
                                     user_data.unsaved_files )
end

function ClangCompleter:translationUnit( user_data )
    -- return the translation unit if exists.
    local filename = user_data.filename
    local tu = self.tu_filename_table[ filename ]
    if tu then
        return tu, false
    end
    -- otherwise create a new translation unit and stores in tu_filename_table
    local new_tu = libclang.TranslationUnit:new( self.index.index,
                                                 filename,
                                                 user_data.unsaved_files,
                                                 user_data.flags )
    self.tu_filename_table[ filename ] = new_tu
    return new_tu, true
end

function ClangCompleter:resetCache()
    self.completions_cache = nil
end

function ClangCompleter:getDiagnostics( user_data )
    local tu, __ = self:translationUnit( user_data )
    return tu:getDiagnostics()
end

local completer = ClangCompleter:new()
local _M = {
    completer=completer,
}
return _M

