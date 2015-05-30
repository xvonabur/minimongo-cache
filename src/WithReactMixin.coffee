createMixin = (db) ->
  Mixin =
    # TODO: support shouldComponentUpdate
    componentWillMount: ->
      @subscription = null;
      @_refresh()

    _refresh: ->
      if @subscription
        @subscription.dispose()

      @subscription = db.observe(@observeData)
      @subscription.subscribe @_setData

    _setData: (nextData, prevData) ->
      @data = nextData
      if prevData
        @forceUpdate()

    componentWillUpdate: (nextProps, nextState) ->
      prevProps = @props
      prevState = @state

      @props = nextProps
      @state = nextState
      try
        @_refresh()
      finally
        @props = prevProps
        @state = prevState

    componentWillUnmount: ->
      if @subscription
        @subscription.dispose()

WithReactMixin =
  getReactMixin: ->
    if not @mixin?
      @mixin = createMixin this
    return @mixin

module.exports = WithReactMixin
