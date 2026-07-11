let s:save_cpo = &cpoptions
set cpoptions&vim

if exists('g:loaded_popupmarks')
	finish
endif
let g:loaded_popupmarks = 1

command! -nargs=0 OpenMarks call popupmarks#open()
command! -nargs=1 EditMarks call popupmarks#edit(<f-args>)

let &cpoptions = s:save_cpo
unlet s:save_cpo
