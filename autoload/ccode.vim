let s:save_cpo = &cpo
set cpo&vim

let s:use_cache = 0
let s:script_root_dir = escape( expand( "<sfile>:p:h:h" ), '\' )

" load luajit ----------------------------------------------------------------
if has('lua')
    if $VIM_CCODE_CLANG_ROOT_DIRECTORY == ''
        echo "$VIM_CLANG_ROOT_DIRECTORY is not found"
        finish
    endif
    let $VIM_CCODE_CLANG_ROOT_DIRECTORY = expand( $VIM_CCODE_CLANG_ROOT_DIRECTORY )
lua << EOL
    package.path = vim.eval('s:script_root_dir') .. '/lua/?.lua'
    ccode = {
            completer = require( 'clang_completer' ).completer,
            vim_user_data = require( 'vim_user_data' ).user_data_store,
    }
EOL
else
    echoe "ccode requires lua"
    finish
endif


" global options -------------------------------------------------------------
let g:ccode#max_display_keywords =
        \ get( g:, 'ccode#max_display_keywords', 50 )
let g:ccode#parse_when_loaded =
        \ get( g:, 'ccode#parse_when_loaded', 0 )
let g:ccode#recommend_setting =
        \ get( g:, 'ccode#recommend_setting', 1 )



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
    setlocal completeopt-=longest
    setlocal omnifunc=ccode#complete

    if g:ccode#recommend_setting
        " TODO:
    endif

    augroup ccode_auto_cmd
        au!
        autocmd InsertLeave <buffer> call s:handle_insert_leave()
        autocmd CursorHold <buffer> call ccode#parse()
    augroup end

    let s:use_cache = 0
    call s:clear_completion_cache()
    if g:ccode#parse_when_loaded
        call ccode#parse()
    endif
endfunc


func! ccode#register( source )
    " register call back functions for ccode
    "
    " source functions requires are ...
    "   "completion_flags" : returns completion flags for file.
    "       :return: list of flags
    "
    " example to define your own source ...
    " let s:source = {}
    " func! s:source.completion_flags()
    "   if &filetype == 'c'
    "       return ['-x', 'c', '-I/usr/include', '-I./']
    "   else &filetype == 'cpp'
    "       return ['-x', 'cpp', '-I/usr/include', '-I/usr/include/c++/']
    "   endif
    " endfunc
    " call ccode#register( s:source )
    "
    if !exists('g:ccode_source')
        let g:ccode_source = {}
    endif
    let g:ccode_source['completion_flags'] =
        \ a:source['completion_flags']
lua << EOL
do
    local eval_func = "g:ccode_source.completion_flags()"
    ccode.vim_user_data:setVimEvalStringForFlags( eval_func )
end
EOL
    let g:ccode_source_resistered = 1
endfunc


func! ccode#parse()
    lua ccode.completer:update(
                \ ccode.vim_user_data:userDataForCurrentFile() )
endfunc


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
                -- 
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


func! ccode#show_diagnostics()
    echo ccode#get_quickfixlist()
endfunc


func! ccode#show_complete_flags()
    let l:flags = []
lua << EOL
do
    local flags = vim.eval('l:flags')
    local filename = vim.eval('expand("%:p")')
    local lua_flags = ccode.vim_user_data:flagsForFile( filename )
    for __, flag in ipairs( lua_flags ) do
        flags:add( flag )
    end
end
EOL
    echo l:flags
endfunc


func! ccode#get_quickfixlist()
    if !s:is_available_this_file()
        return []
    endif
    let l:qflist = []
lua << EOL
do
    local qflist = vim.eval('l:qflist')
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
    for qfdict in l:qflist " convert float values into integers.
        for key in keys( qfdict )
            if type(qfdict[key]) == type(3.14)
                let qfdict[key] = float2nr( qfdict[key] )
            endif
        endfor
    endfor
    return l:qflist
endfunc


" local functions -------------------------------------------------------------
func! s:handle_completion_if_needed()
    augroup ccode_after_insertion
        autocmd!
    augroup end
    if v:char =~ '\w'
        " \<c-p> is necessary because default invoked completion select the
        " first candidate automatically. user seems not to like this behavior.
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


func! s:clear_completion_cache()
    lua ccode.completer:resetCache()
endfunc


func! s:has_luajit()
    if !has('lua')
        return 0
    endif
    let l:has_jit = 0
lua << EOL
do
    if jit ~= nil then
        vim.command('let l:has_jit = 1')
    end
end
EOL
    return l:has_jit
endfunc


func! s:has_libclang()
    if $VIM_CCODE_CLANG_ROOT_DIRECTORY != ''
        return 1
    else
        return 0
    endif
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
    local filename = vim.eval('expand("%:p")')
    if not ccode.vim_user_data:isAvailable( filename ) then
        vim.command('let l:available = 0')
    end
end
EOL
    return l:available
endfunc


let &cpo = s:save_cpo
unlet s:save_cpo
