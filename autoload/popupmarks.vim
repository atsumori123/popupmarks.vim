let s:save_cpo = &cpoptions
set cpoptions&vim

" マークファイル
if has('unix') || has('macunix')
	let s:markfile = expand('~/.vimmarks')
else
	let s:markfile = expand('~/_vimmarks')
endif

" マークウィンドウID記憶用
let s:MarkWinid = -1
" ウィンドウの横幅
let s:mars_winsize = float2nr(&columns * 2 / 3)

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
" ファイル名と行番号から一番近いマークの番号を返す（ない場合は0を返却）
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
" 選択行のマークを返す
"---------------------------------------------------------------
function! s:GetSelectMark() abort
	let i = (line('.') - 1) / 4
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
		if len(parts) >= 5
			call add(marks, { 'file':parts[0], 'lnum':parts[1], 'func':parts[2], 'text':parts[3], 'depth':str2nr(parts[4]) })
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
		call add(lines, m.file . "\t" . m.lnum . "\t" . m.func . "\t" . m.text . "\t" . m.depth)
	endfor

	" ファイル書き込み
	call writefile(lines, s:markfile)
endfunction

"---------------------------------------------------------------
" バッファ表示形式に変換
"---------------------------------------------------------------
function! s:BuildLinesForBuffer() abort
	let lines = []
	let prefix = "   "
	for i in range(len(s:Marks) - 1, 0, -1)
		let m = s:Marks[i]

		" 1つ前のプレフィックスとその長さ
		let old_prefix  = prefix
		let old_prefix_len = len(old_prefix)

		" 現在のプレフィックスの長さ
		let prefix_len  = 3 * (m.depth + 1)

		if old_prefix_len < prefix_len
			" 階層が深くなった（プレフィックスを長くする）
			let prefix .= repeat(" ", prefix_len - old_prefix_len)
		elseif old_prefix_len > prefix_len 
			" 階層が浅くなった（プレフィックスを短くする）
			let prefix = prefix[:prefix_len-1]
		endif

		call insert(lines, prefix[:-4] . "+- " . fnamemodify(m.file, ":t") . ' (' . m.file . ')', 0)
		call insert(lines, prefix . m.func, 1)
		call insert(lines, prefix . printf("%-4s  %s", m.lnum, m.text), 2)
		call insert(lines, old_prefix . "", 3)

		" 階層ツリー
		let n = 3 * m.depth
		if n == 0
			let head = ""
			let tail = prefix[1:]
		else
			let head = prefix[:n-1]
			let tail = prefix[n+1:]
		endif
		let prefix = head . '|' . tail
	endfor

	return lines
endfunction

"---------------------------------------------------------------
" 表示の更新
"---------------------------------------------------------------
function! s:UpdateText() abort
	let old_lnum = line('$')

	" 更新
	setlocal modifiable
	silent! call deletebufline('%', 1, '$')
	silent! call setbufline('%', 1,  s:BuildLinesForBuffer())
	setlocal nomodifiable

	" ハイライト
	if old_lnum != line('$')
		call s:SetHighLightForBuffer()
	endif
endfunction

"---------------------------------------------------------------
" 行番号から次のカーソル位置を設定する
"---------------------------------------------------------------
function! s:UpdateCursor(index) abort
	let lnum = a:index * 4 + 1
	call execute('call cursor(' . lnum . ', 1)')
	if &lines - 10 - 2 < lnum
	 	call execute('normal! jjkk')
	endif
endfunction

function! s:UpdateCursorByLnum(direction) abort
	" 行番号からマーク番号に変換
	let index = line('.') / 4

	" 次のカーソル位置を設定
	let index += a:direction
	let index = empty(s:Marks) ? 0 : min([max([0, index]), len(s:Marks) - 1])
	call s:UpdateCursor(index)
endfunction

"---------------------------------------------------------------
" マークの追加
"---------------------------------------------------------------
function! s:AddMark() abort
	execute 'wincmd p'

	let text = substitute(getline('.'), '\t', ' ', 'g')
	let text = substitute(text, '\v^ +|\t', '', 'g')

	" 現在行のマーク作成
	let m = {}
	let m.file = expand('%:p')						" ファイル名
	let m.lnum = line('.')							" 行番号
	let m.func = func#GetCurrentFunctionName()		" 関数名
	let m.text = text								" 関数名
	let m.depth = 0									" 深さ

	execute 'wincmd w'

	" 同一箇所のマークが既に登録されている場合は一旦削除する
	call filter(s:Marks, { idx, val -> val.file !=# m.file || val.lnum !=# m.lnum })

	" マークリストに追加
	call add(s:Marks, m)

	" マークファイルを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText()
	call s:UpdateCursor(len(s:Marks) - 1)
endfunction

"---------------------------------------------------------------
" マークの削除
"---------------------------------------------------------------
function! s:DeleteMark() abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark()

	" 選択マークを削除
	call remove(s:Marks, i)

	" マークを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText()
	call s:UpdateCursor(max([0, i - 1]))
endfunction

"---------------------------------------------------------------
" マークの編集
"---------------------------------------------------------------
function! s:EditMark() abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark()

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
	call s:UpdateText()
	call s:UpdateCursor(i)
endfunction

"---------------------------------------------------------------
" マークの移動
"---------------------------------------------------------------
function! s:Move(direction) abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark()

	" 選択マークを一旦リストから外して、新しい場所に登録し直す
	let _ = remove(s:Marks, i)
	let i = min([max([0, (i + a:direction)]), len(s:Marks)])
	call insert(s:Marks, m, i)

	" マークを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText()
	call s:UpdateCursor(i)
endfunction

"---------------------------------------------------------------
" インデントの指定
"---------------------------------------------------------------
function! s:Depth(depth) abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark()

	" 深さを増減
	let n = m.depth + a:depth
	let m.depth = n < 0 ? 0 : n

	" マークを保存
	call s:SaveMarkFile()

	" 表示とカーソルを更新
	call s:UpdateText()
	call s:UpdateCursor(i)
endfunction

"---------------------------------------------------------------
" ジャンプ
"---------------------------------------------------------------
function! s:Jump() abort
	" 選択行のマークを取得
	let [i, m]= s:GetSelectMark()

	execute "wincmd p"

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
" ハイライト設定
"---------------------------------------------------------------
function! s:SetHighLightForBuffer()
	let lnum = line('$')

	" ハイライトを全クリア
	call clearmatches()

	" 表示要素がない場合は終了
	if lnum < 3 | return | endif

	" ファイル名(1,5,9,13...行目)をハイライト
	let list = range(1, lnum, 4)
	let pattern = join(map(list, {_, v -> '\%' . v . 'l'}), '\|')
	call matchadd('String', pattern, -1)

	" 関数名(2,6,10,14...行目)をハイライト
	let list = range(2, lnum, 4)
	let pattern = join(map(list, {_, v -> '\%' . v . 'l'}), '\|')
	call matchadd('Function', pattern, -1)

	" 行番号(3,7,11,15...行目)をハイライト
	let list = range(3, lnum, 4)
	let pattern = join(map(list, {_, v -> '\%' . v . 'l\%(^\s*\|\s*\)\@<=\d\+'}), '\|')
	call matchadd('Number', pattern, -1)
endfunction

"---------------------------------------------------------------
" ウィンドウのリサイズ
"---------------------------------------------------------------
function! s:ResizeWindow(inout) abort
	if a:inout
		let size = s:mars_winsize
	else
		let s:mars_winsize = getwininfo(win_getid())[0].width
		let size = 40
	endif
	execute "vertical resize " . size
endfunction

"---------------------------------------------------------------
" バッファでマークを表示
"---------------------------------------------------------------
function! s:OpenBuffer() abort
	" Open a new window at the bottom
	let size = float2nr(&columns * 2 / 3)
	execute 'silent! botright vertical ' . s:mars_winsize . ' split -marks-'
	execute 'silent vertical resize ' . s:mars_winsize

	setlocal buftype=nofile
	setlocal bufhidden=wipe
	setlocal noswapfile
	setlocal nobuflisted
	setlocal nowrap
	setlocal nonumber
	setlocal foldcolumn=0
	setlocal filetype=marks
	setlocal winfixheight winfixwidth

	" 表示
	call s:UpdateText()

	" set keymap
	nnoremap <buffer> <silent> q :close<CR>
	nnoremap <buffer> <silent> j :call <SID>UpdateCursorByLnum(1)<CR>
	nnoremap <buffer> <silent> k :call <SID>UpdateCursorByLnum(-1)<CR>
	nnoremap <buffer> <silent> a :call <SID>AddMark()<CR>
	nnoremap <buffer> <silent> d :call <SID>DeleteMark()<CR>
	nnoremap <buffer> <silent> e :call <SID>EditMark()<CR>
	nnoremap <buffer> <silent><c-j> :call <SID>Move(1)<CR>
	nnoremap <buffer> <silent><c-k> :call <SID>Move(-1)<CR>
	nnoremap <buffer> <silent><c-l> :call <SID>Depth(1)<CR>
	nnoremap <buffer> <silent><c-h> :call <SID>Depth(-1)<CR>
	nnoremap <buffer> <silent> <CR> :call <SID>Jump()<CR>

	" フォーカスがポップアップウィンドウにIN/OUTで発火
	augroup PopupMarksInOut
		autocmd! * <buffer>
		autocmd WinLeave  <buffer> call <SID>ResizeWindow(0)
		autocmd WinEnter  <buffer> call <SID>ResizeWindow(1)
	augroup END

	return win_getid()
endfunction

"---------------------------------------------------------------
" マークの表示
"---------------------------------------------------------------
function! popupmarks#open() abort
	let file = expand('%:p')
	let lnum = line('.')

	let winnum = bufwinnr("-marks-")
	if winnum != -1
		" マークしているファイルを既に開いている場合は、そのウィンドウにフォーカスを移動させる
		execute winnum.'wincmd w'
		let index = s:GetMarkIndex(file, lnum)
		if index != -1
			call s:UpdateCursor(index)
		endif

	else
		" マークを読み込み
		let s:Marks = s:LoadMarks()

		" 表示
		let s:MarkWinid = s:OpenBuffer()

		" 現在行と一番近いマークにカーソルを移動
		let index = s:GetMarkIndex(file, lnum)
		if index == -1 | let index = 0 | endif
		call s:UpdateCursor(index)
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
		let m.depth = 0									" 階層

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
		call s:UpdateText()
		execute 'wincmd p'
	endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
