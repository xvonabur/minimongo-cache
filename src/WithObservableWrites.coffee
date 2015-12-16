EventEmitter = require 'eventemitter3'
NullTransaction = require './NullTransaction'

_ = require 'lodash'

class ReadOnlyTransaction extends NullTransaction
  upsert: ->
    throw new Error('You cannot upsert() during the result of a reactive update')

  del: ->
    throw new Error('You cannot upsert() during the result of a reactive update')

  canPushTransaction: (transaction) -> !(transaction instanceof WriteTransaction)


class WriteTransaction extends NullTransaction
  constructor: (@db) ->
    @dirtyIds = {}
    @queued = false
    @traces = {}

  _ensureQueued: ->
    if @db.debug
      @traces[new Error().stack.split('\n').slice(1).join('\n')] = true

    if not @queued
      @queued = true
      process.nextTick => @_flush()

  upsert: (collectionName, result, docs) ->
    docs = [docs] if not Array.isArray(docs)
    @dirtyIds[collectionName] = @dirtyIds[collectionName] || {}
    docs.forEach (doc) =>
      @dirtyIds[collectionName][doc._id] = true
    @_ensureQueued()
    return result

  del: (collectionName, result, id) ->
    @dirtyIds[collectionName] = @dirtyIds[collectionName] || {}
    @dirtyIds[collectionName][id] = true
    @_ensureQueued()
    return result

  canPushTransaction: (transaction) -> true # nested writes would be bad, but impossible.

  _flush: ->
    changeRecords = {}
    for collectionName, ids of @dirtyIds
      documentFragments = []
      for id of ids
        version = @db.collections[collectionName].versions[id]
        documentFragments.push {_id: id, _version: version}
      changeRecords[collectionName] = documentFragments
    @dirtyIds = {}
    @queued = false

    @db.withTransaction new ReadOnlyTransaction(), =>
      if @db.debug
        traces = @traces
        @traces = {}
        try
          @db.emit 'change', changeRecords
        catch e
          for trace of traces
            e.stack += '\nFrom previous event:\n' + trace
          @db.uncaughtExceptionHandler(e)
      else
        try
          @db.emit 'change', changeRecords
        catch e
          @db.uncaughtExceptionHandler(e)


WithObservableWrites =
  getDefaultTransaction: ->
    @setMaxListeners 0
    return new WriteTransaction(this)

_.mixin WithObservableWrites, EventEmitter.prototype

module.exports = WithObservableWrites
