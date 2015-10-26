component skip="true" {
	this.name = "cfml-redlock-tests" & hash(getCurrentTemplatePath());

	this.mappings["/lib"] = expandPath("../lib");
	this.mappings["/com"] = expandPath("../com");

	this.javasettings = {
		loadPaths = ["../lib"],
		loadColdFusionClassPath = true,
		reloadOnChange = false,
		watchInterval = 60,
		watchExtensions = "jar,class"
	};
}