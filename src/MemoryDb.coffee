_ = require 'lodash'
utils = require('./utils')
processFind = require('./utils').processFind
{EventEmitter} = require 'events'

# TODO: use ImmutableJS (requires changing selector.js which will
# be painful)

module.exports = class MemoryDb
  constructor: ->
    @collections = {}

  addCollection: (name) ->
    if @[name]?
      return
    collection = new Collection(name)
    @[name] = collection
    @collections[name] = collection

# Stores data in memory
class Collection extends EventEmitter
  constructor: (name) ->
    @name = name

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
      # Keep independent copies
      item = _.cloneDeep(item)

      # Replace/add
      @items[item.doc._id] = item.doc
      @version += 1
      @versions[item.doc._id] = (@versions[item.doc._id] || 0) + 1
      @items[item.doc._id]._version = @versions[item.doc._id]
      @emit('change', {_id: item.doc._id, _version: item.doc._version})

    docs

  remove: (id) ->
    if _.has(@items, id)
      prev_version = @items[id]._version
      @version += 1
      delete @items[id]
      delete @versions[id]
      @emit('change', {_id: id, _version: prev_version + 1})
