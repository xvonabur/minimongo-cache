{EventEmitter} = require 'events'
NullTransaction = require './NullTransaction'

_ = require 'lodash'

class WriteTransaction extends NullTransaction
  constructor: ->
    @dirtyIds = {}

  upsert: (collectionName, result, docs) ->
    docs = [docs] if not Array.isArray(docs)
    @dirtyIds[collectionName] = @dirtyIds[collectionName] || {}
    docs.forEach (doc) =>
      @dirtyIds[collectionName][doc._id] = true
    return result

  remove: (collectionName, result, id) ->
    @dirtyIds[collectionName] = @dirtyIds[collectionName] || {}
    @dirtyIds[collectionName][id] = true
    return result

  canPushTransaction: -> false

WithObservableWrites =
  write: (func, context) ->
    transaction = new WriteTransaction()
    try
      @withTransaction transaction, func, context
    finally
      # Emit change event at the end of the transaction
      changeRecords = {}
      for collectionName, ids of transaction.dirtyIds
        documentFragments = []
        for id of ids
          version = @collections[collectionName].versions[id]
          documentFragments.push {_id: id, _version: version}
        changeRecords[collectionName] = documentFragments
      @emit 'change', changeRecords

_.mixin WithObservableWrites, EventEmitter.prototype

module.exports = WithObservableWrites
