component {

	this.name = "cfml-redlock" & hash(getCurrentTemplatePath());
	this.applicationTimeout = createTimeSpan(1, 0, 0, 0);
	//this.sessionManagement = true;
	//this.sessionTimeout = createTimeSpan(0, 1, 0, 0);

	this.javasettings = {
		loadPaths = ["./lib"],
		loadColdFusionClassPath = true,
		reloadOnChange = false,
		watchInterval = 60,
		watchExtensions = "jar,class"
	};

	boolean function onApplicationStart () {
		//you do not have to lock the application scope
		//you CANNOT access the variables scope
		//uncaught exceptions or returning false will keep the application from starting
			//and CF will not process any pages, onApplicationStart() will be called on next request

		appInit();

		return true;
	}

/*
	void function onError (any exception, string eventName) {
		//You CAN display a message to the user if an error occurs during an
			//onApplicationStart, onSessionStart, onRequestStart, onRequest,
			//or onRequestEnd event method, or while processing a request.
		//You CANNOT display output to the user if the error occurs during an
			//onApplicationEnd or onSessionEnd event method, because there is
			//no available page context; however, it can log an error message.

		writedump(arguments);
		abort;
	}
*/

	void function onSessionStart () {
		//do not need to lock session scope

	}

	void function onSessionEnd (sessionScope, applicationScope) {
		//you cannot access session scope directly, use arguments.sessionScope
		//you cannot access the application scope directly, use arguments.applicationScope
		//you cannot access the request scope
		//you do not need to lock the session scope
		//you CANNOT be guarenteed this method will run
	}

	boolean function onRequestStart (targetPage) {
		//you cannot access the variables scope
		//you CAN access the request scope

		//include "globalFunctions.cfm";

		if (!isNull(url.reinit) && url.reinit == true) {
			appInit();
		}



		//returning false would stop processing the request
		return true;
	}

	void function onRequestEnd (targetPage) {
		//you can access page context
		//you can generate output
		//you cannot access the variables scope
		//you CAN access the request scope

	}


	function appInit () {

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

		lock scope="application" type="exclusive" timeout="1" throwOnTimeout=true {
			application.redis = local.redis;
		}
	}





}