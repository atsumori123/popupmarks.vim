let s:save_cpo = &cpoptions
set cpoptions&vim

if exists('g:loaded_popupmarks')
	finish
endif
let g:loaded_popupmarks = 1

command! PopupMarks call popupmarks#open()


let &cpoptions = s:save_cpo
unlet s:save_cpo
