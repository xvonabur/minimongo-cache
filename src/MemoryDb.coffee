_ = require 'lodash'
utils = require('./utils')
processFind = require('./utils').processFind
{EventEmitter} = require 'events'
WithObservableQueries = require './WithObservableQueries'

# TODO: use ImmutableJS (requires changing selector.js which will
# be painful)

class NullTransaction
  get: (collectionName, result, args...) -> result
  find: (collectionName, result, args...) -> result
  findOne: (collectionName, result, args...) -> result
  upsert: (collectionName, result, args...) ->
    throw new Error('Cannot write outside of a WriteTransaction')
  remove: (collectionName, result, args...) ->
    throw new Error('Cannot write outside of a WriteTransaction')
  canPushTransaction: (transaction) -> true

# TODO: move this to WithObservableQueries
class ReadTransaction extends NullTransaction
  constructor: ->
    @dirtyIds = {}
    @dirtyScans = {}
    @log = []

  _extractFragment: (doc) ->
    if not doc
      return null

    return {
      _id: doc._id,
      _version: doc._version,
    }

  get: (collectionName, result, _id) ->
    @dirtyIds[collectionName] = @dirtyIds[collectionName] || {}
    @dirtyIds[collectionName][_id] = true
    @log.push @_extractFragment(result)
    return result

  find: (collectionName, result) ->
    @dirtyScans[collectionName] = true
    @log.push result.map(@_extractFragment)
    return result

  findOne: (collectionName, result) ->
    @dirtyScans[collectionName] = true
    @log.push @_extractFragment(result)
    return result

  canPushTransaction: -> false

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

module.exports = class MemoryDb extends EventEmitter
  constructor: ->
    @collections = {}

    @transaction = new NullTransaction()

  addCollection: (name) ->
    if @[name]?
      return
    collection = new Collection(name, this)
    @[name] = collection
    @collections[name] = collection

  withTransaction: (transaction, func, context) ->
    if not @transaction.canPushTransaction(transaction)
      throw new Error('Already in a transaction')

    prevTransaction = @transaction
    @transaction = transaction
    try
      return func.call(context)
    finally
      @transaction = prevTransaction

  write: (func, context) ->
    transaction = new WriteTransaction()
    @withTransaction transaction, func, context
    # Emit change event at the end of the transaction
    changeRecords = {}
    for collectionName, ids of transaction.dirtyIds
      documentFragments = []
      for id of ids
        version = @collections[collectionName].versions[id]
        documentFragments.push {_id: id, _version: version}
      changeRecords[collectionName] = documentFragments
    @emit 'change', changeRecords

  read: (func, context) ->
    transaction = new ReadTransaction()
    rv = @withTransaction transaction, func, context
    return {
      transaction: transaction,
      value: rv
    }

_.mixin MemoryDb.prototype, WithObservableQueries

# Stores data in memory
class Collection
  constructor: (name, db) ->
    @name = name
    @db = db

    @items = {}
    @versions = {}
    @version = 1

  find: (selector, options) ->
    return @db.transaction.find(
      @name,
      @_findFetch(selector, options),
      selector,
      options
    )

  findOne: (selector, options) ->
    return @db.transaction.findOne(
      @name,
      @_findOne(selector, options),
      selector,
      options
    )

  _findOne: (selector, options) ->
    options = options or {}

    results = @_findFetch(selector, options)
    return if results.length > 0 then results[0] else null

  _findFetch: (selector, options) ->
    processFind(@items, selector, options)

  get: (_id) ->
    return @db.transaction.get @name, @_findOne(_id: _id), _id

  upsert: (docs) ->
    [items, _1, _2] = utils.regularizeUpsert(docs)

    for item in items
      # Shallow copy since MemoryDb adds _version to the document.
      # TODO: should we get rid of this mutation?
      doc = _.merge({}, @items[item.doc._id] || {}, item.doc)

      # Replace/add
      @items[item.doc._id] = doc
      @version += 1
      @versions[doc._id] = (@versions[doc._id] || 0) + 1
      @items[doc._id]._version = @versions[doc._id]

    return @db.transaction.upsert @name, docs, docs

  remove: (id) ->
    if _.has(@items, id)
      prev_version = @items[id]._version
      @version += 1
      @versions[id] = prev_version + 1
      delete @items[id]
    @db.transaction.remove @name, null, id
