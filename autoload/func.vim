let s:save_cpo = &cpoptions
set cpoptions&vim

"---------------------------------------------------------------
" C/C++ の関数名を取得する
"---------------------------------------------------------------
function! s:GetFuncName_C()
	let lnum = line('.')

	" 遡って関数定義箇所を探す
	while lnum > 0
		let line = getline(lnum)

		" コメント除去
		let s = substitute(line, '//.*$', '', '')
		let s = substitute(s, '/\*.*\*/', '', '')

		" 空行はスキップ または ; で終わる行は関数呼び出しなので除外する
		if s =~ '^\s*$' || s =~ ';\s*$'
			let lnum -= 1
			continue
		endif

		" -------------------------------
		" 関数定義パターン（関数呼び出しは除外）
		" -------------------------------
		" 条件:
		" 1. 行頭に戻り値（複数単語可）
		" 2. 関数名 (\k\+)
		" 3. 引数 (...)
		" 4. 行末が ; で終わらない（呼び出しは ; で終わる）
		let pat = '^\s*\(\k\+\s\+\)*\(\k\+\)\s*(.*)\s*\({\s*\)\?$'
		let m = matchlist(s, pat)
		if !empty(m)
			" m[2] が関数名
			return m[2]
		endif

		" -------------------------------
		" 戻り値と関数名が別行にあるパターン
		"	void
		"	sub3() {
		" -------------------------------
		if s =~ '^\s*\k\+\s*$'
			let next = getline(lnum + 1)
			let next2 = substitute(next, '//.*$', '', '')
			let next2 = substitute(next2, '/\*.*\*/', '', '')

			if next2 =~ '^\s*\(\k\+\)\s*(.*)'
				let m2 = matchlist(next2, '^\s*\(\k\+\)\s*(.*)')
				return m2[1]
			endif
		endif

		let lnum -= 1
	endwhile

	return 'unknown'
endfunction

"---------------------------------------------------------------
" Python用関数名取得
"---------------------------------------------------------------
function! s:GetFuncName_Python()
	let lnum = line('.')

	while lnum > 0
		let line = getline(lnum)

		" コメント除去
		let s = substitute(line, '#.*$', '', '')

		" 空行はスキップ
		if s =~ '^\s*$'
			let lnum -= 1
			continue
		endif

		" 関数定義パターン
		" def func(...):
		if s =~ '^\s*def\s\+\k\+\s*(.*):\s*$'
			return matchstr(s, 'def\s\+\zs\k\+')
		endif

		let lnum -= 1
	endwhile

	return 'unknown'
endfunction

"---------------------------------------------------------------
" vimスクリプト用関数名取得
"---------------------------------------------------------------
function! s:GetFuncName_Vim()
	let lnum = line('.')

	" 遡って関数定義箇所を探す
	while lnum > 0
		let line = getline(lnum)

		" コメント除去
		let s = substitute(line, '"\s.*$', '', '')

		" 空行はスキップ
		if s =~ '^\s*$'
			let lnum -= 1
			continue
		endif

		" function/function! の定義
		" function! s:samplefunc()
		" function MyPlugin#Sub#Func()
		" 関数名パターン:
		"	\%(\k\|:\|#\)\+
		"
		if s =~? '^\s*function!\?\s\+\%(\k\|:\|#\)\+'
			return matchstr(s, 'function!\?\s\+\zs\%(\k\|:\|#\)\+')
		endif

		let lnum -= 1
	endwhile

	return 'unknown'
endfunction

"---------------------------------------------------------------
" カーソル位置が属する関数名の取得
"---------------------------------------------------------------
function! func#GetCurrentFunctionName()
	if &filetype ==# 'python'
		return s:GetFuncName_Python()

	elseif &filetype =~# 'c'
		return s:GetFuncName_C()

	elseif &filetype =~# 'vim'
		return s:GetFuncName_Vim()

	else
		return 'unknown'
	endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
