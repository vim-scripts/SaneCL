""" ==============================================================
""" ==============================================================
""" SaneCL       - VimScript Common Lisp Indentation
"""
""" Maintainer   - Eric O'Connor <oconnore@gmail.com>
""" Last edit    - April 16, 2010
""" License      - Released under the VIM license
""" ==============================================================
""" ==============================================================

if exists("b:did_ftplugin")
   finish
endif
let b:did_ftplugin = 1

" ----------------------------------------------------------------

" SETTABLE FEATURES HANDLED HERE :
" g:CL_aggressive_literals
" g:CL_retab_on_open
" g:CL_lispwords_file
" g:CL_loop_keywords

" This will treat symbols beginning in [&':] as literals for indentation
" purposes
if !exists("g:CL_aggressive_literals")
   let CL_aggressive_literals=1
endif

" Automatic retab - useful if you switch from expandtab - noexpandtab
" (commonly emacs -> vim)
if !exists("g:CL_retab_on_open")
   let CL_retab_on_open=1
endif

" Do retab
if CL_retab_on_open==1
   retab!
endif

" where is the lispwords file default?
if !exists("g:CL_lispwords_file")
   let g:CL_lispwords_file="~/lispwords"
endif

if !exists("g:CL_loop_keywords")
   let CL_loop_keywords=["always","append","appending","as","collect","collecting","count","counting","do","doing","finally","for","loop","if","initially","loop-finish","maximize","maximizing","minimize","minimizing","named","nconc","nconcing","never","repeat","return","sum","summing","thereis","unless","until","when","while","with"]
endif

if !exists("g:CL_flets")
   let CL_flets=["flet","macrolet","labels"]
endif

if !exists("g:CL_auto_zero_limit")
   let CL_auto_zero_limit=25
endif

if !exists("g:CL_auto_prefixes")
   let CL_auto_prefixes=[["with-",1],["def",2],["make-",1],["map",1]]
endif

" -------------------------------------------------------

let b:undo_ftplugin = "call CLUndo()"

function! CLUndo()
   call Write_lispwords()
   delcommand CLLoadLispwords
   delcommand CLIndentForm
   delcommand CLIndentRange
   delcommand CLIndentLine
   delcommand CLSaveWords
   delcommand CLSetWord
   nunmap <buffer> <Tab>
   iunmap <buffer> <Tab>
   vunmap <buffer> <Tab>
   nunmap <buffer> <C-\>
   iunmap <buffer> <C-\>
   nunmap <buffer> o
   nunmap <buffer> O
   iunmap <buffer> <CR>
   let b:did_ftplugin=0
endfunction

" -------------------------------------------------------

function! Position()
   let wrap=&wrap
   set nowrap
   return [line("."),col("."),winline()-1,wrap]
endfunction

" -------------------------------------------------------

function! Fix_screen(pos)
   call cursor(a:pos[0]-a:pos[2],1)
   normal zt
   call cursor(a:pos[0],a:pos[1])
   if a:pos[3]
      set wrap
   endif
endfunction

" -------------------------------------------------------

function! Set_indent(line,ind)
   let current=getline(a:line)
   " Get previous indent
   let indent_size=match(current,"[^\n\t ]")
   if indent_size==-1
      let indent_size=strlen(current)
   endif
   " Cut off indentation whitespace
   let current=strpart(current,indent_size)
   let indent_size=indent(a:line)
   " Set according to vim rules
   if !&expandtab
      let tabs=a:ind / &tabstop
      let spaces=a:ind % &tabstop
      let line=repeat("\t",tabs).repeat(" ",spaces).current
   else
      let line=repeat(" ",a:ind).current
   endif
   " Commit and report changes
   call setline(a:line,line)
   return a:ind - indent_size
endfunction

" -------------------------------------------------------

function! Go_top()
   normal 150[(
   let pos=Position()
   return pos
endfunction

function! Go_match()
   normal %
   let pos=Position()
   return pos
endfunction

" -------------------------------------------------------

" parse lispwords file
function! Parse_lispwords(file)
   let dict={}
   try
      let words=readfile(glob(a:file))
      for i in words
	 let tmp=split(i," ")
	 let dict[tmp[0]]=tmp[1]
      endfor
   catch /E484:/
      echo "Lispwords file is unreadable."
   endtry
   return dict
endfunction

" and... parse
let s:lispwords=Parse_lispwords(g:CL_lispwords_file)

" -------------------------------------------------------

function! Write_lispwords()
   let lines=[]
   for i in items(s:lispwords)
      call add(lines,join(i," "))
   endfor
   try
      call writefile(lines,glob(g:CL_lispwords_file))
      echo "Wrote lispwords to ".g:CL_lispwords_file
   catch /E482:/
      echo "Cannot create file"
   endtry
endfunction

" -------------------------------------------------------

function! Set_lispword(word,num)
   let s:lispwords[a:word]=a:num
endfunction

" -------------------------------------------------------

" Parses a lisp block
function! Lisp_reader(pos_start,pos_end,lines)


   " script variables
   let s:lines=a:lines
   let s:start=a:pos_start[0]
   let s:end=a:pos_end[0]
   let s:offset=a:pos_start[1]
   let s:current_line=s:start
   let s:original_indent={}
   let s:original_indent[s:current_line]=indent(s:current_line)
   let s:line=getline(s:current_line)
   let s:stack=[]
   let s:recurse=[] " because in any other language this would be recursive...

   " functions
   " ---------------------------------------------------
   function! s:Get_next()
      let c=""
      if s:current_line <= s:end
         if s:offset >= strlen(s:line)
            let s:current_line+=1
            let s:offset=0
	    let s:original_indent[s:current_line]=indent(s:current_line)
            let s:line=getline(s:current_line)
            return "\n"
         else
            let c=strpart(s:line,s:offset,1)
            let s:offset+=1
         endif
      endif
      return c
   endfunction
   
   " ---------------------------------------------------

   function! s:Get_col()
      return s:offset
   endfunction!

   " ---------------------------------------------------

   function! s:Unget()
      if s:offset > 0
         let s:offset-=1
      else
         if s:offset==0 && s:current_line > s:start
            let s:current_line-=1
            let s:offset=0
         endif
      endif
   endfunction

   " ---------------------------------------------------

   function! s:Lisp_indent(line)

      " short circuit if necessary
      if len(s:lines)!=0 && index(s:lines,s:current_line) == -1
	 return 0
      endif

      let diff=indent(s:stack[0][1])-s:original_indent[s:stack[0][1]]

      let ind=0
      
      " Right now only used for loop indentation...
      let grabbed_line=getline(s:current_line)." "
      let grabbed_line=strpart(grabbed_line,match(grabbed_line,"[^ \t]"))

      " Test for a string parent
      if len(s:recurse)>0 && len(s:recurse[0])>0 && type(s:recurse[0][0]) == 1
         " Is the parent a literal?
	 if s:stack[0][3]=="literal" || (g:CL_aggressive_literals && strpart(s:recurse[0][0],0,1)=~"['&]") || s:recurse[0][0] =~ '[+-]\?\([0-9]\+\.\?[0-9]*\|[0-9]*\.\?[0-9]\+\)'
	    let ind=s:stack[0][2]
         " ---------------------
         " Explicit definitions
         " Parent is found in lispwords with zero+ indent
	 elseif has_key(s:lispwords,s:recurse[0][0]) && s:lispwords[s:recurse[0][0]]!=-1
            " Have we hit the lispword number?
	    if len(s:recurse[0])-1 < s:lispwords[s:recurse[0][0]]
	       let ind=s:stack[0][2]+3
	    else
	       let ind=s:stack[0][2]+1
	    endif
         " ---------------------
         " SPECIAL CASES :
         " ---------------------
         "  Level 1 comments
         elseif grabbed_line[0]==";" && grabbed_line[1]!=";"
            let ind=40
         " ---------------------
         "  Level 3+ comments
         elseif strpart(grabbed_line,0,3)==";;;"
            let ind=0
         " ---------------------
         " Indent loop form
         elseif s:recurse[0][0]=="loop"
            " get first symbol on line because
            " we haven't parsed this to the ast yet
            let loop_word=strpart(grabbed_line,0,max([0,match(grabbed_line,"[ \t]")]))
            " if the first word is a loop word, reduce indent by 2
            if index(g:CL_loop_keywords,loop_word) != -1
               let ind=s:stack[0][2]+2
            else
               let ind=s:stack[0][2]+4
            endif
         " ---------------------
         " Flet, labels, etc.
         elseif len(s:recurse) >= 3 && len(s:recurse[2]) > 0 && index(g:CL_flets,s:recurse[2][0]) != -1
            if len(s:recurse[0])-1 < 1
               let ind=s:stack[0][2]+3
            else
               let ind=s:stack[0][2]+1
            endif
         " --------------------------------------------
         " OK, now we have to calculate prefix matches
         " --------------------------------------------
         else
            let prefix_match=-1
            " Loop over potential prefixes
            for pref in g:CL_auto_prefixes
               if match(s:recurse[0][0],pref[0]) != -1
                  let prefix_match = pref[1]
                  break
               endif
            endfor
            " Did we find any?
            if prefix_match != -1
               " Have we hit the lispword number?
               if len(s:recurse[0])-1 < prefix_match
                  let ind=s:stack[0][2]+3
               else
                  let ind=s:stack[0][2]+1
               endif
            " ---------------------
            " END SPECIAL CASES
            " ---------------------
            " Subforms on same line as parent, indent to word length
            " NEW: unless word is too long (> CL_auto_word_limit). Set to -1
            " to disable
            elseif s:stack[0][4] >= 2 && (g:CL_auto_zero_limit == -1 || len(s:recurse[0][0]) <= g:CL_auto_zero_limit)
               let ind=s:stack[0][2]+strlen(s:recurse[0][0])+1
            " No subforms found on same line, indent normally
            else
               let ind=s:stack[0][2]+1
            endif
         endif
      " Parent is not a string, it is a list!
      else
	 let ind=s:stack[0][2]
      endif
      let ind+=diff
      if &expandtab==0
	 let ind+=((s:original_indent[s:stack[0][1]]/&tabstop)*(&tabstop-1))
      endif
      return Set_indent(a:line,ind)
   endfunction

   " -------------------------------------------------------

   let token=""
   let c="begin"

   let form=[]
   let state=1

   " loop to our bound or to EOF (c=="")
   while c!="" && (s:current_line < s:end || (s:current_line==s:end && s:offset < a:pos_end[1]))

      let c=s:Get_next()

      " whitespace breaks out unless we are in a macro
      if c=~"[\n \t]" && index([5,6,9,10,11],state)==-1

	 " handle token
         if token!=""
	    if len(s:recurse) > 0 && len(s:stack) > 0
	       " do we have multiple subforms on the first line?
	       if s:current_line==s:stack[0][1] || (s:current_line-1==s:stack[0][1] && c=="\n")
		  let s:stack[0][4]+=1
	       endif
	       call add(s:recurse[0],token)
	    else
	       call add(form,token)
	    endif
         endif

	 " do indentation!
	 if c=="\n" && len(s:stack) > 0
	    call s:Lisp_indent(s:current_line)
	 elseif c=="\n"
	    call Set_indent(s:current_line,0)
	 endif

         let token=""
         let state=1
         continue
      " end paren breaks out unless we are in a macro
      elseif c==")" && index([5,6,9,10,11],state)==-1
         if len(s:stack) > 0
	    " do we have multiple subforms on the first line?
	    if len(s:stack) > 1
	       if s:stack[0][1]==s:stack[1][1]
		  let s:stack[1][4]+=1
	       endif
	    endif
            call remove(s:stack,0)
            if token!=""
               call add(s:recurse[0],token)
            endif
            if len(s:recurse) > 1
               let tmp=remove(s:recurse,0)
               call add(s:recurse[0],tmp)
            else
               call add(form,remove(s:recurse,0))
            endif
         else
            echo "Parentheses error on ".s:current_line.",".s:offset
            if !exists("g:paren_error")
               let g:paren_error=[]
            endif
            call add(g:paren_error,[s:current_line,s:offset])
         endif
         let token=""
         let state=1
         continue
      endif

      " set to one if we accumulate a token
      let save=0

      " PARSE STATES
      " 0 = dump token
      " 1 = start
      " 2 = found literal
      " 3 = literal symbol
      " 4 = symbol
      " 5 = string
      " 6 = string
      " 7 = macro
      " 8 = macro 2
      " 9 = comment
      " 10 = multi-line comment
      " 11 = multi-line comment 2

      """"""""""""""""""""""""""""""""""""
      " STATE 1 - default
      if state==1 
         if c=~ "[(]"
            call insert(s:recurse,[])
            call insert(s:stack,["(",s:current_line,s:Get_col(),"eval",0])
            continue
         elseif c=="\""
            let state=5
            let save=1
         elseif c=="\\"
            let state=8
         elseif c=="#"
            let state=7
         elseif c==";"
            let state=9
         elseif c== "'"
            let state=2
            let save=1
         else
            let state=4
            let save=1
         endif
      """"""""""""""""""""""""""""""""""""
      " STATE 2 - handle literals
      elseif state==2
         if c=="("
            let token=""
            call insert(s:recurse,[])
            call insert(s:stack,["(",s:current_line,s:Get_col(),"literal",0])
            let state=1
            continue
         elseif c=~"[^\n\t ]"
            let save=1
            let state=3
         endif
      """"""""""""""""""""""""""""""""""""
      " STATES 3 & 4 - symbols
      elseif state==3 || state == 4
         if c=~"[^( \n\t]"
            let save=1
         else
            let state=0
            call s:Unget()
         endif
      """"""""""""""""""""""""""""""""""""
      " STATES 5 & 6 - string
      elseif state==5
         let save=1
         if c=="\""
            let state=0
         elseif c=="\\"
            let state=6
            let save=0
	 elseif c=="\n"
	    if s:current_line-1 == s:stack[0][1]
	       let s:stack[0][4]+=1
	    endif
         endif
      elseif state==6
         let save=1
         let state=5
      """"""""""""""""""""""""""""""""""""
      " STATE 7 - handle basic macros [char,simple vector and comment]
      elseif state==7
         if c=="|"
            let state=10
         elseif c=="\\"
            let state=8
         elseif c=="("
            call s:Unget()
            let state=1
         else
            let state=1
         endif
      """"""""""""""""""""""""""""""""""""
      " STATE 8 - escape
      elseif state==8
         let save=1
         let state=4
      """"""""""""""""""""""""""""""""""""
      " STATE 9 - comment
      elseif state==9
         if c=="\n"
            let state=1
	    
	    " do indentation!
	    if len(s:stack) > 0
	       call s:Lisp_indent(s:current_line)
	    else
	       call Set_indent(s:current_line,0)
	    endif
         endif
         " do nothing
      """"""""""""""""""""""""""""""""""""
      " STATES 10 & 11 - multiline comments
      elseif state==10
         if c=="|"
            let state=11
         endif
      elseif state==11
         if c=="#"
            let state=1
         else
            let state=10
         endif
      else
         throw "State switch overflow"
      endif
      " accumulate token
      if save
         let token.=c
      endif
      " a token has been accumulated
      if state==0
         if token!= ""
	    if len(s:recurse) > 0 && len(s:stack) > 0
	       " do we have multiple subforms on the first line?
	       if s:current_line==s:stack[0][1]
		  let s:stack[0][4]+=1
	       endif
	       call add(s:recurse[0],token)
	    else
	       call add(form,token)
	    endif
         endif
         let token=""
         let state=1
      endif
   endwhile

   if token != ""
      call add(form,token)
   endif

   let s:stack=[]
   let s:recurse=[] " because in any other language this would be recursive...
   let s:original_indent={}
   let s:memoize_line=-1

   "call garbagecollect()
   
   return form
endfunction

" -------------------------------------------------------

function! Indent_form()
   let pos=Position()
   let offset=match(getline(pos[0]),"[^\t\n ]")
   let top=Go_top()
   let top=[top[0],top[1]-1]
   let bot=Go_match()
   let bot=[bot[0]+1,0]
   call Lisp_reader(top,bot,[])
   let noffset=match(getline(pos[0]),"[^\t\n ]")
   let line=getline(pos[0])
   let match=match(line,"[^ \t]")
   if pos[1] >= match && match != -1
      let pos[1]=max([pos[1]+(noffset-offset),1])
   else
      if match==-1
	 let match=strlen(line)
      endif
      let pos[1]=max([1,match])
   endif
   call Fix_screen(pos)
endfunction

" -------------------------------------------------------

function! Indent_range(line1,line2)
   let pos=Position()
   let offset=match(getline(pos[0]),"[^\t\n ]")
   call Lisp_reader([a:line1,0],[a:line2,0],range(a:line1,a:line2))
   let noffset=match(getline(pos[0]),"[^\t\n ]")
   let line=getline(pos[0])
   let match=match(line,"[^ \t]")
   if pos[1] >= match && match != -1
      let pos[1]=max([pos[1]+(noffset-offset),1])
   else
      if match==-1
	 let match=strlen(line)
      endif
      let pos[1]=max([1,match])
   endif
   call Fix_screen(pos)
endfunction
   
" -------------------------------------------------------

function! Indent_line(count)
   let pos=Position()
   let offset=match(getline(pos[0]),"[^\t\n ]")
   "let top=Go_top()
   normal ^5[(
   let top=Position()
   if top[0]==pos[0] && top[1] == pos[1]
      if strpart(getline(top[0]),top[1]-1,1) != "("
         call Set_indent(top[0],0)
         return
      endif
   endif
   let top=[top[0],top[1]-1]
   let bot=[pos[0],0]
   call Lisp_reader(top,bot,range(pos[0],pos[0]+a:count-1))
   let noffset=match(getline(pos[0]),"[^\t\n ]")
   let line=getline(pos[0])
   let match=match(line,"[^ \t]")
   if pos[1] >= match && match != -1
      let pos[1]=max([pos[1]+(noffset-offset),1])
   else
      if match==-1
	 let match=strlen(line)
      endif
      let pos[1]=max([1,match])
   endif
   call Fix_screen(pos)
endfunction


" -------------------------------------------------------
" BINDINGS

" commands
command! -buffer CLLoadLispwords call Parse_lispwords(CL_lispwords_file)
command! -buffer CLIndentForm call Indent_form()
command! -buffer -range CLIndentRange call Indent_range(<line1>,<line2>)
command! -buffer -count=1 CLIndentLine call Indent_line(<count>)
command! -buffer CLSaveWords call Write_lispwords()
command! -buffer -nargs=+ CLSetWord call Set_lispword(<f-args>)

" indentation maps
nmap <buffer><silent> <Tab> :CLIndentLine<CR>
imap <buffer><silent> <Tab> <Esc>:CLIndentLine<CR>a
vmap <buffer><silent> <Tab> <Esc>:'<,'>CLIndentRange<CR>`<v`>
nmap <buffer><silent> <C-\> :CLIndentForm<CR>
imap <buffer><silent> <C-\> <Esc>:CLIndentForm<CR>a

" set a newline to proper indent (basic cases)
nnoremap <buffer><silent> o o<Esc>:CLIndentLine<CR>a
nnoremap <buffer><silent> O O<Esc>:CLIndentLine<CR>a
inoremap <buffer><silent> <CR> <CR><Esc>:CLIndentLine<CR>a

au! VimLeave *.lisp CLSaveWords

" -------------------------------------------------------
" Thanks for reading!
