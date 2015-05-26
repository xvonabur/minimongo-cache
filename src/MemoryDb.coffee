_ = require 'lodash'
utils = require('./utils')
processFind = require('./utils').processFind
{EventEmitter} = require 'events'
WithCreateQuery = require './WithCreateQuery'
WithObservableQueries = require('./WithObservableQueries')

# TODO: use ImmutableJS (requires changing selector.js which will
# be painful)

module.exports = class MemoryDb extends EventEmitter
  constructor: (alwaysAllowWrites) ->
    @alwaysAllowWrites = alwaysAllowWrites # for testing
    @collections = {}
    @emitQueue = null

  addCollection: (name) ->
    if @[name]?
      return
    collection = new Collection(name, this)
    @[name] = collection
    @collections[name] = collection

  write: (func, context) ->
    # TODO: this may be excessive
    if @emitQueue is not null
      throw new Error('Already in a Transaction')

    @emitQueue = []
    try
      func.call(context, this)
    finally
      emitQueue = @emitQueue
      @emitQueue = null

      emitQueue.reverse()
      emittedEvents = {}

      emitQueue.forEach (args) =>
        collectionName = args[1]
        fragment = args[2]
        key = collectionName + ':' + fragment._id
        if emittedEvents[key]
          return
        emittedEvents[key] = true
        @emit.apply(this, args)

  queueEmit: (args...) ->
    if not @emitQueue
      if @alwaysAllowWrites
        return
      throw new Error('Not in a write() block')

    @emitQueue.push args

_.mixin(MemoryDb.prototype, WithObservableQueries)
_.mixin(MemoryDb.prototype, WithCreateQuery)

# Stores data in memory
class Collection
  constructor: (name, db) ->
    @name = name
    @db = db

    @items = {}
    @versions = {}
    @version = 1

  find: (selector, options) ->
    return @_findFetch(selector, options)

  findOne: (selector, options) ->
    options = options or {}

    results = @find(selector, options)
    if results.length > 0 then results[0] else null

  _findFetch: (selector, options) ->
    processFind(@items, selector, options)

  get: (_id) -> @findOne(_id: _id)

  upsert: (docs, bases, success, error) ->
    [items, success, error] = utils.regularizeUpsert(docs, bases, success, error)

    for item in items
      # Shallow copy since MemoryDb adds _version to the document.
      # TODO: should we get rid of this mutation?
      doc = _.merge({}, @items[item.doc._id] || {}, item.doc)

      # Replace/add
      @items[item.doc._id] = doc
      @version += 1
      @versions[doc._id] = (@versions[doc._id] || 0) + 1
      @items[doc._id]._version = @versions[doc._id]
      @db.queueEmit('change', @name, {_id: doc._id, _version: doc._version})

    docs

  remove: (id) ->
    if _.has(@items, id)
      prev_version = @items[id]._version
      @version += 1
      delete @items[id]
      delete @versions[id]
      @db.queueEmit('change', @name, {_id: id, _version: prev_version + 1})
