package main

import "github.com/microsoft/documentdb-operator/plugins/documentdb-kubectl-plugin/cmd"

// version is set at build time
var version = "dev"

func main() {
	cmd.Execute(version)
}
