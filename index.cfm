
<cfset redlock = new com.redlock([application.redis]) />

<cfdump var="#redlock#" expand="false" />

<cfscript>

	redlock.lock("locks:foobar:12345", 20000, function(err, lock) {
		if (err) throw(err);
		writedump(lock);

		lock.unlock();
	});


</cfscript>

<!---<cfdump var="#application#" expand="false"/>--->