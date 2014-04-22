Steam.ScoringView = (_, _scoring) ->
  _items = nodes$ []
  _hasExecuted = node$ no
  _comparisonTable = node$ null
  _hasComparisonTable = lift$ _comparisonTable, (table) -> not isNull table
  _modelSummary = node$ null

  createModelSummary = (scoring) ->
    aScore = if scoring.scores.length > 0 then head scoring.scores else null
    if aScore
      [ dl, li, dt, dd ] = geyser.generate '.y-summary .y-summary-item .y-summary-key .y-summary-value'
      dl [
        li [
          dt 'Model Category'
          dd aScore.model.model_category
        ]
        li [
          dt 'Response Column'
          dd aScore.model.response_column_name
        ]
      ]
    else
      null

  createItem = (score) ->
    status = node$ if isNull score.status then '-' else score.status
    isSelected = lift$ status, (status) -> status is 'done'

    data: score
    algorithm: score.model.model_algorithm
    category: score.model.model_category
    responseColumn: score.model.response_column_name
    status: status
    time: node$ if isNull score.time then '-' else score.time
    canSelect: lift$ status, (status) -> status is 'done'
    isSelected: isSelected
    result: node$ score.result

  initialize = (scoring) ->
    _modelSummary createModelSummary scoring
    _items items = map scoring.scores, createItem
    if (every scoring.scores, (score) -> score.status is null)
      scoreModels scoring, items, ->
        forEach items, (item) ->
          apply$ item.isSelected, -> displayComparisonTable() if _hasExecuted()
        _hasExecuted yes
        displayComparisonTable()
    else
      _hasExecuted yes
      displayComparisonTable()

  runScoringJobs = (jobs, go) ->
    queue = copy jobs
    runNext = ->
      if job = shift queue
        job.run -> defer runNext
      else
        go()
    defer runNext

  scoreModels = (scoring, items, go) ->
    frameKey = scoring.frameKey
    jobs = map items, (item) ->
      modelKey = item.data.model.key
      item.status 'waiting'
      run: (go) ->
        item.status 'running'
        _.requestScoringOnFrame frameKey, modelKey, (error, result) ->
          data = if error then error.data else result
          item.status data.response.status
          item.time data.response.time
          item.result error or result
          do go

    runScoringJobs jobs, ->
      forEach items, (item) ->
        score = item.data
        score.status = item.status()
        score.time = item.time()
        score.result = item.result()

      go()

  displayComparisonTable = () ->
    selectedItems = filter _items(), (item) -> item.canSelect() and item.isSelected()
    renderComparisonTable map selectedItems, (item) -> item.data

  renderComparisonTable = (scores) ->
    [ table, kvtable, thead, tbody, tr, th, td ] = geyser.generate 'table.table.table-condensed table.table-kv thead tbody tr th td'

    transposeGrid = (grid) ->
      transposed = []
      for row, i in grid
        for cell, j in row
          column = transposed[j] or transposed[j] = []
          column[i] = cell
      transposed

    createParameterTable = (parameters) ->
      kvtable [
        tbody mapWithKey parameters, (value, key) ->
          tr [
            th key
            td value
          ]
      ]

    createROCChart = (data) ->
      margin = top: 20, right: 20, bottom: 20, left: 30
      width = 175
      height = 175

      x = d3.scale.linear()
        .domain [ 0, 1 ]
        .range [ 0, width ]

      y = d3.scale.linear()
        .domain [ 0, 1 ]
        .range [ height, 0 ]

      axisX = d3.svg.axis()
        .scale x
        .orient 'bottom'
        .ticks 5

      axisY = d3.svg.axis()
        .scale y
        .orient 'left'
        .ticks 5

      line = d3.svg.line()
        .x (d) -> x d.fpr
        .y (d) -> y d.tpr

      el = document.createElementNS 'http://www.w3.org/2000/svg', 'svg'

      svg = (d3.select el)
        .attr 'class', 'y-roc-curve'
        .attr 'width', width + margin.left + margin.right
        .attr 'height', height + margin.top + margin.bottom
        .append 'g'
        .attr 'transform', "translate(#{margin.left},#{margin.top})"
      
      svg.append 'g'
        .attr 'class', 'x axis'
        .attr 'transform', "translate(0, #{height})"
        .call axisX
        .append 'text'
        .attr 'x', width
        .attr 'y', -6
        .style 'text-anchor', 'end'
        .text 'FPR'

      svg.append 'g'
        .attr 'class', 'y axis'
        .call axisY
        .append 'text'
        .attr 'transform', 'rotate(-90)'
        .attr 'y', 6
        .attr 'dy', '.71em'
        .style 'text-anchor', 'end'
        .text 'TPR'

      svg.append 'line'
        .attr 'class', 'guide'
        .attr 'stroke-dasharray', '3,3'
        .attr
          x1: x 0
          y1: y 0
          x2: x 1
          y2: y 1

      svg.selectAll '.dot'
        .data data
        .enter()
        .append 'circle'
        .attr 'class', 'dot'
        .attr 'r', 1
        .attr 'cx', (d) -> x d.fpr
        .attr 'cy', (d) -> y d.tpr

      svg.append 'path'
        .datum data
        .attr 'class', 'line'
        .attr 'd', line

      el

    computeTPRandFPR = (cm) ->
      [[tn, fp], [fn, tp]] = cm

      tpr: tp / (tp + fn)
      fpr: fp / (fp + tn)

    createROC = (cms) ->
      rates = map cms, computeTPRandFPR
      createROCChart rates


    createComparisonGrid = (scores) ->
      header = [
        'Method'
        'Name'
        'Input Parameters'
        'Error'
        'AUC'
        'Threshold Criterion'
        'Threshold'
        'F1'
        'Accuracy'
        'Precision'
        'Recall'
        'Specificity'
        'Max per class Error'
        'ROC Curve'
      ]

      format4f = d3.format '.4f' # precision = 4

      scoreWithLowestError = min scores, (score) -> score.result.metrics.error

      rows = map scores, (score) ->
        model = score.model
        metrics = score.result.metrics
        auc = metrics.auc.members
        cm = metrics.cm.members
        errorBadge = if scores.length > 1 and score is scoreWithLowestError then ' (Lowest)' else ''
        [
          model.model_algorithm
          model.key
          model.parameters
          (format4f metrics.error) + errorBadge #TODO change to bootstrap badge
          format4f auc.AUC
          head auc.threshold_criteria
          head auc.threshold_for_criteria
          format4f head auc.F1_for_criteria
          format4f head auc.accuracy_for_criteria
          format4f head auc.precision_for_criteria
          format4f head auc.recall_for_criteria
          format4f head auc.specificity_for_criteria
          format4f head auc.max_per_class_error_for_criteria
          createROC auc.confusion_matrices
        ]

      unshift rows, header
      rows

    renderTable = (grid) ->
      table tbody map grid, (row, i) ->
        tr map row, (cell, i) ->
          if i is 0
            th cell
          else
            if isElement cell
              td cell
            else if isObject cell
              td createParameterTable cell
            else
              td cell


    _comparisonTable if scores.length > 0 then renderTable transposeGrid createComparisonGrid scores else null


  initialize _scoring

  items: _items
  modelSummary: _modelSummary
  hasExecuted: _hasExecuted
  comparisonTable: _comparisonTable
  hasComparisonTable: _hasComparisonTable
  caption: "Scoring on #{_scoring.frameKey}"
  timestamp: new Date(_scoring.timestamp).toString()
  template: 'scoring-view'
