package main

import (
	"fmt"
	"os"

	"github.com/anthonylu23/context_grabber/cli/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
