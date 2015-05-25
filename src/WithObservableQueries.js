'use strict';

// An (OOP) mixin/trait for supporting react-future-style observable queries

function LoggingCollection(collection) {
  this.collection = collection;

  this.numFinds = 0;
  this.gets = {};
  this.fetchLog = [];
  this.identityKey = null;
}

LoggingCollection.prototype.logFetch = function(name, params, results) {
  this.fetchLog.push([name, params, results.map(function(result) {
    return {
      _id: result._id,
      _version: result._version,
    };
  })]);
};

LoggingCollection.prototype.find = function(selector, options) {
  this.ensureNotCompleted();
  this.numFinds++;
  var results = this.collection.find(selector, options);
  this.logFetch('find', [selector, options], results);
  return results;
};

LoggingCollection.prototype.findOne = function(selector, options) {
  this.ensureNotCompleted();
  this.numFinds++;
  var result = this.collection.findOne(selector, options);
  this.logFetch('findOne', [selector, options], [result]);
  return result;
};

LoggingCollection.prototype.get = function(_id) {
  this.ensureNotCompleted();
  this.gets[_id] = true;
  var result = this.collection.get(_id);
  this.logFetch('get', [_id], [result]);
  return result;
};

LoggingCollection.prototype.complete = function() {
  this.identityKey = this.fetchLog;
};

LoggingCollection.prototype.ensureNotCompleted = function() {
  if (this.identityKey) {
    throw new Error('This ObservableDb is no longer active.');
  }
};

function ObservableDb(db) {
  this.collections = {};
  this.identityKey = null;

  for (var collectionName in db.collections) {
    this.collections[collectionName] = new LoggingCollection(db.collections[collectionName]);
    this[collectionName] = this.collections[collectionName];
  }
}

ObservableDb.prototype.complete = function() {
  var identityKeys = {};
  for (var collectionName in this.collections) {
    this.collections[collectionName].complete();
    identityKeys[collectionName] = this.collections[collectionName].identityKey;
  }
  this.identityKey = JSON.stringify(identityKeys);
};

function ObservableQuery(db, func) {
  this.db = db;
  this.func = func;

  this.subscribers = [];
  this.changeListener = this.changeListener.bind(this);
  this.lastObservableDb = null;

  this.db.on('change', this.changeListener);
}

ObservableQuery.prototype.subscribe = function(cb) {
  if (this.subscribers.indexOf(cb) > 0) {
    throw new Error('Already subscribed');
  }
  this.subscribers.push(cb);
  this.notify();
};

ObservableQuery.prototype.dispose = function(cb) {
  var index = this.subscribers.indexOf(cb);
  if (index === -1) {
    throw new Error('Not subscribed');
  }
  this.subscribers.splice(index, 0);
  this.db.removeListener('change', this.changeListener);
};

ObservableQuery.prototype.notify = function() {
  var lastObservableDb = this.lastObservableDb;
  var nextObservableDb = new ObservableDb(this.db);
  try {
    var rv = this.func(nextObservableDb);
  } catch (e) {
    return;
  } finally {
    nextObservableDb.complete();
    this.lastObservableDb = nextObservableDb;
  }

  if (!lastObservableDb || nextObservableDb.identityKey !== lastObservableDb.identityKey) {
    this.subscribers.forEach(function(subscriber) {
      subscriber(rv);
    });
  }
};

ObservableQuery.prototype.changeListener = function(collectionName, documentFragment) {
  if (this.lastObservableDb === null) {
    this.notify();
    return;
  }

  if (this.lastObservableDb.collections[collectionName].numFinds > 0) {
    this.notify();
    return;
  }

  if (this.lastObservableDb.collections[collectionName].gets[documentFragment._id]) {
    this.notify();
    return;
  }
};

var WithObservableQueries = {
  query: function(func) {
    return new ObservableQuery(this, func);
  },
};

module.exports = WithObservableQueries;
