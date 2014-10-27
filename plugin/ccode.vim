"=============================================================================
" File: ccode.vim
" Author: Kaika Yuhi <kyuhi74apid@gmail.com>
"=============================================================================
if exists( 'g:loaded_ccode' )
    finish
endif

augroup ccode
    au!
    au FileType c,cpp,objc,objcpp call ccode#load_file()
augroup end

let g:loaded_ccode = 1
