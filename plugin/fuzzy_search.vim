vim9script noclear
# Vim plugin for opening a fuzzy file search buffer in the current window
# Last Change: 2025 Feb 19
# Maintainer: thepsauce
# License: This file is placed in the public domain.

if exists('g:loaded_fuzzy_search')
    finish
endif
g:loaded_fuzzy_seach = 1

# define a key bind for opening the fuzzy search
if !hasmapto('<Plug>FuzzySearchOpen;')
    map <unique> <Leader>a <Plug>FuzzySearchOpen;
endif

# define a map for opening the fuzzy search and a menu entry
if !hasmapto('<SID>Open')
    noremap <unique> <script> <Plug>FuzzySearchOpen; <SID>Open
    noremenu <script> Plugin.Open\ Fuzzy <SID>Open
    noremap <SID>Open :call <SID>Open()<CR>
endif

# when the fuzzy selection is re-entered, the old directory is shown
var current_fuzzy_directory = getcwd()

# default highlight groups
highlight default link FuzzySearchDirectory Type
highlight default link FuzzySearchFile Statement
highlight default link FuzzySearchItem Search

# Get a list of files within the given directory.
# Directories are marked with a trailing '/'.
def ListFiles(directory: string): list<string>
    var files = [ '../' ]

    for file in readdir(directory)
        var full_file = directory .. '/' .. file
        if isdirectory(full_file)
            full_file ..= '/'
        endif
        add(files, full_file[len(directory) + 1 : ])
    endfor

    return files
enddef

# Move the cursor to the given line
def GoToLine(line: number)
    var cursor = getpos('.')
    cursor[1] = line
    setpos('.', cursor)
enddef

# Go to the item with given index (only in normal mode).
def GoToItem(a_item: number)
    var item = a_item
    # Cap the item index
    if item < 0
        item = 0
    elseif item >= line('$') - 1
        item = max([ 0, line('$') - 2 ])
    endif

    # highlight the next selected item
    b:selected_item = item
    matchdelete(b:selected_item_highlight)
    b:selected_item_highlight = matchadd('FuzzySearchItem', '\%' .. (item + 2) .. 'l')
enddef

# Refilter all files and update the buffer.
def UpdateFileList()
    # the query is in the first line
    var query = getline(1)

    # filter the files with `matchfuzzy()`
    var filtered_files = b:files
    if query != ''
        filtered_files = matchfuzzy(b:files, query)
    endif

    var old_line_count = line('$')

    # efficiently replace the lines with the new file names
    setline(2, filtered_files)
    deletebufline('', len(filtered_files) + 2, line('$') + 1)

    if old_line_count != line('$') || b:old_query != query
        GoToItem(0)
    endif

    b:old_query = query
enddef

# Move into the given directory.
def MoveIntoDirectory(directory: string)
    # append the directory name and then resolve to handle '../'
    b:origin_directory = resolve(b:origin_directory .. '/' .. directory)

    # get the new files
    b:files = ListFiles(b:origin_directory)

    # set the "title"
    execute('file ' .. b:origin_directory)

    # clear the query
    setline(1, '')

    UpdateFileList()
enddef

# Open the file under the selected item.
def OpenSelectedFile()
    var name = getline(b:selected_item + 2)
    if name[-1 : ] == '/'
        MoveIntoDirectory(name)
    else
        current_fuzzy_directory = b:origin_directory
        execute('edit ' .. b:origin_directory .. '/' .. name)
        stopinsert
    endif
enddef

# Opens the next available directory if there is any.
def OpenNextDirectory()
    for i in range(1, line('$'))
        var file = getline(i)
        if file[-1 : ] == '/'
            MoveIntoDirectory(file)
            break
        endif
    endfor
enddef

# Open the old buffer again if still accessible.
def OpenOldBuffer()
    # open a new empty buffer if there is no previous buffer
    if b:previous_buffer == bufnr('') || bufname(b:previous_buffer) == ' '
        enew
    else
        execute('buffer ' .. b:previous_buffer)
    endif
enddef

# Removes all matches created in the window.
def DoCleanup()
    matchdelete(b:directory_highlight)
    matchdelete(b:file_highlight)
    matchdelete(b:selected_item_highlight)
enddef

# Show the fuzzy search buffer in the current window and set it up.
def Open(initial_directory: string = current_fuzzy_directory)
    var files = ListFiles(initial_directory)
    
    if empty(files)
        echo 'No files found.'
        return
    endif

    var previous_buffer = bufnr('')

    # make a new temporary buffer
    enew
    setlocal buftype=nofile
    setlocal bufhidden=wipe
    setlocal nobuflisted
    setlocal noswapfile

    # set the initial "title"
    execute('file ' .. initial_directory)

    # setup variables within the buffer
    b:previous_buffer = previous_buffer
    b:selected_item = 0
    b:origin_directory = initial_directory
    b:files = files
    b:old_query = ""

    # add the initial file names
    append(1, files)

    inoremap <buffer> <silent> / <C-O>:call <SID>OpenNextDirectory()<CR>
    inoremap <buffer> <silent> <CR> <C-O>:call <SID>OpenSelectedFile()<CR>
    inoremap <buffer> <silent> <Up> <Esc><Up>
    inoremap <buffer> <silent> <Down> <Esc><Down>

    nnoremap <buffer> <silent> <CR> :call <SID>OpenSelectedFile()<CR>
    # when pressing ESC in normal mode return to the old buffer (cancel operation)
    nnoremap <buffer> <silent> <ESC> :call <SID>OpenOldBuffer()<CR>

    # make some neat highlighting for file names and directory names
    b:directory_highlight = matchadd('FuzzySearchDirectory', '^[^/]*/$')
    b:file_highlight = matchadd('FuzzySearchFile', '^[^/]*$')
    b:selected_item_highlight = matchadd('FuzzySearchItem', '\%2l')

    autocmd InsertEnter <buffer> GoToLine(1) | v:char = ' '
    autocmd InsertLeave <buffer> GoToLine(b:selected_item + 2)

    # whenever the cursor is moved in normal mode, make the selected item
    # follow it
    autocmd CursorMoved <buffer> GoToItem(getpos('.')[1] - 2)

    # when any text is changed (usually the top query, buf also to clean up any
    # dirt the user might have accidentally produced)
    autocmd TextChangedI,TextChanged <buffer> UpdateFileList()

    # make sure to clean up the highlight matches
    autocmd BufUnload <buffer> DoCleanup()

    # start in insert mode so the user can type right away
    startinsert
enddef

# make a command for calling the `Open()` function
if !exists(":FuzzySearch")
    command -nargs=? FuzzySearch call Open(<args>)
endif
