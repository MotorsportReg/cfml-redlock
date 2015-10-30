component extends="testbox.system.BaseSpec" {


	private numeric function unixtime () {
		return createObject("java", "java.lang.System").currentTimeMillis();
	}

	private function getRedisClients () {
		local.redisHost = "localhost";  // redis server hostname or ip address
		local.redisPort = 6379;         // redis server ip address

		// Configure connection pool
		local.jedisPoolConfig = CreateObject("java", "redis.clients.jedis.JedisPoolConfig");

		//writedump(local.jedisPoolConfig.getFields());
		//writedump(getMetaData(local));abort;

		local.jedisPoolConfig.init();
		local.jedisPoolConfig.testOnBorrow = false;
		local.jedisPoolConfig.testOnReturn = false;
		local.jedisPoolConfig.testWhileIdle = true;
		//local.jedisPoolConfig.maxActive = 100;
		local.jedisPoolConfig.maxIdle = 5;
		local.jedisPoolConfig.numTestsPerEvictionRun = 10;
		local.jedisPoolConfig.timeBetweenEvictionRunsMillis = 10000;
		local.jedisPoolConfig.maxWaitMillis = 30000;

		local.jedisPool = CreateObject("java", "redis.clients.jedis.JedisPool");
		local.jedisPool.init(local.jedisPoolConfig, local.redisHost, local.redisPort);

		// The "cfc.cfredis" component name will change depending on where you put cfredis
		local.redis = CreateObject("component", "lib.cfredis").init();
		local.redis.connectionPool = local.jedisPool;

		return [local.redis];
	}

	function beforeAll () {
		redlock = new com.redlock(getRedisClients(), {
			retryCount: 2,
			retryDelay: 150
		});
	}

	function afterAll () {

	}

	function run () {

		var resource = "redlock:test:resource";
		var error = "redlock:test:error";

		describe("baseline suite", function() {

			for (var c in getRedisClients()) {
				c.del(resource);
			}


			it("should throw an error if not passed any clients", function() {
				expect(function() {
					var r = new com.redlock([]);
				}).toThrow(message="cfml-redlock must be instantiated with at least one client (redis server)");

				expect(function(){
					var r = new com.redlock();
				}).toThrow(message="The parameter clients to function init is required but was not passed in.");

			});
		});

		describe("callbacks", function() {

			for (var c in getRedisClients()) {
				c.del(resource);
			}

			//gotta make this a struct because ACF once again...

			it("should lock a resource", function() {
				var resource = resource & createUUID();
				var one = false;

				redlock.lock(resource, 200, function(err, lock) {
					if (err) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);
					one = lock;
				});
			});

			it("should wait until a lock expires before issuing another lock", function() {
				var resource = resource & createUUID();
				var one = false;
				var two = false;
				var two_expiration = 0;
				redlock.lock(resource, 200, function(err, lock) {
					if (err) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);
					one = lock;

					expect(one).toBeStruct("Could not run because a required previous test failed.");
					redlock.lock(resource, 800, function(err, lock) {
						if (err) throw(err);
						expect(lock).toBeStruct();
						expect(lock.expiration).toBeGT(unixtime() - 1);
						expect(unixTime() + 1).toBeGT(one.expiration);
						two = lock;
						two_expiration = lock.expiration;
					});
				});
			});

			it("should unlock a resource", function() {
				var resource = resource & createUUID();

				redlock.lock(resource, 200, function(err, lock) {
					if (err) throw(err);

					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);
					lock.unlock();
				});
			});

			it("should silently fail to unlock an already-unlocked resource", function() {
				var resource = resource & createUUID();

				redlock.lock(resource, 200, function(err, lock) {
					if (err) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);

					expect(lock).toBeStruct("Could not run because a required previous test failed.");
					redlock.lock(resource, 800, function(err, lock2) {
						if (err) throw(err);
						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixtime() - 1);
						expect(unixTime() + 1).toBeGT(lock.expiration);


						expect(lock2).toBeStruct("Could not run because a required previous test failed.");
						lock2.unlock();

						lock2.unlock();
					});
				});
			});
/*
			it("should fail to extend a lock on an already-unlocked resource", function() {

				var resource = resource & ":fail-extend-unlock";
				var one = false;
				var two = false;
				var two_expiration = 0;



				redlock.lock(resource, 200, function(err, lock) {
					if (err) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);
					one = lock;

					//expect(true).toBeFalse();

					expect(one).toBeStruct("Could not run because a required previous test failed.");
					redlock.lock(resource, 800, function(err, lock) {
						if (err) throw(err);
						expect(lock).toBeStruct();
						expect(lock.expiration).toBeGT(unixtime() - 1);
						expect(unixTime() + 1).toBeGT(one.expiration);
						two = lock;
						two_expiration = lock.expiration;

						expect(two).toBeStruct("Could not run because a required previous test failed.");
						two.unlock();



						writedump(two);abort;

						two.extend(200, function(err, lock){
							expect(err).toBeNull();
							writedump(err);abort;
						});
					});
				});
			});
*/
		});
	}


}