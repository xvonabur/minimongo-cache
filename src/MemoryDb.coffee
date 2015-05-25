_ = require 'lodash'
utils = require('./utils')
processFind = require('./utils').processFind
{EventEmitter} = require 'events'
WithObservableQueries = require('./WithObservableQueries')

# TODO: use ImmutableJS (requires changing selector.js which will
# be painful)

module.exports = class MemoryDb extends EventEmitter
  constructor: ->
    @collections = {}

  addCollection: (name) ->
    if @[name]?
      return
    collection = new Collection(name, this)
    @[name] = collection
    @collections[name] = collection

_.mixin(MemoryDb.prototype, WithObservableQueries)

# Stores data in memory
class Collection
  constructor: (name, eventEmitter) ->
    @name = name
    @eventEmitter = eventEmitter

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
      item = _.clone(item)

      # Replace/add
      @items[item.doc._id] = item.doc
      @version += 1
      @versions[item.doc._id] = (@versions[item.doc._id] || 0) + 1
      @items[item.doc._id]._version = @versions[item.doc._id]
      @eventEmitter.emit('change', @name, {_id: item.doc._id, _version: item.doc._version})

    docs

  remove: (id) ->
    if _.has(@items, id)
      prev_version = @items[id]._version
      @version += 1
      delete @items[id]
      delete @versions[id]
      @eventEmitter.emit('change', @name, {_id: id, _version: prev_version + 1})
