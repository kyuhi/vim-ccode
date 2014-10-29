let s:save_cpo = &cpo
set cpo&vim


" script variables -----------------------------------------------------------
let s:use_cache = 0
let s:script_root_dir = escape( expand( "<sfile>:p:h:h" ), '\' )


" global options -------------------------------------------------------------
let g:ccode#quiet =
    \ get( g:, 'ccode#quiet', 0 )
let g:ccode#parse_when_loaded =
    \ get( g:, 'ccode#parse_when_loaded', 0 )
let g:ccode#max_display_keywords =
    \ get( g:, 'ccode#max_display_keywords', 50 )
let g:ccode#parse_when_cursorhold =
    \ get( g:, 'ccode#parse_when_cursorhold', 1 )
let g:ccode#omni_completion_disable =
    \ get( g:, 'g:ccode#omni_completion_disable', 0 )
let g:ccode#completion_flags_function =
    \ get( g:, 'ccode#completion_flags_function', '' )


" global functions -----------------------------------------------------------
func! ccode#load_file()
    if !s:is_available_this_file()
        return
    endif

    " note: this is the specification.
    " 'longest' option is unnecessary because the omni completion of this
    " script can automatically invoke completion after insert any characters.
    " at that time, candidates of completion is reduced by character inserted.
    " if `longest` option is set, the first candidate is selected automatically
    " and reduce necessary candidates unfortunately.
    if !g:ccode#omni_completion_disable
        setlocal completeopt-=longest
        setlocal omnifunc=ccode#complete
    endif

    augroup ccode_auto_cmd
        au!
        autocmd InsertLeave <buffer> call s:handle_insert_leave()
        autocmd CursorHold <buffer> call s:handle_cursorhold()
    augroup end

    command! -buffer CCodeShowDiagnostics echo ccode#get_quickfixlist()
    command! -buffer CCodeShowCompletionFlags echo ccode#get_complete_flags()
    command! -buffer CCodeGotoDefinition
        \ call s:goto_location( ccode#get_location_to_definition() )
    command! -buffer CCodeGotoDeclaration
        \ call s:goto_location( ccode#get_location_to_declaration() )
    command! -buffer CCodeGoto
        \ call s:goto_location(
            \ ccode#get_location_to_declaration_or_definition() )

    let s:use_cache = 0
    call s:clear_completion_cache()
    if g:ccode#parse_when_loaded
        call ccode#parse()
    endif
endfunc


func! ccode#parse()
    lua ccode.completer:update(
                \ ccode.vim_user_data:userDataForCurrentFile() )
endfunc


func! ccode#complete( findstart, base )
    if a:findstart
        return s:find_starting_query()
    else
        if !s:use_cache
            call s:clear_completion_cache()
        endif
        return s:compute_candidates_for_query( a:base )
    endif
endfunc


func! ccode#get_location_to_declaration_or_definition()
    let loc = ccode#get_location_to_declaration()
    if empty( loc )
        let loc = ccode#get_location_to_definition()
    endif
    return loc
endfunc


func! ccode#get_location_to_definition()
    return s:get_location_to( 'definition' )
endfunc


func! ccode#get_location_to_declaration()
    return s:get_location_to( 'declaration' )
endfunc


func! ccode#get_quickfixlist()
    if !s:is_available_this_file()
        return []
    endif
    let qflist = []
lua << EOL
do
    local qflist = vim.eval('qflist')
    local user_data = ccode.vim_user_data:userDataForCurrentFile()
    ccode.completer:update( user_data )
    local diagnostics = ccode.completer:getDiagnostics( user_data )
    for __, diag in ipairs( diagnostics ) do
        if diag.kind ~= 'I' then
            local result = vim.dict()
            local loc = diag.location
            result.bufnr = vim.eval( string.format('bufnr("%s")', loc.filename) )
            result.lnum = loc.line
            result.col = loc.column
            result.text = diag.text
            result.type = diag.kind
            result.valid = 1
            qflist:add( result )
        end
    end
end
EOL
    for i in range( len(qflist) )
        let qflist[ i ] = s:convert_members_float2integer( qflist[i] )
    endfor
    return l:qflist
endfunc


func! ccode#get_complete_flags()
    let flags = []
lua << EOL
do
    local flags = vim.eval('flags')
    local filename = vim.eval('expand("%:p")')
    local lua_flags = ccode.vim_user_data:flagsForFile( filename )
    for __, flag in ipairs( lua_flags ) do
        flags:add( flag )
    end
end
EOL
    return flags
endfunc


" script local functions ------------------------------------------------------
func! s:find_starting_query()
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[ start - 1 ] =~ '\i'
        let start -= 1
    endwhile
    return start
endfunc


func! s:compute_candidates_for_query( query )
        let results = []
lua << EOL
    do
        local results = vim.eval( 'l:results' )
        local query = vim.eval( 'a:query' ):upper()
        local max_displays = vim.eval(
                            'g:ccode#max_display_keywords' )
        local nq = #query
        local user_data =
            ccode.vim_user_data:userDataForCurrentFile()
        local completions = ccode.completer:codeCompleteAt( user_data )
        local start = completions:searchLeftIndex( query )
        for i=start, completions:numDatas() do
            if #results >= max_displays then
                vim.command( 'call s:complete_after_insertion()' )
                break
            end
            local data = completions:dataAt( i )
            if data:startsWithUpper( query, nq ) then
                -- TODO: should i support snippets?
                local d = vim.dict()
                d.abbr = data:getSyntax()
                d.word = data:getName()
                -- d.word = data:getPlaceholder('$\\\\', '\\\\')
                d.menu = data:getReturnType()
                d.kind = data:getKind()
                d.info = data:getFullSyntax()
                d.icase = '1'
                -- d.dup = '1'
                results:add( d )
            end
        end -- for
    end
EOL
    return results
endfunc


func! s:handle_completion_if_needed()
    augroup ccode_after_insertion
        autocmd!
    augroup end
    if v:char =~ '\w'
        " \<c-p> is necessary because default completion select the
        " first candidate automatically. user seems to unexpect this behavior.
        let s:use_cache = 1
        call feedkeys("\<c-x>\<c-o>\<c-p>", "n")
    endif
    let s:use_cache = 0
endfunc


func! s:complete_after_insertion()
    augroup ccode_after_insertion
        autocmd!
    augroup end
    autocmd ccode_after_insertion InsertCharPre <buffer>
                \ call <SID>handle_completion_if_needed()
endfunc


func! s:handle_insert_leave()
    call s:clear_completion_cache()
endfunc


func! s:handle_cursorhold()
    if g:ccode#parse_when_cursorhold
        call ccode#parse()
    endif
endfunc


func! s:clear_completion_cache()
    lua ccode.completer:resetCache()
endfunc


func! s:goto_location( location )
    normal! m'
    if empty( a:location )
        call s:echo_warning( 'could not jump to location to definition.' )
        return
    endif
    if a:location.filename != expand('%:p')
        exec 'edit ' . a:location.filename
    endif
    call cursor( a:location.lnum, a:location.col )
    normal! zt
endfunc


func! s:get_location_to( definition_or_declaration )
    let command = ''
    if a:definition_or_declaration == 'definition'
        let command = 'locationToDefinition'
    elseif a:definition_or_declaration == 'declaration'
        let command = 'locationToDeclaration'
    else " invalid command
        echoerr printf("invalid command: %s", a:definition_or_declaration)
    endif
    let location = {}
lua << EOL
do
    local command = vim.eval('command')
    local user_data = ccode.vim_user_data:userDataForCurrentFile()
    local loc = ccode.completer[ command ]( ccode.completer, user_data )
    local vimlocation = vim.eval('location')
    if loc then
        vimlocation.lnum = loc.line
        vimlocation.col = loc.column
        vimlocation.filename = loc.filename
    end
end
EOL
    return s:convert_members_float2integer( location )
endfunc


func! s:convert_members_float2integer( dict )
    for key in keys( a:dict )
        if type( a:dict[ key ] ) == type( 3.14 )
            let a:dict[ key ] = float2nr( a:dict[ key ] )
        endif
    endfor
    return a:dict
endfunc


func! s:is_available_this_file()
    if !s:has_luajit()
        return
    elseif !s:has_libclang()
        return
    endif

    let l:available = 1
lua << EOL
do
    local filename = vim.eval( 'expand("%:p")' )
    if not ccode.vim_user_data:isAvailable( filename ) then
        vim.command('let l:available = 0')
    end
end
EOL
    return l:available
endfunc


func! s:has_luajit()
    if !has('lua')
        return 0
    endif
    let has_jit = 0
lua << EOL
do
    if jit ~= nil then
        vim.command( 'let has_jit = 1' )
    end
end
EOL
    return has_jit
endfunc


func! s:has_libclang()
    return finddir( $VIM_CCODE_CLANG_ROOT_DIRECTORY ) != '' ? 1 : 0
endfunc


func! s:echo_warning(...)
    if g:ccode#quiet
        return
    else
        let args = a:000
        if len(a:000) == 1
            let args = [ a:000[0] . '%s', '' ]
        endif
        echohl WarningMsg | echomsg call( 'printf', args ) | echohl None
    endif
endfunc


" lua initialization ----------------------------------------------------------
if !has('lua')
    call s:echo_warning(
        \ 'ccode unavailable: requires to compile VIM with lua support' )
    finish
elseif !s:has_luajit()
    call s:echo_warning(
        \ 'ccode unavailable: requires to compile VIM with luajit support' )
    finish
elseif !s:has_libclang()
    call s:echo_warning(
        \ 'ccode could not detect $VIM_CCODE_CLANG_ROOT_DIRECTORY: ' .
        \ 'set environment $VIM_CCODE_CLANG_ROOT_DIRECTORY ' . 
        \ 'to clang root library directory if you want to use ccode.' )
    finish
else
    let $VIM_CCODE_CLANG_ROOT_DIRECTORY_FOR_LUAJIT =
        \ expand( $VIM_CCODE_CLANG_ROOT_DIRECTORY )
lua << EOL
    package.path = package.path .. ';' .. vim.eval('s:script_root_dir') .. '/lua/?.lua'
    ccode = {
            completer = require( 'clang_completer' ).completer,
            vim_user_data = require( 'vim_user_data' ).user_data_store,
    }
EOL
endif


let &cpo = s:save_cpo
unlet s:save_cpo
