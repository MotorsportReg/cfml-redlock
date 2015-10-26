component {

	property numeric driftFactor;
	property numeric retryCount;
	property numeric retryDelay;

	function init (required array clients, struct options = {}) {

		variables.unlockScript = 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end';
		variables.extendScript = 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("pexpire", KEYS[1], ARGV[2]) else return 0 end';

		//defaults
		variables.driftFactor = 0.01;
		variables.retryCount = 3;
		variables.retryDelay = 200;

		//todo: better validation ranges for these options?
		if (!isNull(options.driftFactor) && isNumeric(options.driftFactor) && options.driftFactor >= 0) {
			driftFactor = options.driftFactor;
		}

		if (!isNull(options.retryCount) && isNumeric(options.retryCount) && options.retryCount >= 0) {
			retryCount = options.retryCount;
		}

		if (!isNull(options.retryDelay) && isNumeric(options.retryDelay) && options.retryDelay >= 0) {
			retryDelay = options.retryDelay;
		}

		if (!arrayLen(clients)) {
			throw(message="cfml-redlock must be instantiated with at least one client (redis server)");
		}

		variables.servers = clients;

		for (var srv in servers) {
			extendCFRedis(srv);
		}

		return this;
	}

	function getDriftFactor () {
		return driftFactor;
	}

	function getRetryCount () {
		return retryCount;
	}

	function getRetryDelay () {
		return retryDelay;
	}

	function lock (string resource, numeric ttl, any callback) {
		return _lock(resource, getNull(), ttl, callback);
	}

	function aquire (string resource, numeric ttl, any callback) {
		lock(resource, ttl, callback);
	}

	function unlock (lock, callback) {
		if (lock.expiration < unixtime()) {
			//lock has expired
			return callback(false, '');
		}

		lock.expiration = 0;

		var waiting = arrayLen(servers);

		var loop = function (err, response) {
			if (err) throw(err);
			if (waiting -- > 1) return;
			return response;
		};

		for (var srv in servers) {
			srv.evalWithCallback(unlockScript, lock.resource, lock.value, loop);
		}
	}

	function release (lock, callback) {
		unlock(lock, callback);
	}

	function extend (lock, ttl, callback) {
		if (lock.expiration < unixtime()) {
			throw(message="Cannot extend lock on resource " & lock.resource & " because the lock has already expired");
		}

		return _lock(lock.resource, lock.value, ttl, callback);

		//there was some extra stuff in the node library here that I think is unecessary...
		//https://github.com/mike-marcacci/node-redlock/blob/master/redlock.js#L186
		//making note in case im wrong
	}

	function _lock (string resource, any value = getNull(), numeric ttl, callback) {

		var request = "";
		var attempts = 0;

		if (isNull(value)) {
			//create a lock
			value = _random();
			request = function (srv, loop) {
				return srv.setNxPx(resource, value, ttl, loop);
			};
		} else {
			//extend a lock
			request = function (srv, loop) {
				return srv.evalWithCallback(extendScript, [resource], [value, ttl], loop);
			};
		}

		var attempt = function() {
			attempts++;

			var start = unixtime();
			var votes = 0;
			var quorum = int(arrayLen(servers) / 2) + 1;
			var waiting = arrayLen(servers);

			var loop = function (err, response) {
				if (err) {
					throw(err); //todo: call callback with err;
				}
				if (!isNull(response) && len(response)) {
					votes++;
				}
				if (waiting-- > 1) {
					return;
				}

				// Add 2 milliseconds to the drift to account for Redis expires precision, which is 1 ms,
				// plus the configured allowable drift factor
				var drift = round(driftFactor * ttl) + 2;
				var lock = _makeLock(this, resource, value, start + ttl - drift);

				// SUCCESS: there is consensus and the lock is not expired
				if(votes >= quorum && lock.expiration > unixtime()) {
					return callback(false, lock);
				}

				// remove this lock from servers that voted for it
				return lock.unlock(function(){
					// RETRY
					if(attempts <= retryCount) {
						sleep(retryDelay);
						return attempt();
					}

					// FAILED
					//return reject(new LockError('Exceeded ' + self.retryCount + ' attempts to lock the resource "' + resource + '".'));
					return callback({message: "Exceeded " & retryCount & " attempts to lock the resource " & resource}, getNull());
				});

			};

			for (var srv in servers) {
				request(srv, loop);
			}
		};

		attempt();

	}

	private function getNull () {
		return javaCast("null", 0);
	}

	private boolean function isCallback (callback) {
		return isCustomFunction(fn) || isClosure(fn);
	}

	private string function _random () {
		//return hash(rand("SHA1PRNG"), "sha1");
		return createUUID();
	}

	private numeric function unixtime () {
		return createObject("java", "java.lang.System").currentTimeMillis();
	}

	private struct function _makeLock (redlock, resource, value, expiration) {

		var l = {
			redlock: redlock,
			resource: resource,
			value: value,
			expiration: expiration,
			unlock: function (callback) {
				if (isNull(callback)) {
					callback = function(){};
				}
				l.redlock.unlock(l, callback);
			},
			extend: function (ttl, callback) {
				if (isNull(callback)) {
					callback = function(){};
				}
				l.redlock.extend(l, ttl, callback);
			}
		};

		return l;

	}

	private function __setNxPx (key, value, ttlms, callback) {

		var conn = getResource();

		//var params = createObject("java", "redis.clients.jedis.params.set.SetParams").init();
		//params.nx().px(JavaCast("long", ttlms));

		var result = conn.set(JavaCast("String", key), JavaCast("String", value), JavaCast("String", "NX"), JavaCast("String", "PX"), JavaCast("long", ttlms));

		returnResource(conn);

		if (isNull(result)) {
			result = '';
		}

		if (!isnull(callback)) {
			return callback(false, result);
		}

		return result;
	}

	private function __evalWithCallback (script, keys, args, callback) {

		if (!isArray(keys)) {
			keys = [keys];
		}

		if (!isArray(args)) {
			args = [args];
		}

		var conn = getResource();
		var result = conn.eval(JavaCast("string", script), keys, args);
		returnResource(conn);

		if (isNull(result)) {
			result = '';
		}

		if (!isnull(callback)) {
			return callback(false, result);
		}

		return result;
	}

	private function __inject (required string name, required any f, required boolean isPublic) {
		if (isPublic) {
			this[name] = f;
			variables[name] = f;
		} else {
			variables[name] = f;
		}
	}

	private function __cleanup () {
		structDelete(variables, "__inject");
		structDelete(this, "__inject");
		structDelete(variables, "__cleanup");
		structDelete(this, "__cleanup");
	}

	private function extendCFRedis (required target) {
		//write the injector first
		target["__inject"] = variables["__inject"];
		target["__cleanup"] = variables["__cleanup"];

		target.__inject("setNxPX", variables["__setNxPx"], true);
		target.__inject("evalWithCallback", variables["__evalWithCallback"], true);

		target.__cleanup();

		return target;
	}

}