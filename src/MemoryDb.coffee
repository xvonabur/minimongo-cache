NullTransaction = require './NullTransaction'
WithObservableReads = require './WithObservableReads'
WithObservableWrites = require './WithObservableWrites'

_ = require 'lodash'
utils = require('./utils')
processFind = require('./utils').processFind

class VersionMismatch extends Error

# TODO: use ImmutableJS (requires changing selector.js which will
# be painful)

module.exports = class MemoryDb
  constructor: ->
    @collections = {}

    @transaction = @getDefaultTransaction()

  getDefaultTransaction: -> new NullTransaction()

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

_.mixin MemoryDb.prototype, WithObservableReads
_.mixin MemoryDb.prototype, WithObservableWrites
MemoryDb.VersionMismatch = VersionMismatch

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

  _throwIfVersionMismatch: (prevVersion, nextVersion) ->
    if not prevVersion?
      return
    if not nextVersion?
      return
    if prevVersion + 1 != nextVersion
      throw new VersionMismatch('Version mismatch: ' + prevVersion + ' ' + nextVersion)

  get: (_id) ->
    return @db.transaction.get @name, @_findOne(_id: _id), _id

  upsert: (docs) ->
    [items, _1, _2] = utils.regularizeUpsert(docs)

    for item in items
      @_throwIfVersionMismatch @versions[item.doc._id], item.doc._version

      # Shallow copy since MemoryDb adds _version to the document.
      # TODO: should we get rid of this mutation?
      doc = _.merge({}, @items[item.doc._id] || {}, item.doc)

      # Replace/add
      @items[item.doc._id] = doc
      @version += 1
      @versions[doc._id] = (@versions[doc._id] || 0) + 1
      @items[doc._id]._version = @versions[doc._id]

    return @db.transaction.upsert @name, docs, docs

  remove: (id, version) ->
    if _.has(@items, id)
      prev_version = @items[id]._version
      @_throwIfVersionMismatch prev_version, version
      @version += 1
      @versions[id] = prev_version + 1
      delete @items[id]
    @db.transaction.remove @name, null, id
