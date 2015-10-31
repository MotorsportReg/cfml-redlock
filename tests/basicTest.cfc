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

			it("should lock a resource", function() {
				var resource = resource & createUUID();

				redlock.lock(resource, 200, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);
				});
			});

			it("should wait until a lock expires before issuing another lock", function() {
				var resource = resource & createUUID();
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 2,
					retryDelay: 150
				});

				redlock.lock(resource, 200, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					redlock.lock(resource, 800, function(err, lock2) {
						if (len(err)) throw(err);
						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixtime());
						expect(unixTime() + 1).toBeGT(lock.expiration);
					});
				});
			});

			it("should time out if lock takes too long to aquire", function() {
				var resource = resource & createUUID();
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 2,
					retryDelay: 150
				});

				redlock.lock(resource, 350, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					redlock.lock(resource, 800, function(err, lock2) {
						expect(err).notToBeEmpty();
						expect(isNull(lock2)).toBeTrue();
					});
				});
			});

			it("should unlock a resource", function() {
				var resource = resource & createUUID();

				redlock.lock(resource, 1000, function(err, lock) {
					if (len(err)) throw(err);

					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);
					lock.unlock();
					expect(lock.expiration).toBe(0);

					redlock.lock(resource, 1000, function(err, lock2) {
						if (len(err)) throw(err);
						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixtime());
						expect(unixTime() + 1).toBeGT(lock.expiration);
						lock2.unlock();
						expect(lock2.expiration).toBe(0);
					});
				});
			});

			it("should silently fail to unlock an already-unlocked resource", function() {
				var resource = resource & createUUID();

				redlock.lock(resource, 200, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime() - 1);

					redlock.lock(resource, 800, function(err, lock2) {
						if (len(err)) throw(err);
						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixtime() - 1);
						expect(unixTime() + 1).toBeGT(lock.expiration);
						lock2.unlock();
						lock2.unlock();
					});
				});
			});

			it("should allow the lock to be extended", function() {
				var resource = resource & createUUID();
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 2,
					retryDelay: 150
				});

				redlock.lock(resource, 200, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					lock.extend(500, function(err, lock2){
						if (len(err)) throw(err);
						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixtime());

						redlock.lock(resource, 800, function(err, lock3) {
							expect(err).notToBeEmpty();
							expect(isNull(lock3)).toBeTrue();
						});
					});


				});
			});

			it("should fail to extend an already unlocked resource", function() {
				var resource = resource & createUUID();
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 2,
					retryDelay: 150
				});

				redlock.lock(resource, 1000, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					lock.unlock();

					lock.extend(500, function(err2, lock2){
						expect(len(err2)).notToBe(0, "Should have thrown an error!" & err2);
						expect(isNull(lock2)).toBeTrue();
					});


				});
			});

			it("should issue another lock immediately after a resource is unlocked", function(){
				var resource = resource & createUUID();
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 2,
					retryDelay: 150
				});

				var tc = getTickCount();

				redlock.lock(resource, 100, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());


					redlock.lock(resource, 500, function(err2, lock2){
						if (len(err2)) throw(err);

						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixTime());
						//the expiration for this lock should be between tc + 100 + 500 and tc + 100 + 500 + 100(leeway);
						expect(lock2.expiration).toBeBetween(tc + 100 + 500, tc + 100 + 500 + 100);
					});


				});
			});

			it("should fail after the maximum retry count is exceeded", function() {
				var resource = resource & createUUID();
				//3 retries of 200 would be up to 600ms timeout
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 3,
					retryDelay: 200
				});

				//this should error because 700 > 600 timeout
				redlock.lock(resource, 700, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					redlock.lock(resource, 500, function(err2, lock2){
						expect(len(err2)).notToBe(0, "Should have thrown an error!" & err2);
						expect(isNull(lock2)).toBeTrue();
					});
				});

				var tc = getTickCount();

				//this should succeed because 550 <= 600 timeout
				redlock.lock(resource, 550, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					redlock.lock(resource, 500, function(err2, lock2){
						if (len(err2)) throw(err);

						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixTime());
						//the expiration for this lock should be between tc + 550 + 500 and tc + 550 + 500 + 300(leeway);
						expect(lock2.expiration).toBeBetween(tc + 550 + 500, tc + 550 + 500 + 300, lock2.expiration-tc);
					});
				});

			});

			it("should issue another lock immediately after a resource is expired", function(){
				var resource = resource & createUUID();
				//3 retries of 200 would be up to 600ms timeout
				var redlock = new com.redlock(getRedisClients(), {
					retryCount: 3,
					retryDelay: 200,
					debugEnabled: false
				});

				var tc = getTickCount();

				//this should succeed because 550 <= 600 timeout
				redlock.lock(resource, 550, function(err, lock) {
					if (len(err)) throw(err);
					expect(lock).toBeStruct();
					expect(lock.expiration).toBeGT(unixtime());

					redlock.lock(resource, 500, function(err2, lock2){
						if (len(err2)) throw(err);

						expect(lock2).toBeStruct();
						expect(lock2.expiration).toBeGT(unixTime());
						//the expiration for this lock should be between tc + 550 + 500 and tc + 550 + 500 + 100(leeway);
						expect(lock2.expiration).toBeBetween(tc + 550 + 500, tc + 550 + 500 + 100, lock2.expiration-tc);
					});
				});
			});

		});
	}


}