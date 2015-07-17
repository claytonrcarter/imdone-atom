{$, $$, $$$, ScrollView, TextEditorView} = require 'atom-space-pen-views'
{Emitter, Disposable, CompositeDisposable} = require 'atom'
ImdoneRepo = require 'imdone-core/lib/repository'
fsStore = require 'imdone-core/lib/mixins/repo-watched-fs-store'
path = require 'path'
util = require 'util'
require('./jq-utils')($)

module.exports =
class ImdoneAtomView extends ScrollView
  @content: (params) ->
    @div class: "imdone-atom pane-item", =>
      @div outlet: "loading", class: "imdone-loading", =>
        @h4 "Loading #{path.basename(params.path)} Issues."
        @h4 "It's gonna be legen... wait for it."
        # DONE:20 Update progress bar on repo load
        @progress class:'inline-block', outlet: "progress", max:100, value:1, style: "display:none;"
      @div outlet: "menu", class: "imdone-menu", =>
        @div click: "toggleMenu",  class: "imdone-menu-toggle", =>
          @span class: "icon icon-gear"
        @div class: "imdone-filter", =>
          # @input outlet:"filterField", type:"text", placeholder: "filter tasks" #, keyup: "onFilterKeyup"
          @subview 'filterField', new TextEditorView(mini: true, placeholderText: "filter tasks")
          @div click: "clearFilter", class:"icon icon-x clear-filter"
        @ul outlet: "lists", class: "lists"
      @div outlet: "boardWrapper", class: "imdone-board-wrapper", =>
        @div outlet: "board", class: "imdone-board"

  getTitle: ->
    "#{path.basename(@path)} Issues"

  getURI: ->
    @uri

  constructor: ({@path, @uri}) ->
    super
    @imdoneRepo = imdoneRepo = @getImdoneRepo()
    @handleEvents()
    imdoneRepo.on 'initialized', => @onRepoUpdate()
    imdoneRepo.on 'file.update', => @onRepoUpdate()
    imdoneRepo.on 'config.update', => imdoneRepo.refresh()

    imdoneRepo.fileStats ((err, files) ->
      if files.length > 1000
        @progress.show()
        imdoneRepo.on 'file.read', ((data) ->
          complete = Math.ceil (data.completed/imdoneRepo.files.length)*100
          @progress.attr 'value', complete
        ).bind(this)
    ).bind(this)

    # TODO:25 Maybe we need to check file stats first (For configuration)
    setTimeout (-> imdoneRepo.init()), 1000

  handleEvents: ->
    repo = @imdoneRepo

    @on 'click', '.source-link',  (e) =>
      link = e.target
      @openPath(link.dataset.uri, link.dataset.line)

    @on 'click', '.toggle-list', (e) =>
      target = e.target
      name = target.dataset.list || target.parentElement.dataset.list
      if (repo.getList(name).hidden)
        repo.showList name
      else repo.hideList name

    editor = @filterField.getModel()
    editor.onDidStopChanging () =>
      @filter editor.getText()

  toggleMenu: (event, element) ->
    @menu.toggleClass('open')
    @boardWrapper.toggleClass('shift')

  clearFilter: (event, element) ->
    @filterField.getModel().setText('')
    @board.find('.task').show()

  onFilterKeyup: (event, element) ->
    @filter @filterField.val()
    return true

  filter: (text) ->
    @lastFilter = text
    if text == ''
      @board.find('.task').show()
    else
      @board.find('.task').hide()
      @board.find(util.format('.task:regex(data-path,%s)', text)).show()
      @board.find(util.format('.task-full-text:containsRegex("%s")', text)).each( ->
        $(this).closest('.task').show()
      )

  getImdoneRepo: ->
    fsStore(new ImdoneRepo(@path))

  onRepoUpdate: ->
    @updateBoard()
    @updateMenu()

    @loading.hide()
    @menu.show()
    @boardWrapper.show();

  updateMenu: ->
    @lists.empty()

    repo = @imdoneRepo
    lists = repo.getLists()
    hiddenList = "hidden-list"

    getList = (list) ->
      $$ ->
        @li "data-list": list.name, =>
          @span class: "reorder icon icon-three-bars"
          @span class: "toggle-list  #{hiddenList if list.hidden}", "data-list": list.name, =>
            @span class: "icon icon-eye"
            @span "#{list.name} (#{repo.getTasksInList(list.name).length})"
            # DOING:10.5 Add delete list icon if length is 0

    elements = (-> getList list for list in lists)

    @lists.append elements

    $('.lists').sortable(
      items: "li"
      handle:".reorder"
      forcePlaceholderSize: true
    ).bind('sortupdate', (e, ui) ->
      name = ui.item.attr "data-list"
      pos = ui.item.index()
      repo.moveList name, pos
    )

  updateBoard: ->
    @board.empty()

    repo = @imdoneRepo
    lists = repo.getVisibleLists()
    width = 378*lists.length + "px"
    @board.css('width', width)
    # TODO:20 Add task drag and drop support

    getTask = (task) ->
      $$$ ->
        @div class: 'inset-panel padded task well', id: "#{task.id}", "data-path": task.source.path, =>
          @div class:'task-order', =>
            @span class: 'badge', task.order
          @div class: 'task-full-text hidden', =>
            @raw task.getText()
          @div class: 'task-text', =>
            @raw task.getHtml(stripMeta: true, stripDates: true)
          # DOING:10 Add todo.txt stuff like chrome app!
          @div class: 'task-context', task.getContext().join(',') if task.getContext()
          @div class: 'task-tags', task.getTags().join(',') if task.getTags()
          @div class: 'task-meta', =>
            @table =>
              for data in task.getMetaDataWithLinks(repo.getConfig())
                do (data) =>
                  @tr =>
                    @td data.key
                    if data.link
                      @td =>
                        @a href: data.link.url, title: data.link.title, data.value
                    else
                      @td data.value
                if task.getDateDue()
                  @tr =>
                    @td "due"
                    @td task.getDateDue()
                if task.getDateCreated()
                  @tr =>
                    @td "created"
                    @td task.getDateCreated()
                if task.getDateCompleted()
                  @tr =>
                    @td "completed"
                    @td task.getDateCompleted()
          @div class: 'task-source', =>
            @a class: 'source-link', 'data-uri': "#{repo.getFullPath(task.source.path)}",
            'data-line': task.line, "#{task.source.path + ':' + task.line}"

    getList = (list) ->
      $$ ->
        @div class: "top list well", =>
          @div class: 'panel', =>
            @div class: 'list-name well', list.name
            @div class: 'panel-body tasks', "data-list":"#{list.name}", =>
              @raw getTask(task) for task in repo.getTasksInList(list.name)

    elements = (-> getList list for list in lists)

    @board.append elements

  destroy: ->
    @detach()

  openPath: (filePath, line) ->
    return unless filePath

    atom.workspace.open(filePath, split: 'left').done =>
      @moveCursorTo(line)

  moveCursorTo: (lineNumber) ->
    lineNumber = parseInt(lineNumber)

    if textEditor = atom.workspace.getActiveTextEditor()
      position = [lineNumber-1, 0]
      textEditor.setCursorBufferPosition(position, autoscroll: false)
      textEditor.scrollToCursorPosition(center: true)
