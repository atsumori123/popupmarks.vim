let s:save_cpo = &cpoptions
set cpoptions&vim

" マークファイル
if has('unix') || has('macunix')
	let s:markfile = expand('~/.vimmark')
else
	let s:markfile = expand('~/_vimmark')
endif

" ハイライトグループを定義
if empty(prop_type_get('MarkFile'))
	call prop_type_add('MarkFile', {'highlight': 'String'})
endif
if empty(prop_type_get('MarkFunc'))
	call prop_type_add('MarkFunc', {'highlight': 'function'})
endif
if empty(prop_type_get('MarkLine'))
	call prop_type_add('MarkLine', {'highlight': 'Comment'})
endif

"---------------------------------------------------------------
" マークの読み込み
"---------------------------------------------------------------
function! s:LoadMarks() abort
	if !filereadable(s:markfile)
		return {}
	endif

	let lines = readfile(s:markfile)

	let marks = {}
	for line in lines
		" タブで分割して配列[ファイル, 関数名, 行番号, テキスト]にする
		let parts = split(line, '\t')

		" ファイル名、関数、行番号、テキストが揃っていない場合はスキップ
		if len(parts) < 4 | continue | endif

		" グループが無い場合は、作成する
		if !has_key(marks, parts[0])
			let marks[parts[0]] = []
		endif

		" ファイル名をキーとして{'func':関数名, 'lnum':行番号, 'text':テキスト}の連想配列にする
		call add(marks[parts[0]], {'func':parts[1], 'lnum':parts[2], 'text':parts[3]})
	endfor

	return marks
endfunction

"---------------------------------------------------------------
" マークの保存
"---------------------------------------------------------------
function! s:SaveMarkFile(marks) abort
	let lines = []

	" 連想配列の各要素をタブ区切りのレコード形式に変換する
	for file in sort(keys(a:marks))
		for m in a:marks[file]
			call add(lines, file . "\t" . m.func . "\t" . m.lnum . "\t" . m.text)
		endfor
	endfor

	" ファイル書き込み
	call writefile(lines, s:markfile)
endfunction

"---------------------------------------------------------------
" 昇順並べ替え用
"---------------------------------------------------------------
function! s:CompareMarkByLnum(a, b) abort
	return a:a.lnum - a:b.lnum
endfunction

"---------------------------------------------------------------
" pupup表示用形式に変換
"---------------------------------------------------------------
function! s:BuildLines() abort
	let lines = []

	for file in sort(keys(s:Marks))
		" lnumで昇順に並び替え
		call sort(s:Marks[file], function('s:CompareMarkByLnum'))

		" ファイル見出し行
		call add(lines, {'text':file, 'props':[#{col: 1, length: len(file), type: "MarkFile"}]})

"		for m in s:Marks[file]
		for m in s:Marks[file]
			" 関数名
			call add(lines, {'text':'    ' . m.func, 'props':[#{col: 5, length: len(m.func), type: "MarkFunc"}]})
			" 行番号＋テキスト
			call add(lines, {'text':'    ' . printf("%-4s", m.lnum) . ' ' .. m.text, 'props':[#{col: 5, length: len(m.lnum), type: "MarkLine"}]})
			" マーク間の空行
			call add(lines, {'text':''})
		endfor
	endfor

	return lines
endfunction

"---------------------------------------------------------------
" ポップアップの更新
"---------------------------------------------------------------
function! s:UpdatePopup(winid) abort
	" popup 用の行を生成
	let lines = s:BuildLines()

	" 表示内容を更新
	call popup_settext(a:winid, lines)
endfunction

"---------------------------------------------------------------
" ポップアップ表示
"---------------------------------------------------------------
function! popupmarks#open() abort
	" マークを読み込み
	let s:Marks = s:LoadMarks()

	" popup 用の行を生成
	let lines = s:BuildLines()

	let opts = {
		\ 'title': ' Marks  (Enter:Jump, a:add, d:delete, e:edit) ',
		\ 'border': [],
		\ 'borderchars': ['─','│','─','│','┌','┐','┘','└'],
		\ 'padding': [0,1,0,1],
		\ 'minwidth':&columns - 20,
		\ 'minheight':&lines - 12,
		\ 'maxheight': 15,
		\ 'scrollbar': 0,
		\ 'mapping': 0,
		\ 'cursorline': 1,
		\ 'filter': function('s:PopupFilter'),
		\ }

	const winid = popup_create(lines, opts)

	call s:GetNextcursorline(winid, 1)
endfunction

"---------------------------------------------------------------
" 選択行からジャンプ先ファイル名と行番号を取得する
"---------------------------------------------------------------
function! s:GetSelectMark(winid) abort
	" 選択行番号
	let lnum = line('.', a:winid)
	" バッファ番号
	let bufnr = winbufnr(a:winid)
	" 選択行のテキスト
	let text = getbufline(bufnr, lnum)[0]

	" 空行と空白以外の文字から始まる場合（＝ファイル行）は無視する
	if empty(text) || text =~ '^[^ ]' | return {'file':'', 'lnum':''} | endif

	" 選択行が、「行番号+テキスト」でない場合は、次行を取得する
	if text !~# '^\s*\d\+\s*'
		let text = getbufline(bufnr, lnum + 1)[0]
	endif

	" 空白で分割して行番号を抽出
	let target_lnum = split(text, ' ')[0]

	" 上に遡ってファイルを取得
	let i = lnum
	let target_file = ''
	while i > 0 && empty(target_file)
		let target_file = matchstr(getbufline(bufnr, i)[0], '^\S.*')
		let i -= 1
	endwhile

	return {'file':target_file, 'lnum':target_lnum}
endfunction

"---------------------------------------------------------------
" 次のカーソル位置を取得する
"---------------------------------------------------------------
function! s:GetNextcursorline(winid, direction) abort
	" 選択行番号
	let lnum = line('.', a:winid)
	" バッファ番号
	let bufnr = winbufnr(a:winid)
	" バッファの行数を取得
	let line_count = len(getbufline(bufnr, 1, '$'))

	" バッファの行数の範囲で関数名またはファイル名の行を検索する
	let i = lnum + a:direction
	let idx = -1
	while i > 0 && i <= line_count
		let line = getbufline(bufnr, i)[0]
		if line !~# '^\s*\d\+\s*' && line =~ '^\s\+.*' && !empty(line)
			let idx = i
			break
		endif
		let i += a:direction
	endwhile

	" カーソル移動できる行が見つかったか
	if idx > 0
		call win_execute(a:winid, 'call cursor(' . idx . ', 1) | normal! zz')
	endif
endfunction

"---------------------------------------------------------------
" ポップアップ内キー処理
"---------------------------------------------------------------
function! s:PopupFilter(winid, key) abort
	if a:key ==# 'q'			" 終了
		call popup_close(a:winid, -1)
		return 1

	elseif a:key ==# 'j'		" 下移動
		call s:GetNextcursorline(a:winid, 1)
		return 1

	elseif a:key ==# 'k'		" 上移動
		call s:GetNextcursorline(a:winid, -1)
		return 1

	elseif a:key ==# 'a'		" マークの追加
		call s:AddMark()
		call s:UpdatePopup(a:winid)
		return 1

	elseif a:key ==# "d"		" マークの削除
		call s:DeleteMark(a:winid)
		call s:UpdatePopup(a:winid)
		return 1

	elseif a:key ==# "e"		" マークの編集
		call s:EditMark(a:winid)
		call s:UpdatePopup(a:winid)
		return 1

	elseif a:key ==# "\<CR>"	" マーク位置にジャンプ
		call s:Jump(a:winid)
		return 1
	endif

	return popup_filter_menu(a:winid, a:key)
endfunction

"---------------------------------------------------------------
" マークの追加
"---------------------------------------------------------------
function! s:AddMark() abort
	" 現在行のマーク作成
	let file = expand('%:p')								" ファイル名
	let func = func#GetCurrentFunctionName()				" 関数名
	let lnum = line('.')									" 行番号
	let text = substitute(getline('.'), '\t', ' ', 'g')		" 関数名

	" キーの存在確認をしてから同一箇所のマークがある場合はまず削除する
	if has_key(s:Marks, file)
		" ラムダ式を使い、lnum が一致「しない」ものだけを残す（＝一致するものを削除）
		call filter(s:Marks[file], { idx, val -> val.lnum != lnum })
	endif

	" グループが無い場合は、作成する
	if !has_key(s:Marks, file)
		let s:Marks[file] = []
	endif

	" マークリストに追加
	call add(s:Marks[file], {'func':func, 'lnum':lnum, 'text':text})

	" マークファイルを保存
	call s:SaveMarkFile(s:Marks)
endfunction

"---------------------------------------------------------------
" マークの削除
"---------------------------------------------------------------
function! s:DeleteMark(winid) abort
	" 選択行から削除対象のファイル名と行番号を取得する
	let target = s:GetSelectMark(a:winid)

	" キーの存在確認をしてから削除処理を実行
	if has_key(s:Marks, target.file)
		" ラムダ式を使い、lnum が一致「しない」ものだけを残す（＝一致するものを削除）
		call filter(s:Marks[target.file], { idx, val -> val.lnum != target.lnum })

		" 要素削除後、リストが空（要素数が0）になった場合は、キー自体も連想配列から削除する
		if empty(s:Marks[target.file])
			unlet s:Marks[target.file]
		endif
	endif

	" マークファイルを保存
	call s:SaveMarkFile(s:Marks)
endfunction

"---------------------------------------------------------------
" マークの編集
"---------------------------------------------------------------
function! s:EditMark(winid) abort
	" 選択行から編集対象のファイル名と行番号を取得する
	let target = s:GetSelectMark(a:winid)

	" 選択項目を取得
	let v = (filter(deepcopy(s:Marks[target.file]), { idx, val -> val.lnum == target.lnum }))[0]
	if empty(v) | return | endif

	" 新しい関数名(タイトル)を入力
	let v.func = input('Function name: ', v.func)
	echo "\r"

	" 空白が入力またはキャンセルされた場合は終了
	if len(v.func) == 0 | return | endif

	" キーの存在確認をしてから一旦削除してから登録し直す
	if has_key(s:Marks, targeti.file)
		" ラムダ式を使い、lnum が一致「しない」ものだけを残す（＝一致するものを削除）
		call filter(s:Marks[target.file], { idx, val -> val.lnum != target.lnum })

		" 新しく追加する
		call add(s:Marks[target.file], v)
	endif

	" マークファイルを保存
	call s:SaveMarkFile(s:Marks)
endfunction

"---------------------------------------------------------------
" ジャンプ
"---------------------------------------------------------------
function! s:Jump(winid) abort
	" 選択行からジャンプ先ファイル名と行番号を取得する
	let target = s:GetSelectMark(a:winid)
	if empty(target.file) | return | endif

	call popup_close(a:winid)
	execute 'edit ' . fnameescape(target.file)
	execute target.lnum
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
