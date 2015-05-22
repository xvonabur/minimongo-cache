_ = require 'lodash'
utils = require('./utils')
processFind = require('./utils').processFind

# TODO: use ImmutableJS (requires changing selector.js which will
# be painful)

module.exports = class MemoryDb
  constructor: (options, success) ->
    @collections = {}

    if success then success(this)

  addCollection: (name, success, error) ->
    collection = new Collection(name)
    @[name] = collection
    @collections[name] = collection
    if success? then success()

  removeCollection: (name, success, error) ->
    delete @[name]
    delete @collections[name]
    if success? then success()

# Stores data in memory
class Collection
  constructor: (name) ->
    @name = name

    @items = {}
    @removes = {}  # Pending removes by _id. No longer in items
    @versions = {}

  find: (selector, options) ->
    return fetch: (success, error) =>
      @_findFetch(selector, options, success, error)

  findOne: (selector, options, success, error) ->
    if _.isFunction(options)
      [options, success, error] = [{}, options, success]

    @find(selector, options).fetch (results) ->
      if success? then success(if results.length>0 then results[0] else null)
    , error

  _findFetch: (selector, options, success, error) ->
    if success? then success(processFind(@items, selector, options))

  upsert: (docs, bases, success, error) ->
    [items, success, error] = utils.regularizeUpsert(docs, bases, success, error)

    for item in items
      # Keep independent copies
      item = _.cloneDeep(item)

      # Replace/add
      @items[item.doc._id] = item.doc
      @versions[item.doc._id] = (@versions[item.doc._id] || 0) + 1
      @items[item.doc._id]._version = @versions[item.doc._id]

    if success then success(docs)

  remove: (id, success, error) ->
    if _.has(@items, id)
      @removes[id] = @items[id]
      delete @items[id]
      delete @versions[id]
    else
      @removes[id] = { _id: id }

    if success? then success()
