let s:save_cpo = &cpoptions
set cpoptions&vim

" マークファイル
if has('unix') || has('macunix')
	let s:markfile = expand('~/.vimmarks')
else
	let s:markfile = expand('~/_vimmarks')
endif

" ハイライトグループを定義
if empty(prop_type_get('MarkFile'))
	call prop_type_add('MarkFile', {'highlight': 'String'})
endif
if empty(prop_type_get('MarkFunc'))
	call prop_type_add('MarkFunc', {'highlight': 'function'})
endif
if empty(prop_type_get('MarkLine'))
	call prop_type_add('MarkLine', {'highlight': 'Number'})
endif

" 複数キーによるコンビネーション用
let s:last_key = ''
" 前回打鍵したときの時間
let s:last_time = [0, 0] " [seconds, microseconds]
" マークウィンドウID記憶用
let s:MarkWinid = -1
" ポップアップウィンドウの横幅
let s:popup_width = &columns - 20

"---------------------------------------------------------------
" マークウィンドウのウィンドウ番号とIDを返却する
"---------------------------------------------------------------
function! s:GetMarkWindow() abort
	let winnr = win_id2win(s:MarkWinid)
	if winnr == 0
		let s:MarkWinid = -1
		return [-1, -1]
	endif
	return [winnr, s:MarkWinid]
endfunction

"---------------------------------------------------------------
" ファイル名と行番号から登録している一番近いマークの番号を返却する（ない場合は0を返却）
"---------------------------------------------------------------
function! s:GetMarkIndex(file, lnum) abort
	let closest_index = -1
	let closest_diff = -1

	for i in range(len(s:Marks))
		if a:file !=# s:Marks[i].file
			continue
		endif

		let diff = abs(a:lnum - s:Marks[i].lnum)
		if diff < closest_diff || closest_diff == -1
			let closest_diff= diff
			let closest_index = i
		endif
	endfor
	return closest_index
endfunction

"---------------------------------------------------------------
" バッファでマークを表示しているか
"---------------------------------------------------------------
function! s:IsBuffer() abort
	if win_id2win(s:MarkWinid) == 0
		return 0
	endif

	if win_gettype(s:MarkWinid) ==# "popup"
		return 0
	endif

	return 1
endfunction

"---------------------------------------------------------------
" 選択行のマークを取得する
"---------------------------------------------------------------
function! s:GetSelectMark(winid) abort
	let i = (line('.', a:winid) - 1) / 4
	return [i, s:Marks[i]]
endfunction

"---------------------------------------------------------------
" マークの読み込み
"---------------------------------------------------------------
function! s:LoadMarks() abort
	if !filereadable(s:markfile)
		return []
	endif

	let lines = readfile(s:markfile)
	let marks = []
	for line in lines
		" タブで分割して辞書型で登録
	 	let parts = split(line, '\t')
		if len(parts) >= 4
			call add(marks, { 'file':parts[0], 'lnum':parts[1], 'func':parts[2], 'text':parts[3] })
		endif
	endfor

	return marks
endfunction

"---------------------------------------------------------------
" マークの保存
"---------------------------------------------------------------
function! s:SaveMarkFile() abort
	let lines = []

	" 連想配列の各要素をタブ区切りのレコード形式に変換する
	for m in s:Marks
		call add(lines, m.file . "\t" . m.lnum . "\t" . m.func . "\t" . m.text)
	endfor

	" ファイル書き込み
	call writefile(lines, s:markfile)
endfunction

"---------------------------------------------------------------
" pupup表示形式に変換
"---------------------------------------------------------------
function! s:BuildLinesForPopup() abort
	let lines = []

	for m in s:Marks
		" ファイル見出し行
		let file = strcharpart(fnamemodify(m.file, ":t") . ' (' . m.file . ')', 0, s:popup_width)
		call add(lines, {'text':file, 'props':[#{col: 1, length: len(file), type: "MarkFile"}]})
		" 関数名
		call add(lines, {'text':'    ' . m.func, 'props':[#{col: 5, length: len(m.func), type: "MarkFunc"}]})
		" 行番号＋テキスト
		let text = strcharpart(printf("    %-4s %s", m.lnum, m.text), 0, s:popup_width-45)
		call add(lines, {'text':text, 'props':[#{col: 5, length: len(m.lnum), type: "MarkLine"}]})
		" マーク間の空行
		call add(lines, {'text':''})
	endfor

	return lines
endfunction

"---------------------------------------------------------------
" バッファ表示形式に変換
"---------------------------------------------------------------
function! s:BuildLinesForBuffer() abort
	let lines = []

	for m in s:Marks
		" ファイル見出し行
		call add(lines, fnamemodify(m.file, ":t") . ' (' . m.file . ')')
		" 関数名
		call add(lines, '    ' . m.func)
		" 行番号＋テキスト
		call add(lines, '    ' . printf("%-4s  %s", m.lnum, m.text))
		" マーク間の空行
		call add(lines, '')
	endfor

	return lines
endfunction

"---------------------------------------------------------------
" 描画
"---------------------------------------------------------------
function! s:SetTextToBuffer(lines) abort
	" 変更許可
	setlocal modifiable

	" 全行消去
	silent! call deletebufline('%', 1, '$')

	silent! 0put = a:lines
	silent! $delete _
	normal! gg

	" 変更禁止
	setlocal nomodifiable
endfunction

"---------------------------------------------------------------
" 表示の更新
"---------------------------------------------------------------
function! s:UpdateText(winid) abort
	if s:IsBuffer()
		call s:SetTextToBuffer(s:BuildLinesForBuffer())
	else
		call popup_settext(a:winid, s:BuildLinesForPopup())
	endif
endfunction

"---------------------------------------------------------------
" 行番号から次のカーソル位置を設定する
"---------------------------------------------------------------
function! s:UpdateCursor(winid, index) abort
	let lnum = a:index * 4 + 1
	call win_execute(a:winid, 'call cursor(' . lnum . ', 1)')
	if &lines - 10 - 2 < lnum
	 	call win_execute(a:winid, 'normal! jjkk')
	endif
endfunction

function! s:UpdateCursorByLnum(winid, direction) abort
	" 行番号からマーク番号に変換
	let index = line('.', a:winid) / 4

	" 次のカーソル位置を設定
	let index += a:direction
	let index = empty(s:Marks) ? 0 : min([max([0, index]), len(s:Marks) - 1])
	call s:UpdateCursor(a:winid, index)
endfunction

"---------------------------------------------------------------
" マークの追加
"---------------------------------------------------------------
function! s:AddMark(winid) abort
	if s:IsBuffer() | execute 'wincmd p' | endif

	let text = substitute(getline('.'), '\t', ' ', 'g')
	let text = substitute(text, '\v^ +|\t', '', 'g')

	" 現在行のマーク作成
	let m = {}
	let m.file = expand('%:p')						" ファイル名
	let m.lnum = line('.')							" 行番号
	let m.func = func#GetCurrentFunctionName()		" 関数名
	let m.text = text								" 関数名

	if s:IsBuffer() | execute 'wincmd w' | endif

	" 同一箇所のマークが既に登録されている場合は一旦削除する
	call filter(s:Marks, { idx, val -> val.file !=# m.file || val.lnum !=# m.lnum })

	" マークリストに追加
	call add(s:Marks, m)

	" マークファイルを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText(a:winid)
	call s:UpdateCursor(a:winid, len(s:Marks) - 1)
endfunction

"---------------------------------------------------------------
" マークの削除
"---------------------------------------------------------------
function! s:DeleteMark(winid) abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark(a:winid)

	" 選択マークを削除
	call remove(s:Marks, i)

	" マークを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText(a:winid)
	call s:UpdateCursor(a:winid, max([0, i - 1]))
endfunction

"---------------------------------------------------------------
" マークの編集
"---------------------------------------------------------------
function! s:EditMark(winid) abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark(a:winid)

	" 新しい名前を入力
	let m.func = input('Function name: ', m.func)
	redraw | echo ""

	" 空白が入力またはキャンセルされた場合は終了
	if len(m.func) == 0 | return | endif

	" 選択マークを更新
	let s:Marks[i] = m

	" マークを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText(a:winid)
	call s:UpdateCursor(a:winid, i)
endfunction

"---------------------------------------------------------------
" マークの移動
"---------------------------------------------------------------
function! s:MoveMark(winid, direction) abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark(a:winid)

	" 選択マークを一旦リストから外して、新しい場所に登録し直す
	let _ = remove(s:Marks, i)
	let i = min([max([0, (i + a:direction)]), len(s:Marks)])
	call insert(s:Marks, m, i)

	" マークを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText(a:winid)
	call s:UpdateCursor(a:winid, i)
endfunction

"---------------------------------------------------------------
" ジャンプ
"---------------------------------------------------------------
function! s:Jump(winid) abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark(a:winid)

	if s:IsBuffer()
		execute "wincmd p"
	else
		call popup_close(a:winid)
	endif

	let winnum = bufwinnr('^' . m.file . '$')
	if winnum != -1
		exe winnum . 'wincmd w'
		execute m.lnum
	else
		execute 'edit ' . fnameescape(m.file)
		execute m.lnum
	endif
endfunction

"---------------------------------------------------------------
" ポップアップ内キー処理
"---------------------------------------------------------------
function! s:PopupFilter(winid, key) abort
	let now = reltime()

	" 前回の打鍵からの経過時間をミリ秒で計算
	" reltimefloat は秒単位（小数）で返すため 1000 倍する
	let elapsed = reltimefloat(reltime(s:last_time, l:now)) * 1000

	" 設定値（timeoutlen）を超えていたらバッファをクリア
	if elapsed > &timeoutlen
		let s:last_key = ''
	endif

	" 今回の打鍵時刻を記録
	let s:last_time = now

	if a:key ==# 'q'			" 終了
		call popup_close(a:winid, -1)
		return 1

	elseif a:key ==# 'j'		" 下移動
		call s:UpdateCursorByLnum(a:winid, 1)
		return 1

	elseif a:key ==# 'k'		" 上移動
		call s:UpdateCursorByLnum(a:winid, -1)
		return 1

	elseif a:key ==# 'a'		" マークの追加
		call s:AddMark(a:winid)
		return 1

	elseif a:key ==# 'd'		" マークの削除
		call s:DeleteMark(a:winid)
		return 1

	elseif a:key ==# 'e'		" マークの編集
		call s:EditMark(a:winid)
		return 1

	elseif a:key ==# "J"		" マークを下に移動
		call s:MoveMark(a:winid, 1)
		return 1

	elseif a:key ==# "K"		" マークを上に移動
		call s:MoveMark(a:winid, -1)
		return 1

	elseif a:key ==# "\<CR>"	" マーク位置にジャンプ
		call s:Jump(a:winid)
		return 1
	endif

	let s:last_key = a:key	

	return popup_filter_menu(a:winid, a:key)
endfunction

"---------------------------------------------------------------
" ポップアップでマークを表示
"---------------------------------------------------------------
function! s:OpenPopup() abort
	" popup 用の行を生成
	let lines = s:BuildLinesForPopup()

	let opts = {
		\ 'title': ' Marks (Enter:Jump, ma:add, md:delete, me:edit, <S-k>:up, <S-j>:down) ',
		\ 'border': [],
		\ 'borderchars': has('gui') ? ['─','│','─','│','┌','┐','┘','└'] : [],
		\ 'padding': [1,1,1,1],
		\ 'minwidth': s:popup_width,
		\ 'minheight': &lines - 10,
		\ 'mmaxwidth': s:popup_width,
		\ 'maxheight': &lines - 10,
		\ 'scrollbar': 0,
		\ 'mapping': 0,
		\ 'cursorline': 1,
		\ 'filter': function('s:PopupFilter'),
		\ }

	return popup_create(lines, opts)
endfunction

"---------------------------------------------------------------
" バッファでマークを表示
"---------------------------------------------------------------
function! s:OpenBuffer() abort
	" Open a new window at the bottom
	execute 'silent! botright vertical 40 split -marks-'
	execute 'silent vertical resize 40'

	setlocal buftype=nofile
	setlocal noswapfile
	setlocal nobuflisted
	setlocal nowrap
	setlocal nonumber
	setlocal foldcolumn=0
	setlocal filetype=marks
	setlocal winfixheight winfixwidth

	" 表示
	call s:SetTextToBuffer(s:BuildLinesForBuffer())

	" set hightlight
	syn match MarksFile '^[^ \t].*$'
	syn match MarksFunc '^ \{4}\zs\S\+'
	syn match MarksLineNr '^\s*\zs\d\+'
	hi! def link MarksFile String
	hi! def link MarksFunc Function
	hi! def link MarksLineNr Number

	" set keymap
	nnoremap <buffer> <silent> q :close<CR>
	nnoremap <buffer> <silent> j :call <SID>UpdateCursorByLnum(win_getid(), 1)<CR>
	nnoremap <buffer> <silent> k :call <SID>UpdateCursorByLnum(win_getid(), -1)<CR>
	nnoremap <buffer> <silent> a :call <SID>AddMark(win_getid())<CR>
	nnoremap <buffer> <silent> d :call <SID>DeleteMark(win_getid())<CR>
	nnoremap <buffer> <silent> e :call <SID>EditMark(win_getid())<CR>
	nnoremap <buffer> <silent> J :call <SID>MoveMark(win_getid(), 1)<CR>
	nnoremap <buffer> <silent> K :call <SID>MoveMark(win_getid(), -1)<CR>
	nnoremap <buffer> <silent> <CR> :call <SID>Jump(win_getid())<CR>

	return win_getid()
endfunction

"---------------------------------------------------------------
" マークの表示
"---------------------------------------------------------------
function! popupmarks#open(...) abort
	let arg = get(a:000, 0, "popup")
	let file = expand('%:p')
	let lnum = line('.')

	let winnum = bufwinnr("-marks-")
	if winnum != -1
		" マークしているファイルを既に開いている場合は、そのウィンドウにフォーカスを移動させる
		execute winnum.'wincmd w'
		let index = s:GetMarkIndex(file, lnum)
		if index != -1
			call s:UpdateCursor(s:MarkWinid, index)
		endif

	else
		" マークを読み込み
		let s:Marks = s:LoadMarks()

		" ウィンドウを作成(ポップアップorバッファ)
		if arg == 'popup'
			let s:popup_width = &columns - 20
			let s:MarkWinid = s:OpenPopup()
		else
			let s:MarkWinid = s:OpenBuffer()
		endif

		" 現在行と一番近いマークにカーソルを移動
		let index = s:GetMarkIndex(file, lnum)
		if index == -1 | let index = 0 | endif
		call s:UpdateCursor(s:MarkWinid, index)
	endif

endfunction

"---------------------------------------------------------------
" マークの追加、最終マークの名前の変更／削除
"---------------------------------------------------------------
function! popupmarks#edit(arg) abort
	" マークウィンドウにフォーカスがある状態での実行は無効
	let [winnr, winid] = s:GetMarkWindow()
	if winid == win_getid() | return | endif

	" マークを読み込み
	let s:Marks = s:LoadMarks()

	if a:arg ==# "Edit"
		if empty(s:Marks) | return | endif

		" 最終のマークを取得
		let m = s:Marks[-1]

		" 新しい名前を入力
		let m.func = input('Function name: ', m.func)
		redraw | echo ""

		" 空白が入力またはキャンセルされた場合は終了
		if len(m.func) == 0 | return | endif

		" 選択マークを更新
		let s:Marks[-1] = m
		call s:SaveMarkFile()
		echohl String | echomsg "Edited last mark." | echohl None

	elseif a:arg ==# "Del"
		" マークが未登録の場合は終了
		if empty(s:Marks) | return | endif

		" 最終マークを削除
		call remove(s:Marks, -1)
		call s:SaveMarkFile()
		echohl String | echomsg "Deleted last mark." | echohl None

	elseif a:arg ==# "Add"
		let text = substitute(getline('.'), '\t', ' ', 'g')
		let text = substitute(text, '\v^ +|\t', '', 'g')

		" 現在行のマーク作成
		let m = {}
		let m.file = expand('%:p')						" ファイル名
		let m.lnum = line('.')							" 行番号
		let m.func = func#GetCurrentFunctionName()		" 関数名
		let m.text = text								" 関数名

		" 同一箇所のマークが既に登録されている場合は一旦削除してから登録
		call filter(s:Marks, { idx, val -> val.file !=# m.file || val.lnum !=# m.lnum })
		call add(s:Marks, m)
		call s:SaveMarkFile()
		echohl String | echomsg "Added mark to last." | echohl None

	endif

	" マークバッファを開いている場合は表示更新
	let [winnr, winid] = s:GetMarkWindow()
	if winnr != -1
		execute winnr.'wincmd w'
		call s:UpdateText(winid)
		execute 'wincmd p'
	endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
